import Foundation
import Observation
import StoreKit
import WidgetKit

/// What `GarminSync` needs from the app's activity store.
@MainActor
protocol GarminSyncHost: AnyObject {
    /// Reads the library again (after files were saved or deleted).
    func refresh() async
    /// Activity names changed (`ActivityNames`): show them.
    func activityNamesChanged()
}

/// The Garmin Connect connection: the user's personal API key (in the Keychain), and the original
/// .fit file of each activity, downloaded once into the library, where Tileroam reads it like any
/// other file (and merges it with the same workout from Strava or HealthFit). The first sync goes
/// through the whole history; later ones stop at the first activity it already has. An activity
/// downloaded once isn't downloaded again, also not after the user deleted its file.
///
/// Garmin's Personal API is meant for a person's own data, "not for commercial applications serving
/// multiple end users", so it's on in Debug and TestFlight builds only (`availability`) until
/// `FeatureFlags.garminInAppStore` is turned on.
@MainActor
@Observable
final class GarminSync {
    @ObservationIgnored weak var host: GarminSyncHost?

    /// The connection is offered in this build (see `availability`).
    private(set) var isAvailable = false
    private(set) var isConnected: Bool
    private(set) var isConnecting = false
    /// What the sync is doing; nil when idle.
    private(set) var status: String?
    private(set) var error: String?
    /// Activities downloaded from Garmin (those that had a .fit file).
    private(set) var downloadedCount: Int
    private var task: Task<Void, Never>?
    var isSyncing: Bool { task != nil }
    /// A sync the user started goes on when they leave the app (see `ContinuedWork`).
    @ObservationIgnored private var continued: ContinuedWork? {
        didSet { continuesInBackground = continued != nil }
    }
    /// The running sync goes on when the user leaves the app (shown in Settings).
    private(set) var continuesInBackground = false
    /// Why it couldn't go on in the background, if iOS refused.
    private(set) var backgroundError: String?
    /// The last progress, for a background task that's attached to a running sync.
    @ObservationIgnored private var lastProgress = (added: 0, left: 0)

    /// What was downloaded, kept on the device: per Garmin activity ID the file name in the
    /// library ("" for an activity without a .fit file), and whether the whole history was seen.
    struct State: Codable, Equatable {
        var files: [String: String] = [:]
        var historyComplete = false
        /// Per Garmin activity ID the name last seen on Garmin Connect (renames are picked up).
        var names: [String: String] = [:]
        /// The whole list was gone through once for names (activities downloaded before 1.18).
        var namesChecked = false

