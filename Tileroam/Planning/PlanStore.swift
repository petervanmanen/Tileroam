import Foundation
import Observation

/// State of the route planning mode.
@MainActor
@Observable
final class PlanStore {
    var isPlanning = false {
        didSet { version += 1 }
    }
    private(set) var selected = Set<PlanTarget>()
    private(set) var route: PlannedRoute?
    /// The selection changed after planning.
    private(set) var routeIsOutdated = false
    private(set) var isWorking = false
    private(set) var status: String?
    private(set) var error: String?
    /// Set when planning waits for Wi-Fi to download this many bytes of map data.
    private(set) var waitingForWiFi: Int?
    /// "Download Anyway": allows one large download over mobile data.
    private var allowMobileDataOnce = false
    private(set) var message: String?
    /// GPX of the current route in a temporary file, for sharing.
    private(set) var gpxURL: URL?
    /// Incremented whenever the map needs to redraw planning overlays.
    private(set) var version = 0
    /// Where the round trip starts and ends; nil is the current location.
    private(set) var start: StartPoint?
    /// The last starting points chosen, newest first.
    private(set) var recentStarts = RecentStarts.load()

    private let router = ValhallaRouter()
    private let location = CurrentLocation()

    func selectedTiles(_ zoom: TileZoom) -> Set<Int64> {
        Set(selected.compactMap { if case .tile(zoom, let k) = $0 { k } else { nil } })
    }

    var selectedMunicipalities: Set<String> {
        Set(selected.compactMap { if case .municipality(let c) = $0 { c } else { nil } })
    }

    var selectedPostcodes: Set<String> {
        Set(selected.compactMap { if case .postcode(let c) = $0 { c } else { nil } })
    }

    var selectionSummary: String {
        let t14 = selectedTiles(.explorer).count, t17 = selectedTiles(.squadratinho).count
        let m = selectedMunicipalities.count, p = selectedPostcodes.count
        var parts = [String]()
        if t14 > 0 { parts.append(TileZoom.explorer.countLabel(t14)) }
        if t17 > 0 { parts.append(TileZoom.squadratinho.countLabel(t17)) }
        if m > 0 { parts.append(String(localized: "\(m) municipalities")) }
        if p > 0 { parts.append(String(localized: "\(p) postcodes")) }
        return parts.isEmpty ? String(localized: "Nothing selected") : String(localized: "Selected: \(parts.joined(separator: " · "))")
    }

    // MARK: Selection

    func toggle(_ target: PlanTarget) {
        if selected.contains(target) {
            selected.remove(target)
        } else {
            guard selected.count < RoutePlanner.maxTargets else {
                error = String(localized: "You can select up to \(RoutePlanner.maxTargets) items per route.")
                return
            }
            selected.insert(target)
        }
        error = nil
        if route?.source == .planned { routeIsOutdated = true }
        version += 1
    }

    func clear() {
        selected = []
        closeRoute()
    }

    func closeRoute() {
        route = nil
        gpxURL = nil
        routeIsOutdated = false
        error = nil
        message = nil
        version += 1
    }

    // MARK: Starting point

    /// Starts from `start`, or from the current location when nil. `remember` adds it to the recent
    /// starting points.
    func setStart(_ start: StartPoint?, remember: Bool = true) {
        self.start = start
        if let start, remember {
            recentStarts = RecentStarts.adding(start, to: recentStarts)
            RecentStarts.save(recentStarts)
        }
        error = start.map { RoutingData.covers($0.point) } == false ? RoutingError.outsideRegion.localizedDescription : nil
        waitingForWiFi = nil
        if route?.source == .planned { routeIsOutdated = true }
        version += 1
    }

    func removeRecentStart(_ start: StartPoint) {
        recentStarts.removeAll { $0 == start }
        RecentStarts.save(recentStarts)
    }

    // MARK: Planning

