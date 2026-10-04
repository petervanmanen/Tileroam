import Foundation
import Observation

@MainActor
@Observable
final class ActivityStore {
    /// All activities from all sources, with duplicates merged.
    private(set) var activities: [Activity] = []
    private(set) var tiles14: Set<Int64> = []
    private(set) var tiles17: Set<Int64> = []
    private(set) var tileStats14 = SquareStats()
    private(set) var tileStats17 = SquareStats()
    private var statsTask: Task<Void, Never>?
    /// Max square/cluster have been computed for the current activities.
    private(set) var statsReady = false
    private(set) var visitedMunicipalities: Set<String> = []
    private(set) var visitedPostcodes: Set<String> = []
    private(set) var eddingtonCycling = Eddington()
    private(set) var eddingtonRunning = Eddington()
    private(set) var eddingtonWalking = Eddington()
    /// Incremented whenever the map data changes.
    private(set) var version = 0

    // Files: the app's library (Library.activitiesFolder) and the sample rides
    private(set) var folderActivities: [Activity] = []
    private(set) var isImporting = false
    private(set) var progress: (done: Int, total: Int) = (0, 0)
    private(set) var failedFiles: [String] = []
    /// What the last import, migration or deletion did, for Settings.
    private(set) var libraryMessage: String?
    /// For each listed activity, the ids of all its copies (the same workout from several
    /// sources), so deleting it deletes them all.
    private(set) var copies: [String: [String]] = [:]

    /// Tileroam's iCloud Drive folder is available (signed in, iCloud Drive on).
    private(set) var isICloudAvailable = false
    /// iCloud already has activities: a further device shows them instead of asking how to add
    /// activities.
    private(set) var iCloudHasActivities = false

    /// Settings → "Sync with iCloud" (on by default). Turning it off keeps the copies in iCloud.
    var isICloudSyncOn: Bool {
        get { syncSetting }
        set {
            syncSetting = newValue
            UserDefaults.standard.set(newValue, forKey: Library.syncSettingKey)
            if newValue { Task { await refresh() } }
        }
    }
    private var syncSetting = Library.isSyncOn

    /// Number of activity files in the library on this device.
    var libraryFileCount: Int { folderActivities.count { $0.id.hasPrefix(Self.libraryPrefix) } }

    static let libraryPrefix = "lib|"
    static let samplePrefix = "sample|"

    // Climbs (see ClimbData)
    /// The climbs downloaded so far, by id: around the activities, the map and plans.
    private(set) var climbs: [String: Climb] = [:]
    /// For each climbed climb, when (newest first).
    private(set) var climbed: [String: [Date]] = [:]
    private var isMatchingClimbs = false

    // Trappist Challenge (see Trappist, TrappistData)
    /// The breweries, from R2 (the copy on the device until the download is checked).
    private(set) var trappists: [Trappist] = TrappistData.cached()
    /// For each visited brewery, when (newest first).
    private(set) var trappistVisits: [String: [Date]] = [:]
    private var trappistTask: Task<Void, Never>?

    /// How often each badge was earned (see `BadgeRules`); indoor activities count too.
    private(set) var badges: [Badge: Int] = [:]
    private var badgeTask: Task<Void, Never>?

    // Strava source
    let stravaConfig = StravaConfig.bundled
    private var strava: StravaClient?
    private(set) var stravaActivities: [Activity] = []
    private(set) var stravaAthlete: String?
    private var stravaAthleteID: Int?
    /// What the Strava sync is doing right now; nil when idle and up to date.
    private(set) var stravaStatus: String?
    private(set) var stravaError: String?
    /// Waiting for Strava's rate limit to reset.
    private(set) var isStravaPaused = false
    private var stravaTask: Task<Void, Never>?

    // Municipalities and postcodes
    /// Boundaries of the switched-on countries; loaded in the background, nil until ready.
    private(set) var regions: RegionData?
    private(set) var isLoadingRegions = false
    private var regionsTask: Task<Void, Never>?
    private static let countriesKey = "enabledCountries"

    /// Countries whose municipalities and postcodes are shown and counted.
    private(set) var enabledCountries: Set<String> = []

    var municipalityAreas: AreaSet? { regions?.municipalities }
    var postcodeAreas: AreaSet? { regions?.postcodes }