        init() {}

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            files = try c.decodeIfPresent([String: String].self, forKey: .files) ?? [:]
            historyComplete = try c.decodeIfPresent(Bool.self, forKey: .historyComplete) ?? false
            names = try c.decodeIfPresent([String: String].self, forKey: .names) ?? [:]
            namesChecked = try c.decodeIfPresent(Bool.self, forKey: .namesChecked) ?? false
        }
    }

    struct Environment {
        var session: URLSession = .shared
        var base: URL = GarminClient.baseURL
        /// Saves a .fit file into the library; returns its name there.
        var save: @Sendable (Data, String) throws -> String = { try Library.add($0, originalName: $1) }
        var delete: @Sendable ([String]) -> Void = { Library.delete(names: $0) }
        /// Stores activity names per library file (`ActivityNames`); returns whether any changed.
        var setNames: ([String: String]) -> Bool = { ActivityNames.set($0) }
        /// The key is in the Keychain group shared with the widgets (1.16 kept it to the app).
        var loadKey: () -> String? = {
            if let key = GarminHealthStore.key { return key }
            guard let legacy = Keychain.load(account: GarminSync.keyAccount) else { return nil }
            Keychain.delete(account: GarminSync.keyAccount)
            Keychain.save(legacy, account: GarminSync.keyAccount, accessGroup: Keychain.sharedGroup)
            return String(decoding: legacy, as: UTF8.self)
        }
        var storeKey: (String?) -> Void = { key in
            GarminHealthStore.clear()
            if let key {
                Keychain.save(Data(key.utf8), account: GarminSync.keyAccount, accessGroup: Keychain.sharedGroup)
            } else {
                Keychain.delete(account: GarminSync.keyAccount, accessGroup: Keychain.sharedGroup)
            }
            GarminHealthStore.widgetKinds.forEach { WidgetCenter.shared.reloadTimelines(ofKind: $0) }
        }
        var defaults: UserDefaults = .standard
        /// Between two downloads: Garmin doesn't publish its rate limits, so a long history is
        /// downloaded at a calm pace (2,000 activities take about 35 minutes).
        var pause: Duration = .seconds(1)
        var sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    }

    nonisolated static let keyAccount = GarminHealthStore.keyAccount
    private static let stateKey = "garminState"
    /// Activities per page of the list.
    static let pageSize = 100
    /// How long to wait after a 429 without Retry-After, and the longest wait Tileroam accepts.
    static let defaultWait: TimeInterval = 5 * 60
    static let longestWait: TimeInterval = 60 * 60
    /// 429s in a row after which the sync stops until the next one.
    static let maxWaits = 5

    @ObservationIgnored private let environment: Environment
    @ObservationIgnored private var client: GarminClient?

    init(environment: Environment = Environment()) {
        self.environment = environment
        let key = environment.loadKey()
        isConnected = key != nil
        state = environment.defaults.data(forKey: Self.stateKey).flatMap { try? JSONDecoder().decode(State.self, from: $0) } ?? State()
        downloadedCount = state.files.values.count { !$0.isEmpty }
        if let key { client = makeClient(key) }
    }

    private func makeClient(_ key: String) -> GarminClient {
        GarminClient(key: key, session: environment.session, base: environment.base)
    }

    @ObservationIgnored private var state: State

    /// Writes `state` to the device (after each page and every 10 downloads: with thousands of
    /// activities, writing it after every one would add up).
    private func saveState() {
        environment.defaults.set(try? JSONEncoder().encode(state), forKey: Self.stateKey)
        downloadedCount = state.files.values.count { !$0.isEmpty }
    }

    // MARK: Availability

    /// Whether this build offers the connection: Debug builds and TestFlight (the App Store's
    /// sandbox environment), or every build once `FeatureFlags.garminInAppStore` is on.
    nonisolated static func availability() async -> Bool {
        #if DEBUG
        return true
        #else
        if FeatureFlags.garminInAppStore { return true }
        guard case .verified(let transaction)? = try? await AppTransaction.shared else { return false }
        return transaction.environment == .sandbox || transaction.environment == .xcode
        #endif
    }

    func checkAvailability() async {
        isAvailable = await Self.availability()
    }

    // MARK: Connecting

    /// Checks the key with Garmin (by asking for an access token), keeps it and starts a sync.
    /// Returns whether it worked; `error` says why not.
    @discardableResult
    func connect(key raw: String) async -> Bool {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return false }
        isConnecting = true
        defer { isConnecting = false }
        let client = makeClient(key)
        do {
            _ = try await client.accessToken()
        } catch {
            self.error = (error as? GarminError).map(\.localizedDescription) ?? error.localizedDescription
            return false
        }
        environment.storeKey(key)
        self.client = client
        isConnected = true
        error = nil
        sync(userInitiated: true)
        return true
    }

    /// Forgets the key; with `deleteFiles`, also deletes the files downloaded from Garmin (on all
    /// devices, with iCloud).
    func disconnect(deleteFiles: Bool) async {
        task?.cancel()
        task = nil
        let names = state.files.values.filter { !$0.isEmpty }
        environment.storeKey(nil)
        client = nil
        isConnected = false
        status = nil
        error = nil
        state = State()
        saveState()
        if deleteFiles, !names.isEmpty {
            let delete = environment.delete
            await Task.detached(priority: .userInitiated) { delete(Array(names)) }.value
            await host?.refresh()
        }
    }

    // MARK: Sync

    /// Starts a sync unless one is running. One the user started (connecting, Sync Now) may go on
    /// in the background, with its progress in a Live Activity; the automatic one when the app
    /// opens runs while it's open (iOS only lets work the user asked for go on).
    func sync(userInitiated: Bool = false) {
        guard client != nil else { return }
        guard task == nil else {
            // Already running (the sync on opening the app): the user asks for it, so it may go on.
            if userInitiated { continueInBackground() }
            return
        }
        if userInitiated { continueInBackground() }
        task = Task {
            await run()
            task = nil
            continued?.finish(success: error == nil)
            continued = nil
        }
    }

    /// Lets the sync go on when the user leaves the app (iOS 26 continued processing, with a Live
    /// Activity); for a sync that's starting or already running. Only on the user's request:
    /// iOS doesn't allow it for work the user didn't ask for, such as the sync on opening the app.
    func continueInBackground() {
        guard continued == nil, ContinuedWork.isSupported else { return }
        switch ContinuedWork.start(title: String(localized: "Garmin Connect"),
                                   subtitle: String(localized: "Checking Garmin Connect…"), onExpire: { [weak self] in
            self?.task?.cancel() // stopped in the Live Activity: what's downloaded is kept
        }) {
        case .success(let work):
            continued = work
            backgroundError = nil
            if task != nil { report(lastProgress.added, left: lastProgress.left) }
        case .failure(let failure):
            backgroundError = failure.localizedDescription
        }
    }

    /// Progress for the Live Activity: done so far, and an estimate of what's left.
    private func report(_ added: Int, left: Int) {
        lastProgress = (added, left)
        guard let continued else { return }
        continued.progress(done: added, total: added + left,
                           subtitle: String(localized: "Downloaded \(added) activities"))
    }

    /// Goes through the activity list, newest first, and downloads the activities it doesn't
    /// have. Stops at the first page with known activities once the whole history was seen, at
    /// the end of the list, or at an error (it continues from there next time).
    func run() async {
        guard let client else { return }
        error = nil
        var added = 0
        defer {
            saveState()
            status = nil
            if added > 0 { Task { await host?.refresh() } }
        }
        var start = 0
        do {
            while !Task.isCancelled {
                let page = try await patiently {
                    status = String(localized: "Checking Garmin Connect…")
                    return try await client.activities(start: start, limit: Self.pageSize)
                }
                guard !page.isEmpty else {
                    state.historyComplete = true
                    state.namesChecked = true
                    break
                }
                let known = state.files
                let new = page.filter { known[String($0.activityId)] == nil }
                updateNames(page.filter { known[String($0.activityId)] != nil })
                // Left: this page's new ones, and a page more while the history isn't complete.
                let more = state.historyComplete || page.count < Self.pageSize ? 0 : Self.pageSize
                report(added, left: new.count + more)
                for (n, activity) in new.enumerated() {
                    guard !Task.isCancelled else { return }
                    let name = try await patiently {
                        status = String(localized: "Downloading from Garmin: \(downloadedCount + 1)")
                        return try await download(activity, with: client)
                    }
                    state.files[String(activity.activityId)] = name ?? ""
                    if name != nil { added += 1 }
                    updateNames([activity])
                    report(added, left: new.count - n - 1 + more)
                    if added % 10 == 0 { saveState() } else { downloadedCount += name != nil ? 1 : 0 }
                    try await environment.sleep(environment.pause)
                }
                saveState()
                if page.count < Self.pageSize {
                    state.historyComplete = true
                    state.namesChecked = true
                    break
                }
                // Reached what it has; once, the whole list is gone through for renamed activities.
                if state.historyComplete && state.namesChecked && new.count < page.count { break }
                start += page.count
            }
        } catch is CancellationError {
            // Disconnected.
        } catch {
            self.error = (error as? GarminError).map(\.localizedDescription) ?? error.localizedDescription
        }
    }

    /// Takes the names on Garmin Connect of activities in the library: new ones, and renamed
    /// ones (`ActivityNames`, shown on all devices).
    private func updateNames(_ activities: [GarminActivity]) {
        var changed = [String: String]()
        for activity in activities {
            let id = String(activity.activityId)
            guard let name = activity.activityName?.trimmingCharacters(in: .whitespaces), !name.isEmpty,
                  let file = state.files[id], !file.isEmpty, state.names[id] != name else { continue }
            state.names[id] = name
            changed[file] = name
        }
        guard !changed.isEmpty, environment.setNames(changed) else { return }
        host?.activityNamesChanged()
    }

    /// Runs `request`; when Garmin asks to slow down (429), waits as long as it says (five
    /// minutes when it doesn't say) and tries again, up to `maxWaits` times in a row.
    private func patiently<T>(_ request: () async throws -> T) async throws -> T {
        var waits = 0
        while true {
            do {
                return try await request()
            } catch GarminError.rateLimited(let retryAfter) where waits < Self.maxWaits {
                waits += 1
                let delay = min(max(retryAfter ?? Self.defaultWait, 1), Self.longestWait)
                let until = Date.now.addingTimeInterval(delay)
                status = String(localized: "Garmin limit reached – continuing at \(until.formatted(date: .omitted, time: .shortened))")
                try await environment.sleep(.seconds(delay))
            }
        }
    }

    /// Downloads one activity's original file and saves its .fit file; nil when there is none
    /// (an activity entered by hand, or uploaded as GPX or TCX).
    private func download(_ activity: GarminActivity, with client: GarminClient) async throws -> String? {
        let archive = try await client.originalFile(activity.activityId)
        let save = environment.save
        let original = Self.fileName(activity)
        return try await Task.detached(priority: .utility) {
            guard let fit = Self.fitFile(in: archive) else { return nil }
            return try save(fit, original)
        }.value
    }

    /// The .fit file in Garmin's download: inside the ZIP, or the download itself when it is one.
    nonisolated static func fitFile(in download: Data) -> Data? {
        if download.count >= 12, download[download.startIndex + 8..<download.startIndex + 12] == Data(".FIT".utf8) {
            return download
        }
        return (try? Zip.firstFile(withExtension: "fit", in: download)) ?? nil
    }

    /// "2026-10-20 Morning Ride Garmin 123456.fit": the date, the name and the ID (the library
    /// adds a short content hash).
    nonisolated static func fileName(_ activity: GarminActivity) -> String {
        let date = activity.startTimeLocal.map { String($0.prefix(10)) }
        let name = activity.activityName?.trimmingCharacters(in: .whitespaces)
        return [date, name.flatMap { $0.isEmpty ? nil : $0 }, "Garmin \(activity.activityId)"].compactMap { $0 }
            .joined(separator: " ") + ".fit"
    }
}
