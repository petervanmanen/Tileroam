import Foundation
import Observation

/// What `StravaSync` needs from the app's activity store.
@MainActor
protocol StravaSyncHost: AnyObject {
    /// The library's activities, to skip workouts it already has.
    var folderActivities: [Activity] { get }
    /// New files go to iCloud right away (sync on and available).
    var pushesToICloud: Bool { get }
    /// The Strava activities changed: count again (when `recount`) and save the cache.
    func stravaActivitiesChanged(recount: Bool)
    /// Reads the library again (after files were saved or deleted).
    func refresh() async
}

/// The Strava connection: login, the list of activities (with summary routes, then full GPS) and
/// saving them as .fit files into the library, webhook events (revoked access, deleted
/// activities) and rate-limit pauses.
@MainActor
@Observable
final class StravaSync {
    let config = StravaConfig.bundled
    @ObservationIgnored private var client: StravaClient?
    @ObservationIgnored weak var host: StravaSyncHost?

    /// The Strava activities (cached on the device per athlete).
    private(set) var activities: [Activity] = []
    private(set) var athlete: String?
    private(set) var athleteID: Int?
    /// What the sync is doing right now; nil when idle and up to date.
    private(set) var status: String?
    private(set) var error: String?
    /// Waiting for Strava's rate limit to reset.
    private(set) var isPaused = false
    private var task: Task<Void, Never>?
    /// Set after `deleteFiles()`, for the confirmation in Settings.
    private(set) var filesDeleted: Int?

    var isConnected: Bool { athleteID != nil }
    var isSyncing: Bool { task != nil }
    var detailedCount: Int { activities.count { $0.isSummary != true } }
    var exportedCount: Int { activities.count { $0.exportedFile != nil } }

    init() {
        guard let config else { return }
        client = StravaClient(config: config)
        if let tokens = StravaTokens.load() {
            athlete = tokens.athleteName
            athleteID = tokens.athleteID
            activities = TrackCache.load(.strava, folder: String(tokens.athleteID))
        }
    }

    /// Changes the activities in place (stored challenge, tile or climb results).
    func update(_ body: (inout Activity) -> Void) {
        for i in activities.indices { body(&activities[i]) }
    }

    func remove(ids: Set<String>) {
        activities.removeAll { ids.contains($0.id) }
    }

    /// Writes the cache (called by the store's cache writer).
    nonisolated static func save(_ activities: [Activity], athleteID: Int) {
        TrackCache.save(activities, .strava, folder: String(athleteID))
    }

    // MARK: Login

    /// Starts a login; returns the state value to send along.
    func beginLogin() async -> String? {
        await client?.beginLogin()
    }