    func plan(with store: ActivityStore) async {
        guard !selected.isEmpty, !isWorking else { return }
        isWorking = true
        error = nil
        message = nil
        waitingForWiFi = nil
        defer {
            isWorking = false
            status = nil
            allowMobileDataOnce = false
        }
        do {
            let from: GeoPoint
            if let start {
                from = start.point
            } else {
                status = String(localized: "Finding your location…")
                let here = try await location.get().coordinate
                from = GeoPoint(lat: here.latitude, lon: here.longitude)
            }
            try await plan(from: from, with: store)
        } catch RoutingError.waitingForWiFi(let bytes) {
            waitingForWiFi = bytes
            self.error = RoutingError.waitingForWiFi(bytes: bytes).localizedDescription
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Removes downloaded route planning areas (Settings → Storage).
    func removeRoutingData(_ tiles: [RoutingIndex.Tile], all: Bool) async {
        guard let index = RoutingData.index else { return }
        await router.forget()
        if all { RoutingData.removeAll(index) } else { RoutingData.remove(tiles, index: index) }
    }

    /// Plans again, downloading the map data over mobile data this once.
    func downloadAnyway(with store: ActivityStore) async {
        allowMobileDataOnce = true
        await plan(with: store)
    }

    func plan(from start: GeoPoint, with store: ActivityStore) async throws {
        let regions: RegionData? = await store.loadedRegions()
        let targets = selected.sorted { $0.sortKey < $1.sortKey }
            .compactMap { TargetGeometry($0, regions: regions) }
        // The routing data covers the Netherlands, Belgium, Luxembourg and Germany.
        guard RoutingData.covers(start),
              targets.allSatisfy({ $0.candidates().contains(where: RoutingData.covers) }) else {
            throw RoutingError.outsideRegion
        }
        let points = [start] + targets.flatMap { $0.candidates() }
        let visited = (store.tiles14, store.tiles17, store.visitedMunicipalities, store.visitedPostcodes)
        let router = self.router
        func attempt() async throws -> PlannedRoute {
            try await Task.detached(priority: .userInitiated) {
                try await RoutePlanner.planRoute(
                    start: start, targets: targets, client: router,
                    coverage: { RouteCoverage(route: $0, visitedTiles14: visited.0, visitedTiles17: visited.1,
                                              visitedMunicipalities: visited.2, visitedPostcodes: visited.3, regions: regions) },
                    progress: { [weak self] in self?.status = $0 })
            }.value
        }

        // Only the 1° areas around the plan (with room for detours) are downloaded; if the route
        // still needs more, try once more with a wider area.
        var planned: PlannedRoute
        do {
            try await prepareRouting(around: points, margin: 15_000)
            planned = try await attempt()
        } catch RoutingError.engine {
            try await prepareRouting(around: points, margin: 60_000)
            planned = try await attempt()
        }
        show(planned)
    }

    /// Gets the routing data for the area, saying how much has to be downloaded.
    private func prepareRouting(around points: [GeoPoint], margin: Double) async throws {
        if let index = RoutingData.index {
            let bytes = RoutingData.downloadBytes(for: RoutingData.tiles(around: points, margin: margin, in: index), index: index)
            guard MapDataDownloads.mayDownload(bytes: bytes, allowedOnce: allowMobileDataOnce) else {
                throw RoutingError.waitingForWiFi(bytes: bytes)
            }
            status = bytes > 0
                ? String(localized: "Downloading map data for route planning (about \(MapDataDownloads.format(bytes)))…")
                : String(localized: "Loading the route planning data…")
        }
        try await router.prepare(around: points, margin: margin)
    }

    #if DEBUG
    /// Simulator check without tapping: -PlanDemo YES plans a route near Utrecht,
    /// -PlanGPX /path/file.gpx imports a GPX, -PlanStart "52.09,5.12" opens planning from that start.
    func runDebugDemo(with store: ActivityStore) async {
        if let text = UserDefaults.standard.string(forKey: "PlanStart") {
            let parts = text.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            if parts.count == 2 {
                isPlanning = true
                let point = GeoPoint(lat: parts[0], lon: parts[1])
                setStart(await StartPoint.dropped(at: point), remember: false)
            }
        }
        if let path = UserDefaults.standard.string(forKey: "PlanGPX") {
            isPlanning = true
            await importGPX(URL(filePath: path), with: store)
            return
        }
        guard UserDefaults.standard.bool(forKey: "PlanDemo") else { return }
        await planDemoRoute(with: store)
    }

    /// Selects a few unvisited tiles, a municipality and a postcode near Utrecht and plans a route.
    /// With a `pace`, the selection happens one item at a time (for the App Store preview video).
    func planDemoRoute(with store: ActivityStore, pace: Duration? = nil) async {
        let regions = await store.loadedRegions()
        isPlanning = true
        var start = GeoPoint(lat: 52.0907, lon: 5.1214)
        var startName = "Utrecht Centrum"
        // -PlanDemoStart "lat,lon": the same demo elsewhere, for example at a border.
        let parts = (UserDefaults.standard.string(forKey: "PlanDemoStart") ?? "").split(separator: ",").compactMap { Double($0) }
        if parts.count == 2 {
            start = GeoPoint(lat: parts[0], lon: parts[1])
            startName = StartPoint.coordinateName(start)
        }
        setStart(StartPoint(name: startName, start), remember: false)
        // The four nearest unvisited tiles around the start.
        let startCell = TileGrid.cell(lat: start.lat, lon: start.lon, zoom: .explorer)!
        var candidates = [(distance: Int, key: Int64)]()
        for dx in -6...6 {
            for dy in -6...6 where max(abs(dx), abs(dy)) >= 1 {
                let k = TileGrid.key(x: startCell.x + dx, y: startCell.y + dy)
                if !store.tiles14.contains(k) { candidates.append((dx * dx + dy * dy, k)) }
            }
        }
        for c in candidates.sorted(by: { $0.distance < $1.distance }).prefix(4) {
            toggle(.tile(.explorer, c.key))
            if let pace { try? await Task.sleep(for: pace) }
        }
        func nearestUnvisited(_ set: AreaSet, _ visited: Set<String>) -> Area? {
            set.all.filter { !visited.contains($0.code) }.min {
                Geo.distance(GeoPoint(lat: ($0.minLat + $0.maxLat) / 2, lon: ($0.minLon + $0.maxLon) / 2), start)
                    < Geo.distance(GeoPoint(lat: ($1.minLat + $1.maxLat) / 2, lon: ($1.minLon + $1.maxLon) / 2), start)
            }
        }
        if let m = nearestUnvisited(regions.municipalities, store.visitedMunicipalities) {
            toggle(.municipality(m.code))
            if let pace { try? await Task.sleep(for: pace) }
        }
        if let p = nearestUnvisited(regions.postcodes, store.visitedPostcodes) {
            toggle(.postcode(p.code))
            if let pace { try? await Task.sleep(for: pace) }
        }
        isWorking = true
        defer { isWorking = false; status = nil }
        do {
            try await plan(from: start, with: store)
            if let url = gpxURL { print("PLAN_DEMO_GPX \(url.path(percentEncoded: false))") }
        } catch {
            self.error = error.localizedDescription
        }
    }
    #endif

    // MARK: GPX

    func importGPX(_ url: URL, with store: ActivityStore) async {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? FolderAccess.read(url), let gpx = GPX.parse(data), gpx.points.count >= 2 else {
            error = String(localized: "Could not read “\(url.lastPathComponent)” as a GPX route.")
            return
        }
        isWorking = true
        status = String(localized: "Checking which tiles and areas this route passes…")
        defer {
            isWorking = false
            status = nil
        }
        let regions: RegionData? = await store.loadedRegions()
        let visited = (store.tiles14, store.tiles17, store.visitedMunicipalities, store.visitedPostcodes)
        let points = gpx.points
        let coverage = await Task.detached(priority: .userInitiated) {
            RouteCoverage(route: points, visitedTiles14: visited.0, visitedTiles17: visited.1,
                          visitedMunicipalities: visited.2, visitedPostcodes: visited.3, regions: regions)
        }.value
        let distance = zip(points, points.dropFirst()).reduce(0) { $0 + Geo.distance($1.0, $1.1) }
        let name = gpx.name ?? url.deletingPathExtension().lastPathComponent
        show(PlannedRoute(source: .imported(name: name), coordinates: points, distance: distance, duration: nil,
                          stops: [], coverage: coverage, missed: []))
    }

    private func show(_ route: PlannedRoute) {
        self.route = route
        routeIsOutdated = false
        gpxURL = nil
        if route.source == .planned {
            let url = FileManager.default.temporaryDirectory.appending(path: Self.fileName())
            if (try? GPX.write(name: route.name, track: route.coordinates, waypoints: route.stops).write(to: url)) != nil {
                gpxURL = url
            }
        }
        version += 1
    }

    static func fileName(date: Date = .now) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmm"
        return "\(f.string(from: date))-Tileroam.gpx"
    }

    /// Saves the planned route in the save folder (Tileroam/Routes).
    func saveToFolder() async {
        guard let route, route.source == .planned else { return }
        let folder = FolderAccess.saveFolder()
        let data = GPX.write(name: route.name, track: route.coordinates, waypoints: route.stops)
        let name = Self.fileName()
        do {
            try await Task.detached(priority: .userInitiated) {
                try SaveFolder.write(data, name: name, subfolder: "Routes", in: folder)
            }.value
            let place = FolderAccess.hasChosenSaveFolder ? folder.lastPathComponent : FolderAccess.defaultSaveLocation
            message = String(localized: "Saved to \(place)/Routes/\(name)")
        } catch {
            self.error = String(localized: "Could not save: \(error.localizedDescription)")
        }
    }
}
