import Foundation
import Observation

@MainActor
@Observable
final class ActivityStore {
    /// All activities from all sources, with duplicates merged.
    private(set) var activities: [Activity] = []
    private(set) var tiles14: Set<Int64> = []
    private(set) var tileStats14 = SquareStats()
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
    /// What the last import or deletion did, for Settings.
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

    /// What the refresh is doing, for the banner while there's no file count to show.
    private(set) var importPhase: String?

    // The parts (see each type): challenges with a list, municipality and postcode boundaries,
    // and the Strava connection. The properties below pass them on for the views.
    let challenges = ChallengeEngine()
    let regionStore = RegionStore()
    let strava = StravaSync()

    var trappists: [Trappist] { challenges.trappists }
    var trappistVisits: [String: [Date]] { challenges.trappistVisits }
    var boscafes: [Boscafe] { challenges.boscafes }
    var boscafeVisits: [String: [Date]] { challenges.boscafeVisits }
    var ferries: [Ferry] { challenges.ferries }
    var ferryCrossings: [String: [Date]] { challenges.ferryCrossings }
    var klompenpaden: [Klompenpad] { challenges.klompenpaden }
    var klompenpadProgress: [String: Double] { challenges.klompenpadProgress }
    var klompenpadenWalked: Int { challenges.klompenpadenWalked }
    var mtbRoutes: [MTBRoute] { challenges.mtbRoutes }
    var mtbProgress: [String: Double] { challenges.mtbProgress }
    var mtbRoutesRidden: Int { challenges.mtbRoutesRidden }
    var badges: [Badge: Int] { challenges.badges }
    var worldCountries: Set<String> { challenges.worldCountries }

    var regions: RegionData? { regionStore.regions }
    var isLoadingRegions: Bool { regionStore.isLoading }
    var regionsError: String? { regionStore.error }
    var regionsErrorDetail: String? { regionStore.errorDetail }
    var municipalityAreas: AreaSet? { regions?.municipalities }
    var postcodeAreas: AreaSet? { regions?.postcodes }
    /// Waits for the region boundaries (those that could be downloaded).
    func loadedRegions() async -> RegionData { await regionStore.loaded() }
    /// Tries the failed downloads again (the "Try Again" button).
    func retryRegions() { regionStore.retry() }

    /// Visited/total per country for a kind of area.
    func regionCounts(_ kind: AreaKind) -> [String: (visited: Int, total: Int)] {
        guard let areas = regions?.areas(kind) else { return [:] }
        let visited = kind == .municipalities ? visitedMunicipalities : visitedPostcodes
        let visitedByCountry = Dictionary(grouping: visited, by: { String($0.prefix { $0 != ":" }) }).mapValues(\.count)
        return areas.countByCountry().reduce(into: [:]) { $0[$1.key] = (visitedByCountry[$1.key] ?? 0, $1.value) }
    }