    func completeLogin(callback: URL) async {
        guard let client else { return }
        do {
            let tokens = try await client.completeLogin(callback: callback)
            // Only events after this login matter (an old "revoked" must not undo it).
            UserDefaults.standard.set(Int(Date.now.timeIntervalSince1970), forKey: Self.eventsSinceKey(tokens.athleteID))
            athlete = tokens.athleteName
            athleteID = tokens.athleteID
            error = nil
            activities = TrackCache.load(.strava, folder: String(tokens.athleteID))
            host?.stravaActivitiesChanged(recount: true)
            sync()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func reportError(_ message: String) {
        error = message
    }

    /// Disconnects Strava and forgets its data; with `deleteFiles`, also deletes the .fit files
    /// Tileroam saved from Strava (see `deleteFiles()`).
    func disconnect(deleteFiles: Bool) async {
        await client?.disconnect()
        forget()
        if deleteFiles { await self.deleteFiles() }
    }

    /// Number of .fit files Tileroam saved from Strava in the library.
    func countFiles() async -> Int {
        await Task.detached(priority: .userInitiated) { StravaExport.ownFiles().count }.value
    }

    /// Deletes the .fit files Tileroam saved from Strava, here and in iCloud, and re-reads.
    func deleteFiles() async {
        let deleted = await Task.detached(priority: .userInitiated) {
            let names = StravaExport.ownFiles()
            Library.delete(names: names)
            return names.count
        }.value
        filesDeleted = deleted
        await host?.refresh()
    }

    /// Removes the Strava connection and its cached activities from this device.
    private func forget() {
        task?.cancel()
        task = nil
        StravaTokens.delete()
        TrackCache.clear(.strava)
        activities = []
        athlete = nil
        athleteID = nil
        status = nil
        error = nil
        host?.stravaActivitiesChanged(recount: true)
    }

    // MARK: Webhook events

    private static func eventsSinceKey(_ athleteID: Int) -> String { "stravaEventsSince-\(athleteID)" }

    /// Handles the webhook events the token service queued since the last time: access revoked
    /// (forget everything and delete the saved files), activities deleted on Strava (delete their
    /// copies). Returns false when the connection is gone.
    private func applyEvents(_ client: StravaClient, athleteID: Int) async -> Bool {
        let sinceKey = Self.eventsSinceKey(athleteID)
        guard let events = try? await client.events(since: UserDefaults.standard.integer(forKey: sinceKey)),
              let last = events.map(\.time).max() else { return true }
        UserDefaults.standard.set(last, forKey: sinceKey)
        let change = StravaEventChanges(events)
        if change.revoked {
            forget()
            await deleteFiles()
            error = String(localized: "Strava access was revoked. Tileroam removed the activities it saved from Strava.")
            return false
        }
        guard !change.removedActivities.isEmpty else { return true }
        let removed = change.removedActivities
        activities.removeAll { StravaImport.stravaID(of: $0).map(removed.contains) ?? false }
        await Task.detached(priority: .utility) {
            Library.delete(names: StravaExport.ownFiles(of: removed))
        }.value
        host?.stravaActivitiesChanged(recount: true)
        await host?.refresh()
        return true
    }

    // MARK: Sync

    /// Starts (or continues) the sync unless it is already running.
    func sync() {
        guard task == nil, isConnected, client != nil else { return }
        task = Task {
            await run()
            task = nil
        }
    }

    private func run() async {
        guard let client, let athleteID else { return }
        error = nil
        guard await applyEvents(client, athleteID: athleteID) else { return }

        while !Task.isCancelled {
            do {
                try await fetchList(client)
                try await fetchDetails(client)
                status = nil
                await host?.refresh() // read the saved files and send them to iCloud
                return
            } catch StravaError.rateLimited(let until) {
                host?.stravaActivitiesChanged(recount: false)
                isPaused = true
                defer { isPaused = false }
                status = String(localized: "Strava limit reached – continuing at \(until.formatted(date: .omitted, time: .shortened))")
                try? await Task.sleep(for: .seconds(max(1, until.timeIntervalSinceNow)))
            } catch StravaError.unauthorized {
                // Access was revoked (in Strava's settings): forget the connection and its data.
                forget()
                error = StravaError.unauthorized.localizedDescription
                return
            } catch {
                host?.stravaActivitiesChanged(recount: false)
                status = nil
                if !Task.isCancelled { self.error = error.localizedDescription }
                return
            }
        }
    }

    /// New activities since the latest known one (everything on the first sync), with summary routes.
    private func fetchList(_ client: StravaClient) async throws {
        // Caches from before virtual detection, or before moving time and power were kept
        // (detailsVersion): fetch the whole list once to fill them in.
        let needsVirtualFlags = activities.contains { $0.isVirtual == nil }
        let needsDetails = activities.contains { $0.detailsVersion != Activity.currentDetails }
        let after = needsVirtualFlags || needsDetails ? nil : activities.compactMap(\.startDate).max()?.addingTimeInterval(-24 * 3600)
        var known = Set(activities.map(\.id))
        var page = 1
        while !Task.isCancelled {
            status = known.isEmpty ? String(localized: "Fetching Strava activities…") : String(localized: "Checking Strava for new activities…")
            let summaries = try await client.activities(page: page, after: after)
            if needsVirtualFlags {
                let virtual = Dictionary(summaries.map { (StravaImport.id(for: $0.id), StravaImport.isVirtual($0)) },
                                         uniquingKeysWith: { a, _ in a })
                for i in activities.indices {
                    guard let flag = virtual[activities[i].id] else { continue }
                    activities[i].isVirtual = flag
                    if flag { activities[i].isSummary = false } // no GPS to download for virtual rides
                }
            }
            if needsDetails {
                let details = Dictionary(summaries.map { (StravaImport.id(for: $0.id), $0) }, uniquingKeysWith: { a, _ in a })
                var changed = false
                for i in activities.indices where activities[i].detailsVersion != Activity.currentDetails {
                    guard let s = details[activities[i].id] else { continue }
                    StravaImport.applyDetails(s, to: &activities[i])
                    changed = true
                }
                if changed { host?.stravaActivitiesChanged(recount: true) }
            }
            let deleted = Deletions.stravaIDs()
            let new = await Task.detached(priority: .userInitiated) {
                summaries.filter { !deleted.contains($0.id) }.map(StravaImport.activity(from:))
            }.value.filter { !known.contains($0.id) }
            if !new.isEmpty {
                activities += new
                known.formUnion(new.map(\.id))
                host?.stravaActivitiesChanged(recount: true)
            }
            if summaries.count < 200 {
                if needsDetails {
                    // The whole list was read: activities Strava didn't list (deleted there) have no
                    // details to add; mark them, or every sync would read the whole list again.
                    for i in activities.indices where activities[i].detailsVersion != Activity.currentDetails {
                        activities[i].detailsVersion = Activity.currentDetails
                    }
                    host?.stravaActivitiesChanged(recount: false)
                }
                break
            }
            page += 1
        }
    }

    /// Downloads full GPS for summary-only activities (most recent first) and saves every Strava
    /// activity as a .fit file in the library. Activities the library already has (same start
    /// time) are skipped to save API calls and avoid duplicates.
    private func fetchDetails(_ client: StravaClient) async throws {
        let folder = host?.folderActivities ?? []
        let inFolderWithGPS = ActivityMerge.Index(folder.filter { !$0.trackData.isEmpty })
        let inFolder = ActivityMerge.Index(folder)

        // "Saved" activities whose file isn't in the library (saved before 1.3 into a save folder
        // whose files never reached the library, or removed elsewhere): save them again, unless the
        // library has another copy of the workout, with GPS when the Strava activity has GPS (a
        // Health export without a route doesn't count: issue of 1.8.2, where the Mac missed 787
        // routes). Otherwise they'd never reach iCloud and the user's other devices.
        let present = await Task.detached(priority: .utility) { Library.names(in: Library.activitiesFolder, ext: "fit") }.value
        var resaved = 0
        for i in activities.indices {
            let a = activities[i]
            guard let file = a.exportedFile, !present.contains(file),
                  !(a.trackData.isEmpty ? inFolder : inFolderWithGPS).contains(a) else { continue }
            activities[i].exportedFile = nil
            resaved += 1
        }
        if resaved > 0 { host?.stravaActivitiesChanged(recount: false) }
        defer {
            // New files go to iCloud now, not only at the next refresh.
            if host?.pushesToICloud == true {
                Task.detached(priority: .utility) { Library.push() }
            }
        }
        defer { host?.stravaActivitiesChanged(recount: true) }

        // Activities without GPS: export needs no API calls.
        let noGPS = activities.indices.filter {
            let a = activities[$0]
            return a.trackData.isEmpty && a.exportedFile == nil && !inFolder.contains(a)
        }
        for (n, index) in noGPS.enumerated() {
            if Task.isCancelled { return }
            status = String(localized: "Saving Strava activities to folder: \(n) of \(noGPS.count)")
            await export(index, stream: nil)
        }

        let queue = activities
            .filter { a in
                !a.trackData.isEmpty && !inFolderWithGPS.contains(a)
                    && (a.isSummary == true || a.exportedFile == nil)
            }
            .sorted { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }

        for (done, activity) in queue.enumerated() {
            if Task.isCancelled { return }
            status = String(localized: "Strava detailed GPS: \(done) of \(queue.count)")
            if activity.isSummary != true {
                // The detailed track is on the device already: saved without an API call.
                if let index = activities.firstIndex(where: { $0.id == activity.id }) { await export(index, stream: nil) }
                continue
            }
            guard let stravaID = StravaImport.stravaID(of: activity) else { continue }
            let stream = try await client.stream(activityID: stravaID)
            let updated = await Task.detached(priority: .utility) {
                activity.isSummary == true ? StravaImport.detailed(activity, points: stream?.points) : activity
            }.value
            guard let index = activities.firstIndex(where: { $0.id == activity.id }) else { continue }
            activities[index] = updated
            await export(index, stream: stream)
            if (done + 1) % 25 == 0 { host?.stravaActivitiesChanged(recount: true) }
        }
    }

    private func export(_ index: Int, stream: StravaStream?) async {
        let activity = activities[index]
        do {
            let name = try await Task.detached(priority: .utility) {
                try StravaExport.write(activity, stream: stream)
            }.value
            if let i = activities.firstIndex(where: { $0.id == activity.id }) {
                activities[i].exportedFile = name
            }
        } catch {
            self.error = String(localized: "Could not save the activity: \(error.localizedDescription)")
        }
    }
}
