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

    // Folder source
    private(set) var folderActivities: [Activity] = []
    /// The folders with .fit files, with their state for the UI.
    private(set) var importFolders: [ImportFolderStatus] = []
    private(set) var isImporting = false
    private(set) var progress: (done: Int, total: Int) = (0, 0)
    private(set) var failedFiles: [String] = []

    struct ImportFolderStatus: Identifiable, Equatable {
        let id: String
        var name: String
        var location: String?
        /// Set when the folder can't be read or contains no .fit files.
        var problem: String?
    }

    var hasImportFolders: Bool { !importFolders.isEmpty }

    /// First folder problem, for the card on the map.
    var problem: String? { importFolders.compactMap(\.problem).first }

    func activityCount(inFolder id: String) -> Int {
        guard let folder = (FolderAccess.importFolders() + [.internalFolder]).first(where: { $0.id == id }) else { return 0 }
        return folderActivities.count { folder.owns($0.id) }
    }

    // The app's own folder for downloaded activities
    private(set) var exportFolderName: String?
    private(set) var exportFolderLocation: String?
    private(set) var exportMessage: String?

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

    /// Waits for the region boundaries.
    func loadedRegions() async -> RegionData {
        while true {
            if let regions, regions.countries == Country.all.map(\.code).filter(enabledCountries.contains) { return regions }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    func setCountry(_ code: String, enabled: Bool) {
        countriesAutomatic = false
        pruneCountriesAfterCount = false
        if enabled { enabledCountries.insert(code) } else { enabledCountries.remove(code) }
        UserDefaults.standard.set(Array(enabledCountries).sorted(), forKey: Self.countriesKey)
        loadRegions()
    }

    /// Visited/total per country for a kind of area.
    func regionCounts(_ kind: AreaKind) -> [String: (visited: Int, total: Int)] {
        guard let areas = regions?.areas(kind) else { return [:] }
        let visited = kind == .municipalities ? visitedMunicipalities : visitedPostcodes
        let visitedByCountry = Dictionary(grouping: visited, by: { String($0.prefix { $0 != ":" }) }).mapValues(\.count)
        return areas.countByCountry().reduce(into: [:]) { $0[$1.key] = (visitedByCountry[$1.key] ?? 0, $1.value) }
    }

    private func loadRegions() {
        regionsTask?.cancel()
        isLoadingRegions = true
        let countries = enabledCountries
        regionsTask = Task {
            let data = await Task.detached(priority: .userInitiated) { RegionData.load(countries: countries) }.value
            guard !Task.isCancelled else { return }
            regions = data
            isLoadingRegions = false
            version += 1
            backfillDerived()
        }
    }

    private static let countriesAutomaticKey = "countriesAutomatic"

    /// Countries follow the activities until the user switches one on or off.
    private var countriesAutomatic: Bool {
        get { UserDefaults.standard.object(forKey: Self.countriesAutomaticKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.countriesAutomaticKey) }
    }
    private var countryScannedIDs = Set<String>()

    private func chooseInitialCountries() {
        if let saved = UserDefaults.standard.stringArray(forKey: Self.countriesKey) {
            enabledCountries = Set(saved)
        }
        if enabledCountries.isEmpty {
            let region = Locale.current.region?.identifier ?? "NL"
            enabledCountries = [Country.named(region) != nil ? region : "NL"]
        }
        detectCountries(load: false)
    }

    /// Automatic mode: switch on countries whose bounding box contains new activities. Bounding
    /// boxes overlap (Monaco lies within France's, southern Netherlands within Belgium's), so
    /// countries without visits are dropped again after the next count.
    private func detectCountries(load: Bool = true) {
        guard countriesAutomatic else { return }
        var found = Set<String>()
        for a in folderActivities + stravaActivities where !countryScannedIDs.contains(a.id) && a.isVirtual != true {
            countryScannedIDs.insert(a.id)
            let coordinates = a.coordinates
            guard !coordinates.isEmpty else { continue }
            let samples = stride(from: 0, to: coordinates.count, by: max(1, coordinates.count / 8)).map { coordinates[$0] }
            for c in samples + [coordinates[coordinates.count - 1]] {
                let p = GeoPoint(lat: c.latitude, lon: c.longitude)
                for country in Country.all where country.contains(p) { found.insert(country.code) }
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
        guard pruneCountriesAfterCount, let regions, regions.countries.sorted() == enabledCountries.sorted() else { return }
        pruneCountriesAfterCount = false
        let visited = Set(visitedMunicipalities.map { String($0.prefix { $0 != ":" }) })
        let keep = enabledCountries.filter { visited.contains($0) }
        guard !keep.isEmpty else { return } // no visits yet: keep the current choice
        guard keep != enabledCountries else { return }
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
        exportFolderName = FolderAccess.savedFolderName(.export)
        exportFolderLocation = FolderAccess.resolve(.export).map(FolderAccess.displayLocation)
        updateFolderStatuses()
        folderActivities = TrackCache.load(folder: Self.folderCacheKey)
        if folderActivities.isEmpty, let legacy = FolderAccess.savedFolderName() {
            folderActivities = TrackCache.load(folder: legacy) // cache of the single-folder version
        }

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
        syncStrava()
        await refresh()
    }

    // MARK: Folders

    private static let folderCacheKey = "folders"

    private func updateFolderStatuses() {
        let problems = Dictionary(importFolders.map { ($0.id, $0.problem) }, uniquingKeysWith: { a, _ in a })
        importFolders = FolderAccess.importFolders().map { folder in
            ImportFolderStatus(id: folder.id, name: folder.name,
                               location: FolderAccess.resolve(folder).map(FolderAccess.displayLocation),
                               problem: problems[folder.id] ?? nil)
        }
    }

    private func setProblem(_ problem: String?, for id: String) {
        if let i = importFolders.firstIndex(where: { $0.id == id }) { importFolders[i].problem = problem }
    }

    /// Adds one or more folders with .fit files and imports them.
    func addFolders(_ urls: [URL]) async {
        for url in urls {
            do {
                try FolderAccess.addImportFolder(url)
            } catch {
                failedFiles.append(String(localized: "Could not access “\(url.lastPathComponent)”: \(error.localizedDescription)"))
            }
        }
        updateFolderStatuses()
        await refresh()
    }

    func removeFolder(id: String) {
        guard let folder = FolderAccess.importFolders().first(where: { $0.id == id }) else { return }
        FolderAccess.removeImportFolder(id: id)
        folderActivities.removeAll { folder.owns($0.id) }
        TrackCache.save(folderActivities, folder: Self.folderCacheKey)
        updateFolderStatuses()
        recompute()
    }

    /// Copies individual .fit files into the internal Import folder and imports them.
    func importFiles(_ urls: [URL]) async {
        let target = FolderAccess.internalImportFolder
        let failed = await Task.detached(priority: .userInitiated) {
            var failed = [String]()
            for url in urls {
                let didAccess = url.startAccessingSecurityScopedResource()
                defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
                do {
                    let data = try FolderAccess.read(url)
                    try data.write(to: target.appending(path: url.lastPathComponent), options: .atomic)
                } catch {
                    failed.append(String(localized: "Could not read “\(url.lastPathComponent)”: \(error.localizedDescription)"))
                }
            }
            return failed
        }.value
        await refresh()
        failedFiles += failed
    }

    /// Imports new and changed files from all folders.
    func refresh() async {
        // The internal Import folder ("On My iPhone › Tileroam › Import") is always read too.
        let folders = FolderAccess.importFolders() + [.internalFolder]
        guard !isImporting else { return }
        isImporting = true
        progress = (0, 0)
        defer { isImporting = false }
        updateFolderStatuses()

        var all = [Activity]()
        var failed = [String]()
        for folder in folders {
            setProblem(nil, for: folder.id)
            let previous = folderActivities.filter { folder.owns($0.id) }
            guard let url = FolderAccess.resolve(folder) else {
                setProblem(String(localized: "Could not access “\(folder.name)”: \(String(localized: "Choose it again in Settings."))"), for: folder.id)
                all += previous
                continue
            }
            let existing = Dictionary(previous.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            var result: [Activity]?
            for await event in Importer.run(folder: url, existing: existing, activityID: { folder.activityID(for: $0) }) {
                switch event {
                case .started(let found, let toParse):
                    progress = (0, toParse)
                    if found == 0, !folder.isInternal {
                        setProblem(String(localized: "No .fit files found in “\(folder.name)”. Choose the folder that contains your .fit files."), for: folder.id)
                    }
                case .folderUnreadable(let message):
                    setProblem(String(localized: "Could not read “\(folder.name)”: \(message)"), for: folder.id)
                case .progress(let done, let total):
                    progress = (done, total)
                case .finished(let activities, let failedPaths):
                    result = activities
                    failed += failedPaths
                }
            }
            all += result ?? previous // keep what we had if the folder couldn't be read
        }
        folderActivities = all.sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
        failedFiles = failed
        recompute()
        TrackCache.save(folderActivities, folder: Self.folderCacheKey)
        if regions != nil { backfillDerived() }
    }

    func clearCache() async {
        TrackCache.clear()
        folderActivities = []
        recompute()
        await refresh()
    }

    // MARK: Save folder

    func selectExportFolder(_ url: URL) async {
        do {
            try FolderAccess.save(url, as: .export)
        } catch {
            exportMessage = String(localized: "Could not access “\(url.lastPathComponent)”: \(error.localizedDescription)")
            return
        }
        exportFolderName = url.lastPathComponent
        exportFolderLocation = FolderAccess.displayLocation(url)
        exportMessage = nil

        // Move files saved earlier in the app's internal storage (or, in early versions, in the
        // first import folder) to the new save folder.
        let sources = [FolderAccess.internalFolder] + FolderAccess.importFolders().filter { !$0.isInternal }.prefix(1).compactMap(FolderAccess.resolve)
        if let new = FolderAccess.resolve(.export) {
            do {
                let moved = try await Task.detached(priority: .userInitiated) {
                    var moved = 0
                    for old in sources {
                        moved += try StravaExport.moveExports(from: old, to: new)
                    }
                    moved += try StravaExport.moveExports(from: FolderAccess.internalFolder, to: new, subfolder: "Routes",
                                                          isOwn: { $0.hasSuffix("-Tileroam.gpx") })
                    return moved
                }.value
                if moved > 0 { exportMessage = String(localized: "Moved \(moved) earlier saved files to “\(url.lastPathComponent)”.") }
            } catch {
                exportMessage = String(localized: "Could not move earlier saved files: \(error.localizedDescription)")
            }
        }
        syncStrava()
    }

    /// Save in the app's internal storage again. Files already in the chosen folder stay there.
    func useInternalSaveFolder() {
        FolderAccess.clearSaveFolder()
        exportFolderName = nil
        exportFolderLocation = nil
        exportMessage = nil
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

    func disconnectStrava() async {
        stravaTask?.cancel()
        stravaTask = nil
        await strava?.disconnect()
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

        while !Task.isCancelled {
            do {
                try await fetchStravaList(strava)
                try await fetchStravaDetails(strava)
                stravaStatus = nil
                return
            } catch StravaError.rateLimited(let until) {
                saveStrava(athleteID)
                isStravaPaused = true
                defer { isStravaPaused = false }
                stravaStatus = String(localized: "Strava limit reached – continuing at \(until.formatted(date: .omitted, time: .shortened))")
                try? await Task.sleep(for: .seconds(max(1, until.timeIntervalSinceNow)))
            } catch StravaError.unauthorized {
                stravaStatus = nil
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
        // Caches from before virtual detection: fetch the whole list once to set the flag.
        let needsVirtualFlags = stravaActivities.contains { $0.isVirtual == nil }
        let after = needsVirtualFlags ? nil : stravaActivities.compactMap(\.startDate).max()?.addingTimeInterval(-24 * 3600)
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
            let new = await Task.detached(priority: .userInitiated) {
                summaries.map(StravaImport.activity(from:))
            }.value.filter { !known.contains($0.id) }
            if !new.isEmpty {
                stravaActivities += new
                known.formUnion(new.map(\.id))
                recompute()
                if let id = stravaAthleteID { saveStrava(id) }
            }
            if summaries.count < 200 { break }
            page += 1
        }
    }

    /// Downloads full GPS for summary-only activities (most recent first) and saves every
    /// Strava activity as a .fit file in the folder's "Strava" subfolder. Activities that the
    /// folder already has (same start time) are skipped to save API calls and avoid duplicates.
    private func fetchStravaDetails(_ strava: StravaClient) async throws {
        // The chosen save folder, or the app's internal storage; never an import folder.
        let folder = FolderAccess.saveFolder()
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
            await export(index, stream: nil, to: folder)
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
            await export(index, stream: stream, to: folder)
            if (done + 1) % 25 == 0 {
                recompute()
                if let id = stravaAthleteID { saveStrava(id) }
            }
        }
    }

    private func export(_ index: Int, stream: StravaStream?, to folder: URL) async {
        let activity = stravaActivities[index]
        do {
            let name = try await Task.detached(priority: .utility) {
                try StravaExport.write(activity, stream: stream, to: folder)
            }.value
            if let i = stravaActivities.firstIndex(where: { $0.id == activity.id }) {
                stravaActivities[i].exportedFile = name
            }
        } catch {
            stravaError = String(localized: "Could not save to folder: \(error.localizedDescription)")
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

    // MARK: Derived data

    private func recompute() {
        activities = ActivityMerge.merge(folderActivities + stravaActivities)
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
        eddingtonCycling = Eddington(activities: activities, sports: Eddington.cyclingSports)
        eddingtonRunning = Eddington(activities: activities, sports: Eddington.runningSports)
        eddingtonWalking = Eddington(activities: activities, sports: Eddington.walkingSports)
        WidgetData.save(cycling: eddingtonCycling, running: eddingtonRunning)
        version += 1
        if regions != nil { detectCountries() }
        backfillDerived()
    }
}