    var stravaConfig: StravaConfig? { strava.config }
    var stravaActivities: [Activity] { strava.activities }
    var stravaAthlete: String? { strava.athlete }
    var stravaStatus: String? { strava.status }
    var stravaError: String? { strava.error }
    var isStravaPaused: Bool { strava.isPaused }
    var isStravaConnected: Bool { strava.isConnected }
    var isStravaSyncing: Bool { strava.isSyncing }
    var stravaDetailedCount: Int { strava.detailedCount }
    var stravaExportedCount: Int { strava.exportedCount }
    var stravaFilesDeleted: Int? { strava.filesDeleted }
    func beginStravaLogin() async -> String? { await strava.beginLogin() }
    func completeStravaLogin(callback: URL) async { await strava.completeLogin(callback: callback) }
    func reportStravaError(_ message: String) { strava.reportError(message) }
    func disconnectStrava(deleteFiles: Bool) async { await strava.disconnect(deleteFiles: deleteFiles) }
    func countStravaFiles() async -> Int { await strava.countFiles() }
    func deleteStravaFiles() async { await strava.deleteFiles() }
    /// Starts (or continues) the Strava sync unless it is already running.
    func syncStrava() { strava.sync() }

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
        tiles14
    }

    func tileStats(_ zoom: TileZoom) -> SquareStats {
        tileStats14
    }

    init() {
        folderActivities = TrackCache.load(folder: Self.folderCacheKey)
        strava.host = self
        challenges.onPrepared = { [weak self] in self?.matchChallenges() }
        regionStore.onLoaded = { [weak self] in
            self?.version += 1
            self?.backfillDerived()
        }
        recompute()
        regionStore.chooseInitialCountries(folderActivities + stravaActivities)
        regionStore.load()
    }

    /// Re-scans the folder and continues the Strava sync.
    func refreshAll() async {
        if regionsError != nil { regionStore.retry() } // retry downloads
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
        importPhase = nil
        defer {
            isImporting = false
            importPhase = nil
        }
        await updateICloud()
        let sync = syncSetting && isICloudAvailable
        if sync {
            importPhase = String(localized: "Checking iCloud…")
            let pull = Task.detached(priority: .userInitiated) {
                Library.pull { done, total in Task { @MainActor [weak self] in self?.progress = (done, total) } }
            }
            // A new device can fetch hundreds of activities: show what has arrived every 10
            // seconds, instead of only at the end.
            let interim = Task { @MainActor [weak self] in
                var shown = Library.names(in: Library.activitiesFolder, ext: "fit").count
                while !Task.isCancelled {
                    try? await Task.sleep(for: Self.interimRefresh)
                    guard let self, !Task.isCancelled else { return }
                    let arrived = Library.names(in: Library.activitiesFolder, ext: "fit").count
                    guard arrived > shown else { continue }
                    shown = arrived
                    await self.showArrivedActivities()
                }
            }
            _ = await pull.value
            interim.cancel()
            await interim.value // a refresh under way finishes first
        }

        importPhase = String(localized: "Reading your activities…")
        var failed = [String]()
        var library = await parse(Library.activitiesFolder, prefix: Self.libraryPrefix, failed: &failed)
        let samples = hasSampleRides ? await parse(FolderAccess.sampleRidesFolder, prefix: Self.samplePrefix, failed: &failed) : []
        library = await removeDuplicateFiles(library)
        folderActivities = (library + samples).sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
        failedFiles = failed
        recompute()
        scheduleCacheSave()
        if sync {
            importPhase = String(localized: "Saving to iCloud…")
            await Task.detached(priority: .utility) { Library.push() }.value
        }
        if regions != nil { backfillDerived() }
        // The import is done: the rest (lists from the server or an asset pack, climbs to match,
        // which takes minutes the first time) runs on without the "Checking" banner, each on its own.
        isImporting = false
        importPhase = nil
        matchChallenges() // the activities that arrived, now the refresh is done
        updateChallengeLists()
        Task { await updateClimbs() }
    }

    /// How often activities arriving from iCloud are shown while they download.
    static let interimRefresh = Duration.seconds(10)

    /// While iCloud downloads: reads the activity files that have arrived (unchanged ones come from
    /// the cache) and updates the map and statistics. Duplicates, failures and the cache are left
    /// to the full refresh after the download.
    private func showArrivedActivities() async {
        var failed = [String]()
        let library = await parse(Library.activitiesFolder, prefix: Self.libraryPrefix, failed: &failed, reportProgress: false)
        let samples = folderActivities.filter { $0.id.hasPrefix(Self.samplePrefix) }
        folderActivities = (library + samples).sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
        recompute()
    }

    /// Checks the lists for updates, each on its own; a changed list means checking again.
    private func updateChallengeLists() {
        func handle(_ change: ChallengeEngine.Change) {
            switch change {
            case .list: matchChallenges() // a new list has a new key: every activity is checked again
            case .logos: version += 1 // redraw with the new logos
            case .none: break
            }
        }
        Task { handle(await challenges.updateTrappists()) }
        Task { handle(await challenges.updateBoscafes()) }
        Task { handle(await challenges.updateFerries()) }
        Task { handle(await challenges.updateKlompenpaden()) }
        Task { handle(await challenges.updateMTBRoutes()) }
    }

    // MARK: Challenge results (see ChallengeEngine, ChallengeResults)

    /// Adds up the stored challenge results, then checks the activities whose results are missing
    /// or out of date (new ones, or all of them after a new list or new rules) and stores the
    /// results with them. One pass at a time: activities that arrive meanwhile are picked up by the
    /// next. While a refresh runs (activities downloading from iCloud, shown every 10 seconds) only
    /// the stored results are added up: tiles and areas come first, and the checks, which take
    /// minutes for hundreds of new activities, run in the background once the refresh is done.
    private func matchChallenges() {
        guard let current = challenges.current else { return } // routes being prepared: called again
        if challenges.aggregate(activities, current) { version += 1 }
        guard !isImporting, !challenges.isChecking else { return }
        let all = folderActivities + stravaActivities
        Task {
            guard let results = await challenges.check(all, current) else { return }
            func fill(_ a: inout Activity) {
                guard let r = results[a.id] else { return } // deleted meanwhile: nothing to store
                ChallengeEngine.store(r, current, in: &a)
            }
            for i in folderActivities.indices { fill(&folderActivities[i]) }
            strava.update(fill)
            scheduleCacheSave()
            recompute() // merged activities with their results; checks what arrived meanwhile
        }
    }

    /// Reads the .fit files of a folder; unchanged files come from the cache.
    /// `reportProgress` false keeps the progress line on the iCloud download (interim refreshes).
    private func parse(_ folder: URL, prefix: String, failed: inout [String], reportProgress: Bool = true) async -> [Activity] {
        let previous = folderActivities.filter { $0.id.hasPrefix(prefix) }
        let existing = Dictionary(previous.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var result: [Activity]?
        for await event in Importer.run(folder: folder, existing: existing, activityID: { prefix + $0 }) {
            switch event {
            case .started(_, let toParse): if reportProgress { progress = (0, toParse) }
            case .folderUnreadable(let message): failed.append(message)
            case .progress(let done, let total): if reportProgress { progress = (done, total) }
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
        strava.remove(ids: ids)
        scheduleCacheSave()
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

    // MARK: Caches

    /// The parsed activities are kept on the device (`TrackCache`): the library's and Strava's.
    /// Changes are written together, a moment after the last one and off the main thread (the
    /// caches hold ~2,000 tracks), instead of in full after every step; `saveCaches()` writes at
    /// once (when the app goes to the background).
    @ObservationIgnored private var cacheSave: Task<Void, Never>?
    @ObservationIgnored private var cacheWrite: Task<Void, Never>?

    private func scheduleCacheSave() {
        cacheSave?.cancel()
        cacheSave = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.saveCaches()
        }
    }

    /// Writes both caches now (in order: a write never overtakes an earlier one).
    func saveCaches() {
        cacheSave?.cancel()
        cacheSave = nil
        let folder = folderActivities, key = Self.folderCacheKey
        let stravaList = strava.activities, athleteID = strava.athleteID
        let previous = cacheWrite
        cacheWrite = Task.detached(priority: .utility) {
            await previous?.value
            TrackCache.save(folder, folder: key)
            if let athleteID { StravaSync.save(stravaList, athleteID: athleteID) }
        }
    }

    private var isBackfilling = false

    /// Computes tiles and visited municipalities/postcodes for activities that don't have them
    /// for the current countries, from their stored tracks (simplified to ~8 m; no re-parsing
    /// or re-downloading needed). Tiles don't need the boundaries: without them (still loading, or
    /// a download that failed) only the tiles are computed, so the map never waits for them.
    private func backfillDerived() {
        guard !isBackfilling else { return }
        guard let regions = regionStore.regions else { return backfillTiles() }
        let key = regions.key
        let missing = (folderActivities + stravaActivities)
            .filter { $0.regionsKey != key || $0.tiles14 == nil }
        guard !missing.isEmpty else { return }
        isBackfilling = true
        Task {
            defer {
                isBackfilling = false
                backfillDerived() // activities added or countries changed meanwhile
            }
            let computed = await Task.detached(priority: .utility) {
                var result = [String: (tiles14: [Int64], municipalities: [String], postalCodes: [String])]()
                for a in missing {
                    let points = a.coordinates.map { GeoPoint(lat: $0.latitude, lon: $0.longitude) }
                    let dense = Geo.densified(points, spacing: 100)
                    let fresh = a.regionsKey != key
                    result[a.id] = (
                        a.tiles14 ?? Array(TileGrid.tiles(for: points, zoom: .explorer)).sorted(),
                        fresh ? Array(regions.municipalities.visited(by: dense)).sorted() : a.municipalities ?? [],
                        fresh ? Array(regions.postcodes.visited(by: dense)).sorted() : a.postalCodes ?? []
                    )
                }
                return result
            }.value
            guard self.regions?.key == key else { return } // countries changed meanwhile; a new pass follows
            defer { regionStore.pruneUnvisitedCountries(visitedMunicipalities: visitedMunicipalities) }
            func fill(_ a: inout Activity) {
                guard let c = computed[a.id] else { return }
                a.tiles14 = c.tiles14
                a.municipalities = c.municipalities
                a.postalCodes = c.postalCodes
                a.regionsKey = key
            }
            for i in folderActivities.indices { fill(&folderActivities[i]) }
            strava.update(fill)
            recompute()
            scheduleCacheSave()
        }
    }

    /// The tiles of activities that have none, while the boundaries aren't loaded.
    private func backfillTiles() {
        let missing = (folderActivities + stravaActivities).filter { $0.tiles14 == nil }
        guard !missing.isEmpty else { return }
        isBackfilling = true
        Task {
            defer {
                isBackfilling = false
                backfillDerived() // the boundaries may have arrived meanwhile
            }
            let computed = await Task.detached(priority: .utility) {
                Dictionary(missing.map { a in
                    (a.id, Array(TileGrid.tiles(for: a.coordinates.map { GeoPoint(lat: $0.latitude, lon: $0.longitude) },
                                                zoom: .explorer)).sorted())
                }, uniquingKeysWith: { a, _ in a })
            }.value
            func fill(_ a: inout Activity) {
                if a.tiles14 == nil, let tiles = computed[a.id] { a.tiles14 = tiles }
            }
            for i in folderActivities.indices { fill(&folderActivities[i]) }
            strava.update(fill)
            recompute()
            scheduleCacheSave()
        }
    }

    // MARK: Climbs

    /// Downloads the climbs around the activities (areas not on the device yet; small files) and
    /// finds which each activity climbed. Activities matched with these climbs before are skipped.
    func updateClimbs() async {
        guard let index = ClimbData.index, !isMatchingClimbs else { return }
        isMatchingClimbs = true
        defer { isMatchingClimbs = false }
        // The climbs and the matching rules: activities are matched again when either changes.
        let key = "\(ClimbData.key(index))-m\(ClimbMatcher.version)"
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
        strava.update(fill)
        recompute()
        scheduleCacheSave()
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
        var municipalities = Set<String>()
        var postcodes = Set<String>()
        for a in activities where a.isOnMap {
            tiles14.formUnion(a.tiles14 ?? [])
            municipalities.formUnion(a.municipalities ?? [])
            postcodes.formUnion(a.postalCodes ?? [])
        }
        var climbed = [String: [Date]]()
        for a in activities {
            for id in a.climbs ?? [] { climbed[id, default: []].append(a.startDate ?? .distantPast) }
        }
        self.climbed = climbed.mapValues { $0.sorted(by: >) }
        self.tiles14 = tiles14
        self.visitedMunicipalities = municipalities
        self.visitedPostcodes = postcodes
        // Max square and cluster can take a moment for many tiles: compute in the background.
        statsTask?.cancel()
        let visited14 = tiles14
        statsTask = Task {
            let stats = await Task.detached(priority: .userInitiated) {
                SquareStats(visited: visited14)
            }.value
            guard !Task.isCancelled else { return }
            tileStats14 = stats
            statsReady = true
            version += 1
            await WidgetData.saveTiles(visited14)
        }
        matchChallenges()
        eddingtonCycling = Eddington(activities: activities, sports: Eddington.cyclingSports)
        eddingtonRunning = Eddington(activities: activities, sports: Eddington.runningSports)
        eddingtonWalking = Eddington(activities: activities, sports: Eddington.walkingSports)
        WidgetData.save(cycling: eddingtonCycling, running: eddingtonRunning)
        version += 1
        if regions != nil { regionStore.detectCountries(folderActivities + stravaActivities) }
        backfillDerived()
    }
}

extension ActivityStore: StravaSyncHost {
    var pushesToICloud: Bool { syncSetting && isICloudAvailable }

    func stravaActivitiesChanged(recount: Bool) {
        if recount { recompute() }
        scheduleCacheSave()
    }
}
