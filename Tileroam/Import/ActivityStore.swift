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
        guard let folder = (FolderAccess.importFolders() + [.internalFolder, .iCloudDrive]).first(where: { $0.id == id }) else { return 0 }
        return folderActivities.count { folder.owns($0.id) }
    }

    /// Tileroam's iCloud Drive folder is available (signed in, iCloud Drive on).
    private(set) var isICloudAvailable = false

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
        if regionsError != nil, !isLoadingRegions { loadRegions() } // retry downloads
        await updateICloud() // so Strava saves to iCloud from the start
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

    /// Copies individual .fit files into the Import folder (in iCloud when available) and imports them.
    func importFiles(_ urls: [URL]) async {
        await updateICloud()
        let target = FolderAccess.importTarget
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
        guard !isImporting else { return }
        isImporting = true
        progress = (0, 0)
        defer { isImporting = false }
        await updateICloud()
        // The internal Import folder ("On My iPhone › Tileroam › Import") and the iCloud folder
        // are always read too.
        let folders = FolderAccess.importFolders() + FolderAccess.builtInFolders
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
                    if found == 0, !folder.isBuiltIn {
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

        // Move files saved earlier in the app's own storage (internal or iCloud; in early
        // versions, the first import folder) to the new save folder.
        let ownStorage = [FolderAccess.internalFolder] + [FolderAccess.iCloudFolder].compactMap { $0 }
        let sources = ownStorage + FolderAccess.importFolders().filter { !$0.isBuiltIn }.prefix(1).compactMap(FolderAccess.resolve)
        if let new = FolderAccess.resolve(.export) {
            do {
                let moved = try await Task.detached(priority: .userInitiated) {
                    var moved = 0
                    for old in sources {
                        moved += try StravaExport.moveExports(from: old, to: new)
                    }
                    for old in ownStorage {
                        moved += try StravaExport.moveExports(from: old, to: new, subfolder: "Routes",
                                                              isOwn: { $0.hasSuffix("-Tileroam.gpx") })
                    }
                    return moved
                }.value
                if moved > 0 { exportMessage = String(localized: "Moved \(moved) earlier saved files to “\(url.lastPathComponent)”.") }
            } catch {
                exportMessage = String(localized: "Could not move earlier saved files: \(error.localizedDescription)")
            }
        }
        syncStrava()
    }

    /// Save in Tileroam's own folder again (iCloud Drive, or internal storage without iCloud).
    /// Files already in the chosen folder stay there.
    func useDefaultSaveFolder() {
        FolderAccess.clearSaveFolder()
        exportFolderName = nil
        exportFolderLocation = nil
        exportMessage = nil
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
        await refresh()
    }

    // MARK: iCloud

    private static let movedToICloudKey = "movedToICloud"

    /// Looks up the iCloud folder; the first time it is available, moves what the app saved in
    /// its internal storage there so the user's other devices get it.
    private func updateICloud() async {
        let folder = await Task.detached(priority: .userInitiated) { FolderAccess.updateICloudFolder() }.value
        isICloudAvailable = folder != nil
        guard let folder, !UserDefaults.standard.bool(forKey: Self.movedToICloudKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.movedToICloudKey)
        let saveHere = !FolderAccess.hasChosenSaveFolder
        let moved = await Task.detached(priority: .userInitiated) {
            let local = FolderAccess.internalFolder
            var moved = (try? StravaExport.moveExports(from: local, to: folder, subfolder: "Import",
                                                       isOwn: { $0.lowercased().hasSuffix(".fit") })) ?? 0
            if saveHere {
                moved += (try? StravaExport.moveExports(from: local, to: folder)) ?? 0
                moved += (try? StravaExport.moveExports(from: local, to: folder, subfolder: "Routes",
                                                        isOwn: { $0.hasSuffix("-Tileroam.gpx") })) ?? 0
            }
            return moved
        }.value
        if moved > 0 {
            exportMessage = String(localized: "Moved \(moved) files to \(FolderAccess.iCloudLocation).")
        }
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

    /// Folders where Tileroam may have saved Strava activities: the save folder, its iCloud
    /// folder and its internal storage.
    private var stravaFileFolders: [URL] {
        var folders = [FolderAccess.saveFolder()]
        for url in [FolderAccess.iCloudFolder, FolderAccess.internalFolder].compactMap({ $0 })
        where !folders.contains(where: { $0.standardizedFileURL == url.standardizedFileURL }) {
            folders.append(url)
        }
        return folders
    }

    /// Number of .fit files Tileroam saved from Strava that still exist.
    func countStravaFiles() async -> Int {
        let folders = stravaFileFolders
        return await Task.detached(priority: .userInitiated) {
            folders.reduce(0) { $0 + StravaExport.ownFiles(in: $1).count }
        }.value
    }

    /// Deletes the .fit files Tileroam saved from Strava, in all its folders, and re-imports.
    func deleteStravaFiles() async {
        let folders = stravaFileFolders
        let deleted = await Task.detached(priority: .userInitiated) {
            folders.reduce(0) { $0 + StravaExport.deleteOwnFiles(in: $1) }
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
        let folders = stravaFileFolders
        _ = await Task.detached(priority: .utility) {
            folders.reduce(0) { $0 + StravaExport.deleteOwnFiles(in: $1, activities: removed) }
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
            let new = await Task.detached(priority: .userInitiated) {
                summaries.map(StravaImport.activity(from:))
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