    /// Waits for the region boundaries (those that could be downloaded).
    func loadedRegions() async -> RegionData {
        while true {
            if let regions, !isLoadingRegions { return regions }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    /// Visited/total per country for a kind of area.
    func regionCounts(_ kind: AreaKind) -> [String: (visited: Int, total: Int)] {
        guard let areas = regions?.areas(kind) else { return [:] }
        let visited = kind == .municipalities ? visitedMunicipalities : visitedPostcodes
        let visitedByCountry = Dictionary(grouping: visited, by: { String($0.prefix { $0 != ":" }) }).mapValues(\.count)
        return areas.countByCountry().reduce(into: [:]) { $0[$1.key] = (visitedByCountry[$1.key] ?? 0, $1.value) }
    }

    /// Set when the boundaries of some countries couldn't be downloaded; retried on the next refresh.
    private(set) var regionsError: String?
    /// Apple's error for the first failed country, shown in small print for diagnosis.
    private(set) var regionsErrorDetail: String?
    /// Countries whose boundaries couldn't be downloaded.
    private var regionsFailed = Set<String>()

    /// Tries the failed downloads again (the "Try Again" button).
    func retryRegions() {
        guard !isLoadingRegions else { return }
        loadRegions()
    }

    private func loadRegions() {
        regionsTask?.cancel()
        isLoadingRegions = true
        let countries = enabledCountries
        regionsTask = Task {
            // Boundaries are Apple-hosted asset packs: download the missing countries first.
            let availability = await RegionAssets.makeAvailable(countries)
            guard !Task.isCancelled else { return }
            let data = await Task.detached(priority: .userInitiated) {
                RegionData.load(countries: availability.available)
            }.value
            guard !Task.isCancelled else { return }
            regions = data
            regionsFailed = Set(availability.failed.keys)
            let failedNames = availability.failed.keys.compactMap { Country.named($0)?.name }.sorted()
            regionsError = failedNames.isEmpty ? nil : String(localized:
                "Couldn't load the municipalities and postcodes of \(failedNames.formatted(.list(type: .and))). Tileroam tries again when you open it.")
            regionsErrorDetail = availability.failed.sorted { $0.key < $1.key }.first.map { "\($0.key): \($0.value)" }
            isLoadingRegions = false
            version += 1
            backfillDerived()
        }
    }

    private var countryScannedIDs = Set<String>()

    private func chooseInitialCountries() {
        if let saved = UserDefaults.standard.stringArray(forKey: Self.countriesKey) {
            // Earlier versions had more countries; their boundaries are no longer available.
            enabledCountries = Set(saved).filter { Country.named($0) != nil }
        }
        // Countries follow the activities: drop any without visits after the first count
        // (earlier versions let the user switch countries on by hand).
        pruneCountriesAfterCount = true
        detectCountries(load: false)
        if enabledCountries.isEmpty {
            // No activities yet: show the phone's region.
            let region = Locale.current.region?.identifier ?? "NL"
            enabledCountries = [Country.named(region) != nil ? region : "NL"]
        }
    }

    /// Switches on the countries new activities pass through, using the bundled outlines (or,
    /// without them, bounding boxes). Countries found near a border without a visited
    /// municipality are dropped again after the next count.
    private func detectCountries(load: Bool = true) {
        let new = (folderActivities + stravaActivities).filter { !countryScannedIDs.contains($0.id) && $0.isVirtual != true }
        countryScannedIDs.formUnion(new.map(\.id))
        let tracks = new.map { $0.coordinates.map { GeoPoint(lat: $0.latitude, lon: $0.longitude) } }
        var found = Set<String>()
        if let outlines = CountryOutlines.bundled {
            found = outlines.countries(visitedBy: tracks)
        } else {
            for track in tracks {
                for p in track.enumerated().filter({ $0.offset % max(1, track.count / 8) == 0 }).map(\.element) {
                    for country in Country.all where country.contains(p) { found.insert(country.code) }
                }
            }
        }
        let updated = enabledCountries.union(found)
        guard updated != enabledCountries else { return }
        enabledCountries = updated
        pruneCountriesAfterCount = true
        UserDefaults.standard.set(Array(updated).sorted(), forKey: Self.countriesKey)
        if load { loadRegions() }
    }

    private var pruneCountriesAfterCount = false

    /// After the first count: keep only countries with visited municipalities (plus the phone's region).
    private func pruneUnvisitedCountries() {
        // Wait until every country is loaded, except those whose download failed.
        guard pruneCountriesAfterCount, let regions,
              Set(regions.countries) == enabledCountries.subtracting(regionsFailed) else { return }
        pruneCountriesAfterCount = false
        guard let keep = CountrySelection.pruned(enabled: enabledCountries, visitedMunicipalities: visitedMunicipalities,
                                                 failed: regionsFailed) else { return }
        enabledCountries = keep
        UserDefaults.standard.set(Array(keep).sorted(), forKey: Self.countriesKey)
        loadRegions()
    }

    var isStravaConnected: Bool { stravaAthleteID != nil }
    var isStravaSyncing: Bool { stravaTask != nil }

    /// Activities whose file has no GPS positions (indoor, or synced into Apple Health without a route).
    var activitiesWithoutGPS: Int {
        activities.count { $0.trackData.isEmpty }
    }

    /// Activities drawn on the map (real GPS, not indoor or virtual).
    var mapActivities: [Activity] { activities.filter(\.isOnMap) }

    var totalDistanceKm: Double {
        activities.reduce(0) { $0 + $1.distance } / 1000
    }

    func tiles(_ zoom: TileZoom) -> Set<Int64> {
        zoom == .explorer ? tiles14 : tiles17
    }

    func tileStats(_ zoom: TileZoom) -> SquareStats {
        zoom == .explorer ? tileStats14 : tileStats17
    }

    var stravaDetailedCount: Int {
        stravaActivities.count { $0.isSummary != true }
    }

    var stravaExportedCount: Int {
        stravaActivities.count { $0.exportedFile != nil }
    }

    init() {
        folderActivities = TrackCache.load(folder: Self.folderCacheKey)

        if let stravaConfig {
            strava = StravaClient(config: stravaConfig)
            if let tokens = StravaTokens.load() {
                stravaAthlete = tokens.athleteName
                stravaAthleteID = tokens.athleteID
                stravaActivities = TrackCache.load(.strava, folder: String(tokens.athleteID))
            }
        }
        recompute()
        chooseInitialCountries()
        loadRegions()
    }

    /// Re-scans the folder and continues the Strava sync.
    func refreshAll() async {
        if regionsError != nil, !isLoadingRegions { loadRegions() } // retry downloads
        await updateICloud() // so Strava saves to iCloud from the start
        syncStrava()
        await refresh()
    }

    // MARK: Library

    /// The cache of parsed library files (older caches, keyed by folder, are read again once).
    private static let folderCacheKey = "library"

    /// Copies .fit files (or the .fit files in folders) into the library once, and imports them.
    /// The originals aren't watched afterwards.
    func importFiles(_ urls: [URL]) async {
        let result = await Task.detached(priority: .userInitiated) { Library.importOnce(urls) }.value
        await refresh()
        failedFiles += result.failed
        libraryMessage = result.added.isEmpty ? nil : String(localized: "Imported \(result.added.count) .fit files.")
    }

    /// Brings in what other devices added (iCloud), reads new and changed files, removes
    /// duplicate files and sends this device's files to iCloud.
    func refresh() async {
        guard !isImporting else { return }
        isImporting = true
        progress = (0, 0)
        defer { isImporting = false }
        await updateICloud()
        if !Library.isMigrated { await migrate() }
        let sync = syncSetting && isICloudAvailable
        if sync {
            await Task.detached(priority: .userInitiated) {
                Library.pull { done, total in Task { @MainActor [weak self] in self?.progress = (done, total) } }
            }.value
        }

        var failed = [String]()
        var library = await parse(Library.activitiesFolder, prefix: Self.libraryPrefix, failed: &failed)
        let samples = hasSampleRides ? await parse(FolderAccess.sampleRidesFolder, prefix: Self.samplePrefix, failed: &failed) : []
        library = await removeDuplicateFiles(library)
        folderActivities = (library + samples).sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
        failedFiles = failed
        recompute()
        TrackCache.save(folderActivities, folder: Self.folderCacheKey)
        if sync { await Task.detached(priority: .utility) { Library.push() }.value }
        if regions != nil { backfillDerived() }
        await updateTrappists()
        await updateClimbs()
    }

    /// Checks for a new list of Trappist breweries (at most once a day; the copy on the device
    /// otherwise) and their logos, and matches the activities again when the list changed.
    func updateTrappists() async {
        func logos() -> Int {
            trappists.filter { FileManager.default.fileExists(atPath: TrappistData.iconFile($0.id).path(percentEncoded: false)) }.count
        }
        let before = logos()
        guard let list = try? await TrappistData.load() else { return }
        if list != trappists {
            trappists = list
            matchTrappists()
        } else if logos() != before {
            version += 1 // redraw with the new logos
        }
    }

    /// Which breweries the tracks pass: every track point is looked at, so in the background.
    private func matchTrappists() {
        trappistTask?.cancel()
        let all = activities, list = trappists
        trappistTask = Task {
            let visits = await Task.detached(priority: .utility) { TrappistMatcher.visits(all, among: list) }.value
            guard !Task.isCancelled, visits != trappistVisits else { return }
            trappistVisits = visits
            version += 1
        }
    }

    /// Reads the .fit files of a folder; unchanged files come from the cache.
    private func parse(_ folder: URL, prefix: String, failed: inout [String]) async -> [Activity] {
        let previous = folderActivities.filter { $0.id.hasPrefix(prefix) }
        let existing = Dictionary(previous.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var result: [Activity]?
        for await event in Importer.run(folder: folder, existing: existing, activityID: { prefix + $0 }) {
            switch event {
            case .started(_, let toParse): progress = (0, toParse)
            case .folderUnreadable(let message): failed.append(message)
            case .progress(let done, let total): progress = (done, total)
            case .finished(let activities, let failedPaths):
                result = activities
                failed += failedPaths
            }
        }
        return result ?? previous
    }

    /// Keeps one file per workout: the same ride recorded by a watch and saved from Strava, or
    /// imported twice. The best copy stays (see `ActivityMerge.preferredFile`); the others are
    /// deleted here and in iCloud.
    private func removeDuplicateFiles(_ library: [Activity]) async -> [Activity] {
        var keep = [Activity](), drop = [String]()
        for group in ActivityMerge.groups(library) {
            let best = ActivityMerge.preferredFile(group)
            keep.append(best)
            drop += group.filter { $0.id != best.id }.map { String($0.id.dropFirst(Self.libraryPrefix.count)) }
        }
        if !drop.isEmpty {
            await Task.detached(priority: .utility) { Library.delete(names: drop) }.value
        }
        return keep
    }

    /// Once per device: copies the files earlier versions read or saved into the library (no
    /// downloads from Strava again), then forgets the watched folders and the save folder.
    private func migrate() async {
        let folders = FolderAccess.importFolders().filter { !$0.isBuiltIn }.compactMap(FolderAccess.resolve)
        let saveFolder = FolderAccess.resolve(.export)
        let result = await Task.detached(priority: .userInitiated) {
            Library.migrate(importFolders: folders, saveFolder: saveFolder) { done, total in
                Task { @MainActor [weak self] in self?.progress = (done, total) }
            }
        }.value
        FolderAccess.clearImportFolders()
        FolderAccess.clearSaveFolder()
        UserDefaults.standard.set(true, forKey: Library.migratedKey)
        failedFiles += result.failed
        if result.files > 0 {
            libraryMessage = String(localized: "Tileroam now keeps its own copy of your \(result.files) .fit files. The folders they came from aren't watched any more; import new files in Settings.")
        }
    }

    /// Deletes an activity, with all its copies, from this device and iCloud. It isn't deleted
    /// from Strava or from where it was imported from; a deleted Strava activity isn't downloaded
    /// again.
    func delete(_ activity: Activity) async {
        let ids = Set(copies[activity.id] ?? [activity.id])
        var names = [String](), stravaIDs = [Int](), samples = [String]()
        for id in ids {
            if id.hasPrefix(Self.libraryPrefix) {
                names.append(String(id.dropFirst(Self.libraryPrefix.count)))
            } else if id.hasPrefix(Self.samplePrefix) {
                samples.append(String(id.dropFirst(Self.samplePrefix.count)))
            } else if let stravaID = StravaImport.stravaID(fromID: id) {
                stravaIDs.append(stravaID)
                if let file = stravaActivities.first(where: { $0.id == id })?.exportedFile { names.append(file) }
            }
        }
        Deletions.add(stravaIDs: stravaIDs)
        folderActivities.removeAll { ids.contains($0.id) }
        stravaActivities.removeAll { ids.contains($0.id) }
        if let athleteID = stravaAthleteID { saveStrava(athleteID) }
        TrackCache.save(folderActivities, folder: Self.folderCacheKey)
        recompute()
        let sampleFolder = FolderAccess.sampleRidesFolder
        await Task.detached(priority: .userInitiated) {
            Library.delete(names: names)
            for path in samples { try? FileManager.default.removeItem(at: sampleFolder.appending(path: path)) }
        }.value
    }

    func clearCache() async {
        TrackCache.clear()
        folderActivities = []
        recompute()
        await refresh()
    }

    // MARK: Sample rides

    private(set) var hasSampleRides = FolderAccess.hasSampleRides

    func addSampleRides() async {
        await Task.detached(priority: .userInitiated) {
            let folder = FolderAccess.sampleRidesFolder
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for url in FolderAccess.bundledSampleRides {
                try? FileManager.default.copyItem(at: url, to: folder.appending(path: url.lastPathComponent))
            }
        }.value
        hasSampleRides = true
        await refresh()
    }

    func removeSampleRides() async {
        try? FileManager.default.removeItem(at: FolderAccess.sampleRidesFolder)
        hasSampleRides = false
        folderActivities.removeAll { $0.id.hasPrefix(Self.samplePrefix) }
        recompute()
        await refresh()
    }

    // MARK: iCloud

    /// Looks up the iCloud folder, and whether it already has activities.
    private func updateICloud() async {
        let (folder, hasActivities) = await Task.detached(priority: .userInitiated) {
            let folder = FolderAccess.updateICloudFolder()
            return (folder, folder != nil && Library.cloudHasActivities)
        }.value
        isICloudAvailable = folder != nil
        iCloudHasActivities = hasActivities
    }

    // MARK: Strava

    /// Starts a login; returns the state value to send along.
    func beginStravaLogin() async -> String? {
        await strava?.beginLogin()
    }

    func completeStravaLogin(callback: URL) async {
        guard let strava else { return }
        do {
            let tokens = try await strava.completeLogin(callback: callback)
            // Only events after this login matter (an old "revoked" must not undo it).
            UserDefaults.standard.set(Int(Date.now.timeIntervalSince1970), forKey: Self.eventsSinceKey(tokens.athleteID))
            stravaAthlete = tokens.athleteName
            stravaAthleteID = tokens.athleteID
            stravaError = nil
            stravaActivities = TrackCache.load(.strava, folder: String(tokens.athleteID))
            recompute()
            syncStrava()
        } catch {
            stravaError = error.localizedDescription
        }
    }

    func reportStravaError(_ message: String) {
        stravaError = message
    }

    /// Disconnects Strava and forgets its data; with `deleteFiles`, also deletes the .fit files
    /// Tileroam saved from Strava (see `deleteStravaFiles()`).
    func disconnectStrava(deleteFiles: Bool) async {
        await strava?.disconnect()
        forgetStrava()
        if deleteFiles { await deleteStravaFiles() }
    }

    /// Number of .fit files Tileroam saved from Strava in the library.
    func countStravaFiles() async -> Int {
        await Task.detached(priority: .userInitiated) { StravaExport.ownFiles().count }.value
    }

    /// Deletes the .fit files Tileroam saved from Strava, here and in iCloud, and re-reads.
    func deleteStravaFiles() async {
        let deleted = await Task.detached(priority: .userInitiated) {
            let names = StravaExport.ownFiles()
            Library.delete(names: names)
            return names.count
        }.value
        stravaFilesDeleted = deleted
        await refresh()
    }

    /// Set after `deleteStravaFiles()`, for the confirmation in Settings.
    private(set) var stravaFilesDeleted: Int?

    // MARK: Strava webhook events

    private static func eventsSinceKey(_ athleteID: Int) -> String { "stravaEventsSince-\(athleteID)" }

    /// Handles the webhook events the token service queued since the last time: access revoked
    /// (forget everything and delete the saved files), activities deleted on Strava (delete their
    /// copies). Returns false when the connection is gone.
    private func applyStravaEvents(_ strava: StravaClient, athleteID: Int) async -> Bool {
        let sinceKey = Self.eventsSinceKey(athleteID)
        guard let events = try? await strava.events(since: UserDefaults.standard.integer(forKey: sinceKey)),
              let last = events.map(\.time).max() else { return true }
        UserDefaults.standard.set(last, forKey: sinceKey)
        let change = StravaEventChanges(events)
        if change.revoked {
            forgetStrava()
            await deleteStravaFiles()
            stravaError = String(localized: "Strava access was revoked. Tileroam removed the activities it saved from Strava.")
            return false
        }
        guard !change.removedActivities.isEmpty else { return true }
        let removed = change.removedActivities
        stravaActivities.removeAll { StravaImport.stravaID(of: $0).map(removed.contains) ?? false }
        saveStrava(athleteID)
        await Task.detached(priority: .utility) {
            Library.delete(names: StravaExport.ownFiles(of: removed))
        }.value
        recompute()
        await refresh()
        return true
    }

    /// Removes the Strava connection and its cached activities from this device.
    private func forgetStrava() {
        stravaTask?.cancel()
        stravaTask = nil
        StravaTokens.delete()
        TrackCache.clear(.strava)
        stravaActivities = []
        stravaAthlete = nil
        stravaAthleteID = nil
        stravaStatus = nil
        stravaError = nil
        recompute()
    }

    /// Starts (or continues) the Strava sync unless it is already running.
    func syncStrava() {
        guard stravaTask == nil, isStravaConnected, strava != nil else { return }
        stravaTask = Task {
            await runStravaSync()
            stravaTask = nil
        }
    }

    private func runStravaSync() async {
        guard let strava, let athleteID = stravaAthleteID else { return }
        stravaError = nil
        guard await applyStravaEvents(strava, athleteID: athleteID) else { return }

        while !Task.isCancelled {
            do {
                try await fetchStravaList(strava)
                try await fetchStravaDetails(strava)
                stravaStatus = nil
                await refresh() // read the saved files and send them to iCloud
                return
            } catch StravaError.rateLimited(let until) {
                saveStrava(athleteID)
                isStravaPaused = true
                defer { isStravaPaused = false }
                stravaStatus = String(localized: "Strava limit reached – continuing at \(until.formatted(date: .omitted, time: .shortened))")
                try? await Task.sleep(for: .seconds(max(1, until.timeIntervalSinceNow)))
            } catch StravaError.unauthorized {
                // Access was revoked (in Strava's settings): forget the connection and its data.
                forgetStrava()
                stravaError = StravaError.unauthorized.localizedDescription
                return
            } catch {
                saveStrava(athleteID)
                stravaStatus = nil
                if !Task.isCancelled { stravaError = error.localizedDescription }
                return
            }
        }
    }

    /// New activities since the latest known one (everything on the first sync), with summary routes.
    private func fetchStravaList(_ strava: StravaClient) async throws {
        // Caches from before virtual detection, or before moving time and power were kept
        // (detailsVersion): fetch the whole list once to fill them in.
        let needsVirtualFlags = stravaActivities.contains { $0.isVirtual == nil }
        let needsDetails = stravaActivities.contains { $0.detailsVersion != Activity.currentDetails }
        let after = needsVirtualFlags || needsDetails ? nil : stravaActivities.compactMap(\.startDate).max()?.addingTimeInterval(-24 * 3600)
        var known = Set(stravaActivities.map(\.id))
        var page = 1
        while !Task.isCancelled {
            stravaStatus = known.isEmpty ? String(localized: "Fetching Strava activities…") : String(localized: "Checking Strava for new activities…")
            let summaries = try await strava.activities(page: page, after: after)
            if needsVirtualFlags {
                let virtual = Dictionary(summaries.map { (StravaImport.id(for: $0.id), StravaImport.isVirtual($0)) },
                                         uniquingKeysWith: { a, _ in a })
                for i in stravaActivities.indices {
                    guard let flag = virtual[stravaActivities[i].id] else { continue }
                    stravaActivities[i].isVirtual = flag
                    if flag { stravaActivities[i].isSummary = false } // no GPS to download for virtual rides
                }
            }
            if needsDetails {
                let details = Dictionary(summaries.map { (StravaImport.id(for: $0.id), $0) }, uniquingKeysWith: { a, _ in a })
                var changed = false
                for i in stravaActivities.indices where stravaActivities[i].detailsVersion != Activity.currentDetails {
                    guard let s = details[stravaActivities[i].id] else { continue }
                    StravaImport.applyDetails(s, to: &stravaActivities[i])
                    changed = true
                }
                if changed {
                    recompute()
                    if let id = stravaAthleteID { saveStrava(id) }
                }
            }
            let deleted = Deletions.stravaIDs()
            let new = await Task.detached(priority: .userInitiated) {
                summaries.filter { !deleted.contains($0.id) }.map(StravaImport.activity(from:))
            }.value.filter { !known.contains($0.id) }
            if !new.isEmpty {
                stravaActivities += new
                known.formUnion(new.map(\.id))
                recompute()
                if let id = stravaAthleteID { saveStrava(id) }
            }
            if summaries.count < 200 {
                if needsDetails {
                    // The whole list was read: activities Strava didn't list (deleted there) have no
                    // details to add; mark them, or every sync would read the whole list again.
                    for i in stravaActivities.indices where stravaActivities[i].detailsVersion != Activity.currentDetails {
                        stravaActivities[i].detailsVersion = Activity.currentDetails
                    }
                    if let id = stravaAthleteID { saveStrava(id) }
                }
                break
            }
            page += 1
        }
    }

    /// Downloads full GPS for summary-only activities (most recent first) and saves every
    /// Strava activity as a .fit file in the folder's "Strava" subfolder. Activities that the
    /// folder already has (same start time) are skipped to save API calls and avoid duplicates.
    private func fetchStravaDetails(_ strava: StravaClient) async throws {
        let inFolderWithGPS = ActivityMerge.Index(folderActivities.filter { !$0.trackData.isEmpty })
        let inFolder = ActivityMerge.Index(folderActivities)

        defer {
            recompute()
            if let id = stravaAthleteID { saveStrava(id) }
        }

        // Activities without GPS: export needs no API calls.
        let noGPS = stravaActivities.indices.filter {
            let a = stravaActivities[$0]
            return a.trackData.isEmpty && a.exportedFile == nil && !inFolder.contains(a)
        }
        for (n, index) in noGPS.enumerated() {
            if Task.isCancelled { return }
            stravaStatus = String(localized: "Saving Strava activities to folder: \(n) of \(noGPS.count)")
            await export(index, stream: nil)
        }

        let queue = stravaActivities
            .filter { a in
                !a.trackData.isEmpty && !inFolderWithGPS.contains(a)
                    && (a.isSummary == true || a.exportedFile == nil)
            }
            .sorted { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }

        for (done, activity) in queue.enumerated() {
            if Task.isCancelled { return }
            stravaStatus = String(localized: "Strava detailed GPS: \(done) of \(queue.count)")
            guard let stravaID = StravaImport.stravaID(of: activity) else { continue }
            let stream = try await strava.stream(activityID: stravaID)
            let updated = await Task.detached(priority: .utility) {
                activity.isSummary == true ? StravaImport.detailed(activity, points: stream?.points) : activity
            }.value
            guard let index = stravaActivities.firstIndex(where: { $0.id == activity.id }) else { continue }
            stravaActivities[index] = updated
            await export(index, stream: stream)
            if (done + 1) % 25 == 0 {
                recompute()
                if let id = stravaAthleteID { saveStrava(id) }
            }
        }
    }

    private func export(_ index: Int, stream: StravaStream?) async {
        let activity = stravaActivities[index]
        do {
            let name = try await Task.detached(priority: .utility) {
                try StravaExport.write(activity, stream: stream)
            }.value
            if let i = stravaActivities.firstIndex(where: { $0.id == activity.id }) {
                stravaActivities[i].exportedFile = name
            }
        } catch {
            stravaError = String(localized: "Could not save the activity: \(error.localizedDescription)")
        }
    }

    private func saveStrava(_ athleteID: Int) {
        TrackCache.save(stravaActivities, .strava, folder: String(athleteID))
    }

    /// Computes tiles and visited municipalities/postcodes for activities that don't have them
    /// for the current countries, from their stored tracks (simplified to ~8 m; no re-parsing
    /// or re-downloading needed).
    private var isBackfilling = false

    private func backfillDerived() {
        guard let regions, !isBackfilling else { return }
        let key = regions.key
        let missing = (folderActivities + stravaActivities)
            .filter { $0.regionsKey != key || $0.tiles14 == nil || $0.tiles17 == nil }
        guard !missing.isEmpty else { return }
        isBackfilling = true
        Task {
            defer {
                isBackfilling = false
                backfillDerived() // activities added or countries changed meanwhile
            }
            let computed = await Task.detached(priority: .utility) {
                var result = [String: (tiles14: [Int64], tiles17: [Int64], municipalities: [String], postalCodes: [String])]()
                for a in missing {
                    let points = a.coordinates.map { GeoPoint(lat: $0.latitude, lon: $0.longitude) }
                    let dense = Geo.densified(points, spacing: 100)
                    let fresh = a.regionsKey != key
                    result[a.id] = (
                        a.tiles14 ?? Array(TileGrid.tiles(for: points, zoom: .explorer)).sorted(),
                        a.tiles17 ?? Array(TileGrid.tiles(for: points, zoom: .squadratinho)).sorted(),
                        fresh ? Array(regions.municipalities.visited(by: dense)).sorted() : a.municipalities ?? [],
                        fresh ? Array(regions.postcodes.visited(by: dense)).sorted() : a.postalCodes ?? []
                    )
                }
                return result
            }.value
            guard self.regions?.key == key else { return } // countries changed meanwhile; a new pass follows
            defer { pruneUnvisitedCountries() }
            func fill(_ a: inout Activity) {
                guard let c = computed[a.id] else { return }
                a.tiles14 = c.tiles14
                a.tiles17 = c.tiles17
                a.municipalities = c.municipalities
                a.postalCodes = c.postalCodes
                a.regionsKey = key
            }
            for i in folderActivities.indices { fill(&folderActivities[i]) }
            for i in stravaActivities.indices { fill(&stravaActivities[i]) }
            recompute()
            TrackCache.save(folderActivities, folder: Self.folderCacheKey)
            if let id = stravaAthleteID { saveStrava(id) }
        }
    }

    // MARK: Climbs

    /// Downloads the climbs around the activities (areas not on the device yet; small files) and
    /// finds which each activity climbed. Activities matched with these climbs before are skipped.
    func updateClimbs() async {
        guard let index = ClimbData.index, !isMatchingClimbs else { return }
        isMatchingClimbs = true
        defer { isMatchingClimbs = false }
        let key = ClimbData.key(index)
        let all = folderActivities + stravaActivities
        var areas = Set<ClimbIndex.Area>()
        for a in all where a.isOnMap {
            let points = a.coordinates.map { GeoPoint(lat: $0.latitude, lon: $0.longitude) }
            areas.formUnion(ClimbData.areas(around: points, in: index))
        }
        guard let loaded = try? await ClimbData.load(Array(areas), index: index) else { return }
        for climb in loaded { climbs[climb.id] = climb }

        let pending = all.filter { $0.climbsKey != key && $0.isOnMap }
        guard !pending.isEmpty else { return }
        let candidates = Array(climbs.values)
        let found = await Task.detached(priority: .utility) { ClimbMatcher.match(pending, climbs: candidates) }.value
        func fill(_ a: inout Activity) {
            guard let ids = found[a.id] else { return }
            a.climbs = ids
            a.climbsKey = key
        }
        for i in folderActivities.indices { fill(&folderActivities[i]) }
        for i in stravaActivities.indices { fill(&stravaActivities[i]) }
        recompute()
        TrackCache.save(folderActivities, folder: Self.folderCacheKey)
        if let id = stravaAthleteID { saveStrava(id) }
    }

    /// The climbs around a route or plan (downloading their areas where needed; none when offline).
    func climbs(around points: [GeoPoint]) async -> [Climb] {
        guard let index = ClimbData.index,
              let loaded = try? await ClimbData.load(ClimbData.areas(around: points, in: index), index: index) else { return [] }
        for climb in loaded { climbs[climb.id] = climb }
        return loaded
    }

    /// Makes sure the climbs of a map area are on the device (the Climbs tab, planning). Large
    /// areas are left out: the map shows climbs from about 2° wide.
    func loadClimbs(minLat: Double, maxLat: Double, minLon: Double, maxLon: Double) async {
        guard let index = ClimbData.index, maxLat - minLat < 3, maxLon - minLon < 4 else { return }
        let areas = ClimbData.areas(minLat: minLat, maxLat: maxLat, minLon: minLon, maxLon: maxLon, margin: 0, in: index)
        guard areas.contains(where: { !ClimbData.isDownloaded($0, index: index) }) || climbs.isEmpty,
              let loaded = try? await ClimbData.load(areas, index: index) else { return }
        var changed = false
        for climb in loaded where climbs[climb.id] == nil {
            climbs[climb.id] = climb
            changed = true
        }
        if changed { version += 1 }
    }

    // MARK: Derived data

    private func recompute() {
        let groups = ActivityMerge.groups(folderActivities + stravaActivities)
        activities = groups.map(ActivityMerge.best(of:))
        copies = Dictionary(zip(activities.map(\.id), groups.map { $0.map(\.id) }), uniquingKeysWith: { a, _ in a })
        var tiles14 = Set<Int64>()
        var tiles17 = Set<Int64>()
        var municipalities = Set<String>()
        var postcodes = Set<String>()
        for a in activities where a.isOnMap {
            tiles14.formUnion(a.tiles14 ?? [])
            tiles17.formUnion(a.tiles17 ?? [])
            municipalities.formUnion(a.municipalities ?? [])
            postcodes.formUnion(a.postalCodes ?? [])
        }
        var climbed = [String: [Date]]()
        for a in activities {
            for id in a.climbs ?? [] { climbed[id, default: []].append(a.startDate ?? .distantPast) }
        }
        self.climbed = climbed.mapValues { $0.sorted(by: >) }
        self.tiles14 = tiles14
        self.tiles17 = tiles17
        self.visitedMunicipalities = municipalities
        self.visitedPostcodes = postcodes
        // Max square and cluster can take a moment for many zoom 17 tiles: compute in the background.
        statsTask?.cancel()
        let visited14 = tiles14, visited17 = tiles17
        statsTask = Task {
            let stats = await Task.detached(priority: .userInitiated) {
                (SquareStats(visited: visited14), SquareStats(visited: visited17))
            }.value
            guard !Task.isCancelled else { return }
            tileStats14 = stats.0
            tileStats17 = stats.1
            statsReady = true
            version += 1
            await WidgetData.saveTiles(visited14, visited17)
        }
        matchTrappists()
        badgeTask?.cancel()
        let forBadges = activities, countries = enabledCountries.count
        badgeTask = Task {
            let counts = await Task.detached(priority: .utility) { BadgeRules.counts(forBadges, countries: countries) }.value
            guard !Task.isCancelled else { return }
            badges = counts
        }
        eddingtonCycling = Eddington(activities: activities, sports: Eddington.cyclingSports)
        eddingtonRunning = Eddington(activities: activities, sports: Eddington.runningSports)
        eddingtonWalking = Eddington(activities: activities, sports: Eddington.walkingSports)
        WidgetData.save(cycling: eddingtonCycling, running: eddingtonRunning)
        version += 1
        if regions != nil { detectCountries() }
        backfillDerived()
    }
}
