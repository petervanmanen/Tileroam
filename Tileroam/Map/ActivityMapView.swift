import CoreLocation
import MapKit
import SwiftUI

enum MapMode: String, CaseIterable, Identifiable {
    // (A Routes mode with all rides drawn in sport colours, "activities", was removed in 1.5.3; a
    // stored "activities" no longer decodes, so those users start on Tiles.)
    case squares, gemeenten, postcodes, climbs, trappists, boscafes, ferries, klompenpaden, mtb

    var id: Self { self }

    var title: String {
        switch self {
        case .squares: String(localized: "Tiles")
        case .gemeenten: String(localized: "Municipalities", comment: "Map mode: municipalities (gemeenten, communes, Gemeinden…)")
        case .postcodes: String(localized: "Postcodes")
        case .climbs: String(localized: "Climbs")
        case .trappists: String(localized: "Trappist Challenge")
        case .boscafes: String(localized: "Boscafé Challenge")
        case .ferries: String(localized: "Ferries")
        case .klompenpaden: String(localized: "Klompenpaden")
        case .mtb: String(localized: "Mountain bike routes")
        }
    }

    /// Short name for the segmented control at the top of the map.
    var tabTitle: String {
        switch self {
        case .squares: String(localized: "tab.tiles", defaultValue: "Tiles")
        case .gemeenten: String(localized: "tab.municipalities", defaultValue: "Towns")
        case .postcodes: String(localized: "tab.postcodes", defaultValue: "Postcodes")
        case .climbs: String(localized: "tab.climbs", defaultValue: "Climbs")
        case .trappists: String(localized: "tab.trappists", defaultValue: "Trappists")
        case .boscafes: String(localized: "tab.boscafes", defaultValue: "Boscafés")
        case .ferries: String(localized: "tab.ferries", defaultValue: "Ferries")
        case .klompenpaden: String(localized: "tab.klompenpaden", defaultValue: "Klompenpaden")
        case .mtb: String(localized: "tab.mtb", defaultValue: "MTB")
        }
    }

    /// SF Symbol for Settings → Challenges.
    var symbol: String {
        switch self {
        case .squares: "square.grid.3x3"
        case .gemeenten: "building.2"
        case .postcodes: "envelope"
        case .climbs: "mountain.2"
        case .trappists: "mug"
        case .boscafes: "tree"
        case .ferries: "ferry"
        case .klompenpaden: "shoeprints.fill"
        case .mtb: "bicycle"
        }
    }

    /// Area-based challenge shown in this mode, if any.
    @MainActor
    func areas(in store: ActivityStore) -> (set: AreaSet, visited: Set<String>)? {
        switch self {
        case .gemeenten: store.municipalityAreas.map { ($0, store.visitedMunicipalities) }
        case .postcodes: store.postcodeAreas.map { ($0, store.visitedPostcodes) }
        default: nil
        }
    }
}

/// The map modes besides Tiles are challenges the user turns on (Settings, or the
/// Challenges menu at the end of the mode bar). All are off by default, so the bar stays short.
enum Challenges {
    /// UserDefaults key (synced through SettingsSync): the turned-on modes, comma-separated.
    static let key = "challenges"
    static let all: [MapMode] = [.gemeenten, .postcodes, .climbs, .trappists, .boscafes, .ferries, .klompenpaden, .mtb]

    static func decode(_ raw: String) -> Set<MapMode> {
        Set(raw.split(separator: ",").compactMap { MapMode(rawValue: String($0)) }).intersection(all)
    }

    static func encode(_ modes: Set<MapMode>) -> String {
        all.filter(modes.contains).map(\.rawValue).joined(separator: ",")
    }

    /// The modes in the bar: Tiles and the turned-on challenges.
    static func visibleModes(_ raw: String) -> [MapMode] {
        let on = decode(raw)
        return MapMode.allCases.filter { $0 == .squares || on.contains($0) }
    }
}

extension MapMode {
    var isChallenge: Bool { Challenges.all.contains(self) }
}

/// Base map shown under the overlays.
enum MapStyle: String, CaseIterable, Identifiable {
    case standard, satellite, hybrid

    var id: Self { self }

    var title: String {
        switch self {
        case .standard: String(localized: "Map")
        case .satellite: String(localized: "Satellite")
        case .hybrid: String(localized: "Hybrid")
        }
    }

    var symbol: String {
        switch self {
        case .standard: "map"
        case .satellite: "globe.europe.africa.fill"
        case .hybrid: "map.fill"
        }
    }

    /// Flat (no 3D terrain or buildings), so tiles and areas line up with the ground.
    var configuration: MKMapConfiguration {
        switch self {
        case .standard: MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        case .satellite: MKImageryMapConfiguration(elevationStyle: .flat)
        case .hybrid: MKHybridMapConfiguration(elevationStyle: .flat)
        }
    }
}

struct ActivityMapView: UIViewRepresentable {
    let mode: MapMode
    var mapStyle: MapStyle = .standard
    /// Tile zoom level shown (both are always calculated).
    let tileZoom: TileZoom
    let store: ActivityStore
    /// Passed explicitly so SwiftUI updates the view when the data changes.
    let version: Int
    @Binding var selectedArea: Area?
    @Binding var selectedClimb: Climb?
    @Binding var selectedTrappist: Trappist?
    @Binding var selectedBoscafe: Boscafe?
    @Binding var selectedFerry: Ferry?
    @Binding var selectedKlompenpad: Klompenpad?
    @Binding var selectedMTBRoute: MTBRoute?
    /// Incremented by the "my location" button.
    let locateRequest: Int
    @Binding var isFollowingUser: Bool
    @Binding var locationDenied: Bool
    let plan: PlanStore
    let planVersion: Int
    /// Width covered by the iPad side panel; route and launch zoom keep clear of it.
    var leadingInset: CGFloat = 0

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        let status = CLLocationManager().authorizationStatus
        map.showsUserLocation = status == .authorizedWhenInUse || status == .authorizedAlways
        map.preferredConfiguration = mapStyle.configuration
        map.isPitchEnabled = false // no tilt: tiles and areas stay flat on the map
        map.isRotateEnabled = false // always north up (issue #39)
        map.pointOfInterestFilter = .excludingAll
        map.region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 52.2, longitude: 5.3),
                                        span: MKCoordinateSpan(latitudeDelta: 3.4, longitudeDelta: 3.4))
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        map.addGestureRecognizer(tap)
        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        map.addGestureRecognizer(longPress)
        map.addInteraction(context.coordinator.placeMenu)
        #if DEBUG
        // Screenshots and checks: -MapCenter "50.85,5.85,0.3" (latitude, longitude, span in degrees).
        let center = (UserDefaults.standard.string(forKey: "MapCenter") ?? "").split(separator: ",").compactMap { Double($0) }
        if center.count == 3 {
            map.region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: center[0], longitude: center[1]),
                                            span: MKCoordinateSpan(latitudeDelta: center[2], longitudeDelta: center[2]))
            context.coordinator.skipFocus()
        }
        // -PlaceMenuDemo YES: opens the long-press menu in the middle of the map after launch.
        if UserDefaults.standard.bool(forKey: "PlaceMenuDemo") {
            Task { @MainActor [weak map, coordinator = context.coordinator] in
                try? await Task.sleep(for: .seconds(8))
                guard let map else { return }
                coordinator.showPlaceMenu(at: CGPoint(x: map.bounds.midX, y: map.bounds.midY), on: map)
            }
        }
        #endif
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        // Keeps the Apple Maps legal label and compass clear of the side panel.
        if map.layoutMargins.left != leadingInset {
            map.layoutMargins = UIEdgeInsets(top: 0, left: leadingInset, bottom: 0, right: 0)
        }
        context.coordinator.parent = self
        context.coordinator.applyStyle(map)
        context.coordinator.update(map)
        context.coordinator.handleLocateRequest(map)
    }

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate, CLLocationManagerDelegate, @MainActor UIEditMenuInteractionDelegate {
        var parent: ActivityMapView
        /// Planning mode: the menu a long-press opens, "Start Here" / "End Here".
        lazy var placeMenu = UIEditMenuInteraction(delegate: self)
        /// Where the map was long-pressed, for that menu.
        private var pressedPoint: GeoPoint?
        private let locationManager = CLLocationManager()
        private var handledLocateRequest = 0
        private weak var mapView: MKMapView?
        private var centerWhenAuthorized = false
        private var appliedMode: MapMode?
        private var appliedVersion = -1
        private var appliedPlanVersion = -1
        private var appliedTileZoom: TileZoom?
        private var appliedClimb: String?
        private var appliedKlompenpad: String?
        private var appliedMTBRoute: String?
        private var appliedStyle: MapStyle?

        func applyStyle(_ map: MKMapView) {
            guard appliedStyle != parent.mapStyle else { return }
            appliedStyle = parent.mapStyle
            map.preferredConfiguration = parent.mapStyle.configuration
        }
        private var zoomedRouteID: UUID?
        private var hasFocused = false

        /// Keep the map where it was opened (-MapCenter).
        func skipFocus() { hasFocused = true }
        /// Focused on Apple Park for lack of data; refocus once data arrives.
        private var focusedOnFallback = false

        private var areaGeometry: [MapMode: AreaGeometry] = [:]
        private var areaGeometryKey: String?

        init(parent: ActivityMapView) {
            self.parent = parent
            self.handledLocateRequest = parent.locateRequest
            super.init()
            locationManager.delegate = self
        }

        // MARK: Current location

        func handleLocateRequest(_ map: MKMapView) {
            mapView = map
            guard parent.locateRequest != handledLocateRequest else { return }
            handledLocateRequest = parent.locateRequest
            switch locationManager.authorizationStatus {
            case .notDetermined:
                centerWhenAuthorized = true
                locationManager.requestWhenInUseAuthorization()
            case .denied, .restricted:
                parent.locationDenied = true
            default:
                centerOnUser(map)
            }
        }

        private func centerOnUser(_ map: MKMapView) {
            map.showsUserLocation = true
            if map.userTrackingMode == .follow {
                map.setUserTrackingMode(.none, animated: true)
            } else {
                map.setUserTrackingMode(.follow, animated: true)
            }
        }

        nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
            let status = manager.authorizationStatus
            MainActor.assumeIsolated {
                guard let map = mapView else { return }
                switch status {
                case .authorizedWhenInUse, .authorizedAlways:
                    map.showsUserLocation = true
                    if centerWhenAuthorized {
                        centerWhenAuthorized = false
                        map.setUserTrackingMode(.follow, animated: true)
                    }
                case .denied, .restricted:
                    if centerWhenAuthorized {
                        centerWhenAuthorized = false
                        parent.locationDenied = true
                    }
                default:
                    break
                }
            }
        }

        func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
            if let location = userLocation.location { WidgetData.saveLocation(location.coordinate) }
        }

        func mapView(_ mapView: MKMapView, didChange mode: MKUserTrackingMode, animated: Bool) {
            parent.isFollowingUser = mode != .none
        }

        /// Climbs tab: the climbs of the visible area (downloaded where needed).
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            loadClimbs(mapView)
        }

        private func loadClimbs(_ map: MKMapView) {
            guard parent.mode == .climbs else { return }
            let r = map.region, store = parent.store
            Task {
                await store.loadClimbs(minLat: r.center.latitude - r.span.latitudeDelta / 2, maxLat: r.center.latitude + r.span.latitudeDelta / 2,
                                       minLon: r.center.longitude - r.span.longitudeDelta / 2, maxLon: r.center.longitude + r.span.longitudeDelta / 2)
            }
        }

        func update(_ map: MKMapView) {
            guard appliedMode != parent.mode || appliedVersion != parent.version || appliedPlanVersion != parent.planVersion
                || appliedTileZoom != parent.tileZoom || appliedClimb != parent.selectedClimb?.id
                || appliedKlompenpad != parent.selectedKlompenpad?.id
                || appliedMTBRoute != parent.selectedMTBRoute?.id else { return }
            appliedMTBRoute = parent.selectedMTBRoute?.id
            appliedClimb = parent.selectedClimb?.id
            appliedKlompenpad = parent.selectedKlompenpad?.id
            appliedTileZoom = parent.tileZoom
            if appliedMode != parent.mode, parent.mode == .climbs { loadClimbs(map) }
            appliedMode = parent.mode
            appliedVersion = parent.version
            appliedPlanVersion = parent.planVersion

            map.removeOverlays(map.overlays)
            map.removeAnnotations(map.annotations.filter { !($0 is MKUserLocation) })
            let store = parent.store
            let plan = parent.plan
            let planning = plan.isPlanning
            let coverage = planning ? plan.route?.coverage : nil

            switch parent.mode {
            case .squares:
                let zoom = parent.tileZoom
                map.addOverlay(TilesOverlay(zoom: zoom, visited: store.tiles(zoom), stats: store.tileStats(zoom),
                                            selected: planning ? plan.selectedTiles(zoom) : [],
                                            highlight: coverage?.newTiles(zoom) ?? []), level: .aboveRoads)
            case .gemeenten, .postcodes:
                guard let (areas, visitedCodes) = parent.mode.areas(in: store) else { break }
                if areaGeometryKey != store.regions?.key {
                    areaGeometry = [:] // countries changed
                    areaGeometryKey = store.regions?.key
                }
                let geometry = areaGeometry[parent.mode] ?? AreaGeometry(areas.all)
                areaGeometry[parent.mode] = geometry
                let selected = !planning ? [] : parent.mode == .gemeenten ? plan.selectedMunicipalities : plan.selectedPostcodes
                let highlight = (parent.mode == .gemeenten ? coverage?.newMunicipalities : coverage?.newPostcodes) ?? []
                map.addOverlay(AreaOverlay(geometry: geometry, visited: visitedCodes, selected: selected, highlight: highlight),
                               level: .aboveRoads)
            case .climbs:
                let selected = planning ? plan.selectedClimbs : Set(parent.selectedClimb.map { [$0.id] } ?? [])
                let onRoute = coverage?.climbs ?? []
                // The selected climbs (and those on a planned route) in blue, a colour no category
                // uses, thicker and on top (issue #40).
                var groups = [UIColor: [MKPolyline]]()
                var highlighted = [MKPolyline]()
                for climb in store.climbs.values {
                    let coords = climb.points.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
                    let line = MKPolyline(coordinates: coords, count: coords.count)
                    if selected.contains(climb.id) || onRoute.contains(climb.id) {
                        highlighted.append(line)
                    } else {
                        groups[store.climbed[climb.id] != nil ? .systemGreen : Self.color(for: climb.cat), default: []].append(line)
                    }
                }
                for (color, lines) in groups {
                    let multi = ClimbLines(lines)
                    multi.color = color
                    map.addOverlay(multi, level: .aboveRoads)
                }
                if !highlighted.isEmpty {
                    let multi = ClimbLines(highlighted)
                    multi.color = Self.selectedClimbColor
                    multi.width = 7
                    map.addOverlay(multi, level: .aboveRoads)
                }
            case .klompenpaden:
                // Two colours (issue #41): walked green, not (yet) walked dark orange. The selected
                // path keeps its colour, drawn thicker and on top; its card shows the progress.
                addRouteLines(store.klompenpaden, progress: store.klompenpadProgress, selected: parent.selectedKlompenpad?.id, to: map)
            case .mtb:
                // Like the Klompenpaden: ridden green, not (yet) ridden dark orange; the selected
                // route thicker and on top.
                addRouteLines(store.mtbRoutes, progress: store.mtbProgress, selected: parent.selectedMTBRoute?.id, to: map)
            case .trappists:
                let marked = planning ? plan.selectedTrappists.union(coverage?.trappists ?? []) : []
                map.addAnnotations(store.trappists.map {
                    PlaceAnnotation(place: $0, icon: $0.icon, visited: store.trappistVisits[$0.id] != nil, marked: marked.contains($0.id))
                })
            case .boscafes:
                let marked = planning ? plan.selectedBoscafes.union(coverage?.boscafes ?? []) : []
                map.addAnnotations(store.boscafes.map {
                    PlaceAnnotation(place: $0, emoji: $0.emoji, visited: store.boscafeVisits[$0.id] != nil, marked: marked.contains($0.id))
                })
            case .ferries:
                map.addAnnotations(store.ferries.map {
                    PlaceAnnotation(place: $0, emoji: "⛴️", visited: store.ferryCrossings[$0.id] != nil)
                })
            }

            if planning, let start = plan.start {
                let pin = StartAnnotation()
                pin.coordinate = CLLocationCoordinate2D(latitude: start.lat, longitude: start.lon)
                pin.title = start.name
                map.addAnnotation(pin)
            }
            if planning, let end = plan.end {
                let pin = EndAnnotation()
                pin.coordinate = CLLocationCoordinate2D(latitude: end.lat, longitude: end.lon)
                pin.title = end.name
                map.addAnnotation(pin)
            }

            if planning, let route = plan.route {
                hasFocused = true // don't move away from the route
                showRoute(route, on: map)
            }

            focusIfNeeded(map)
        }

        /// On launch: center on the biggest cluster of what the current view shows, with one
        /// zoom-10 tile filling the screen height; Apple Park when there is nothing yet.
        private func focusIfNeeded(_ map: MKMapView) {
            guard !hasFocused || focusedOnFallback else { return }
            let store = parent.store
            var center: GeoPoint?
            var ready = true
            switch parent.mode {
            case .squares:
                ready = store.statsReady
                let zoom = parent.tileZoom
                if let c = store.tileStats(zoom).maxClusterCenter {
                    center = TileGrid.coordinate(x: c.x, y: c.y, zoom: zoom)
                } else {
                    center = MapFocus.densestCenter(store.tiles(zoom).map {
                        let c = TileGrid.cell(of: $0)
                        return TileGrid.coordinate(x: Double(c.x) + 0.5, y: Double(c.y) + 0.5, zoom: zoom)
                    })
                }
            case .climbs, .trappists, .boscafes, .ferries, .klompenpaden, .mtb:
                center = MapFocus.densestCenter(store.mapActivities.flatMap { a in
                    a.coordinates.enumerated().filter { $0.offset % 10 == 0 }.map { GeoPoint(lat: $0.element.latitude, lon: $0.element.longitude) }
                })
            case .gemeenten, .postcodes:
                if let (areas, visited) = parent.mode.areas(in: store) {
                    center = MapFocus.densestCenter(visited.compactMap { areas.area(code: $0) }.map {
                        GeoPoint(lat: ($0.minLat + $0.maxLat) / 2, lon: ($0.minLon + $0.maxLon) / 2)
                    })
                } else {
                    ready = false
                }
            }
            if center == nil, ready, hasFocused { return } // still nothing: stay where we are
            if center == nil, !ready, !store.activities.isEmpty { return } // wait for the data
            let target = center ?? MapFocus.appleHQ
            let visibleWidth = max(map.bounds.width - parent.leadingInset, 1)
            let aspect = map.bounds.height > 0 ? Double(visibleWidth / map.bounds.height) : 0.5
            show(MapFocus.rect(center: target, aspectRatio: aspect), on: map, padding: .zero, animated: hasFocused)
            hasFocused = true
            focusedOnFallback = center == nil
        }

        /// Shows `rect` with extra `padding`. MapKit already keeps clear of the iPad side panel
        /// through the map's `layoutMargins` (set from `leadingInset`), so that is not added here.
        private func show(_ rect: MKMapRect, on map: MKMapView, padding: UIEdgeInsets, animated: Bool) {
            map.setVisibleMapRect(rect, edgePadding: padding, animated: animated)
        }

        // MARK: Planned route

        final class RoutePolyline: MKPolyline {
            var isCasing = false
        }

        private func showRoute(_ route: PlannedRoute, on map: MKMapView) {
            let coords = route.coordinates.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
            let casing = RoutePolyline(coordinates: coords, count: coords.count)
            casing.isCasing = true
            map.addOverlay(casing, level: .aboveLabels)
            map.addOverlay(RoutePolyline(coordinates: coords, count: coords.count), level: .aboveLabels)
            for (i, stop) in route.stops.enumerated() {
                let a = MKPointAnnotation()
                a.coordinate = CLLocationCoordinate2D(latitude: stop.point.lat, longitude: stop.point.lon)
                a.title = "\(i + 1)"
                a.subtitle = stop.name
                map.addAnnotation(a)
            }
            if zoomedRouteID != route.id {
                zoomedRouteID = route.id
                let wide = parent.leadingInset > 0
                show(casing.boundingMapRect, on: map,
                     padding: UIEdgeInsets(top: wide ? 60 : 160, left: 40, bottom: wide ? 60 : 260, right: 40), animated: true)
            }
        }

        /// The chosen starting point; drag it to move the start.
        final class StartAnnotation: MKPointAnnotation {}
        /// The chosen end of a point-to-point route; drag it to move the end.
        final class EndAnnotation: MKPointAnnotation {}

        /// A Trappist brewery or a boscafé, drawn as its logo or emoji in a white badge: green ring
        /// and check once visited.
        final class PlaceAnnotation: NSObject, MKAnnotation {
            let place: any ChallengePlace
            /// A brewery's logo (nil until downloaded: its initial is drawn instead).
            let icon: UIImage?
            /// A boscafé's emoji.
            let emoji: String?
            let visited: Bool
            /// Selected for a plan, or on the planned route: orange ring.
            let marked: Bool
            var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: place.lat, longitude: place.lon) }
            var title: String? { place.name }

            init(place: any ChallengePlace, icon: UIImage? = nil, emoji: String? = nil, visited: Bool, marked: Bool = false) {
                self.place = place
                self.icon = icon
                self.emoji = emoji
                self.visited = visited
                self.marked = marked
            }

            /// The badge, rendered once per brewery and state.
            func badge() -> UIImage {
                let size = CGSize(width: 46, height: 46)
                return UIGraphicsImageRenderer(size: size).image { _ in
                    let rect = CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2)
                    let ring = marked ? UIColor.systemOrange : visited ? UIColor.systemGreen : UIColor.systemGray
                    UIColor.white.setFill()
                    let circle = UIBezierPath(ovalIn: rect)
                    circle.fill()
                    if let icon {
                        icon.draw(in: rect.insetBy(dx: 5, dy: 5))
                    } else {
                        // A boscafé's emoji, or a brewery's initial while its logo isn't downloaded.
                        let text = (emoji ?? String(place.name.prefix(1))) as NSString
                        let font = emoji != nil ? UIFont.systemFont(ofSize: 24) : UIFont.boldSystemFont(ofSize: 20)
                        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.black]
                        let s = text.size(withAttributes: attributes)
                        text.draw(at: CGPoint(x: (size.width - s.width) / 2, y: (size.height - s.height) / 2), withAttributes: attributes)
                    }
                    ring.setStroke()
                    circle.lineWidth = marked ? 4 : 3
                    circle.stroke()
                    if visited, let check = UIImage(systemName: "checkmark.circle.fill")?
                        .withTintColor(.systemGreen, renderingMode: .alwaysOriginal) {
                        let c = CGRect(x: size.width - 17, y: size.height - 17, width: 16, height: 16)
                        UIColor.white.setFill()
                        UIBezierPath(ovalIn: c).fill()
                        check.draw(in: c)
                    }
                }
            }
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard !(annotation is MKUserLocation) else { return nil }
            if let place = annotation as? PlaceAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: "place")
                    ?? MKAnnotationView(annotation: annotation, reuseIdentifier: "place")
                view.annotation = annotation
                view.image = place.badge()
                view.canShowCallout = false
                view.displayPriority = .required
                view.collisionMode = .circle
                return view
            }
            if annotation is StartAnnotation || annotation is EndAnnotation {
                let isEnd = annotation is EndAnnotation
                let id = isEnd ? "end" : "start"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView
                    ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
                view.annotation = annotation
                view.glyphImage = UIImage(systemName: isEnd ? "flag.checkered" : "flag.fill")
                view.markerTintColor = isEnd ? .systemRed : .systemGreen
                view.titleVisibility = .adaptive
                view.canShowCallout = false
                view.isDraggable = true
                view.displayPriority = .required
                return view
            }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: "stop") as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "stop")
            view.annotation = annotation
            view.glyphText = annotation.title ?? nil
            view.markerTintColor = .systemPurple
            view.titleVisibility = .hidden
            view.canShowCallout = true
            view.displayPriority = .required
            return view
        }

        /// A route challenge's routes: done (at least `KlompenpadMatcher.done`) green, others dark
        /// orange; the selected one keeps its colour, thicker and on top.
        private func addRouteLines<Route: ChallengeRoute>(_ routes: [Route], progress: [String: Double], selected: String?, to map: MKMapView) {
            var groups = [UIColor: [MKPolyline]]()
            var selectedLines = [MKPolyline](), selectedColor = Self.klompenpadOpen
            for route in routes {
                let color = (progress[route.id] ?? 0) >= KlompenpadMatcher.done ? UIColor.systemGreen : Self.klompenpadOpen
                let lines = route.pieces.map { piece in
                    let coords = piece.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
                    return MKPolyline(coordinates: coords, count: coords.count)
                }
                if route.id == selected {
                    selectedLines = lines
                    selectedColor = color
                } else {
                    groups[color, default: []] += lines
                }
            }
            for (color, lines) in groups {
                let multi = ClimbLines(lines)
                multi.color = color
                map.addOverlay(multi, level: .aboveRoads)
            }
            if !selectedLines.isEmpty {
                let multi = ClimbLines(selectedLines)
                multi.color = selectedColor
                multi.width = 8
                map.addOverlay(multi, level: .aboveRoads)
            }
        }

        /// Climbs (or a route challenge's routes) drawn in one colour.
        final class ClimbLines: MKMultiPolyline {
            var color = UIColor.systemRed
            var width: CGFloat = 4
        }

        /// A selected climb: no category uses blue.
        static let selectedClimbColor = UIColor.systemBlue
        /// A Klompenpad not (yet) walked.
        static let klompenpadOpen = UIColor(red: 0.85, green: 0.35, blue: 0.0, alpha: 1)

        static func color(for category: Climb.Category) -> UIColor {
            switch category {
            case .hill: .systemYellow
            case .cat4: UIColor(red: 1, green: 0.55, blue: 0.1, alpha: 1)
            case .cat3: .systemRed
            case .cat2: UIColor(red: 0.75, green: 0.05, blue: 0.15, alpha: 1)
            case .cat1: .systemPurple
            case .hc: .black
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            switch overlay {
            case let tiles as TilesOverlay:
                return TilesRenderer(overlay: tiles)
            case let route as RoutePolyline:
                let r = MKPolylineRenderer(polyline: route)
                r.strokeColor = route.isCasing ? .white : .systemPurple
                r.lineWidth = route.isCasing ? 8 : 5
                r.lineCap = .round
                r.lineJoin = .round
                return r
            case let climbs as ClimbLines:
                let r = MKMultiPolylineRenderer(multiPolyline: climbs)
                r.strokeColor = climbs.color.withAlphaComponent(0.9)
                r.lineWidth = climbs.width
                r.lineCap = .round
                return r
            case let areas as AreaOverlay:
                return AreaRenderer(overlay: areas)
            default:
                return MKOverlayRenderer(overlay: overlay)
            }
        }

        func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView,
                     didChange newState: MKAnnotationView.DragState, fromOldState oldState: MKAnnotationView.DragState) {
            guard newState == .ending, let pin = view.annotation as? MKPointAnnotation else { return }
            let point = GeoPoint(lat: pin.coordinate.latitude, lon: pin.coordinate.longitude)
            if pin is EndAnnotation { setEnd(at: point) } else if pin is StartAnnotation { setStart(at: point) }
        }

        /// Planning mode: long-press the map to start or end the route there (a small menu at the
        /// finger: "Start Here", "End Here").
        @objc func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began, parent.plan.isPlanning, !parent.plan.isWorking,
                  let map = recognizer.view as? MKMapView else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            showPlaceMenu(at: recognizer.location(in: map), on: map)
        }

        func showPlaceMenu(at location: CGPoint, on map: MKMapView) {
            let c = map.convert(location, toCoordinateFrom: map)
            pressedPoint = GeoPoint(lat: c.latitude, lon: c.longitude)
            placeMenu.presentEditMenu(with: UIEditMenuConfiguration(identifier: nil, sourcePoint: location))
        }

        func editMenuInteraction(_ interaction: UIEditMenuInteraction, menuFor configuration: UIEditMenuConfiguration,
                                 suggestedActions: [UIMenuElement]) -> UIMenu? {
            guard let point = pressedPoint else { return nil }
            return UIMenu(children: [
                UIAction(title: String(localized: "Start Here"), image: UIImage(systemName: "flag.fill")) { [weak self] _ in
                    self?.setStart(at: point)
                },
                UIAction(title: String(localized: "End Here"), image: UIImage(systemName: "flag.checkered")) { [weak self] _ in
                    self?.setEnd(at: point)
                },
            ])
        }

        private func setStart(at point: GeoPoint) {
            let plan = parent.plan
            // Show the pin right away; the place name follows.
            plan.setStart(StartPoint(name: StartPoint.coordinateName(point), point), remember: false)
            Task {
                let named = await StartPoint.dropped(at: point)
                if plan.start?.point == point { plan.setStart(named) }
            }
        }

        private func setEnd(at point: GeoPoint) {
            let plan = parent.plan
            plan.setEnd(StartPoint(name: StartPoint.coordinateName(point), point), remember: false)
            Task {
                let named = await StartPoint.dropped(at: point)
                if plan.end?.point == point { plan.setEnd(named) }
            }
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let map = recognizer.view as? MKMapView else { return }
            // Taps on stop markers show their callout instead.
            if map.selectedAnnotations.contains(where: { !($0 is MKUserLocation) }) { return }
            let c = map.convert(recognizer.location(in: map), toCoordinateFrom: map)
            let p = GeoPoint(lat: c.latitude, lon: c.longitude)
            let store = parent.store

            if parent.plan.isPlanning {
                // Toggle unvisited items for route planning.
                switch parent.mode {
                case .squares:
                    let zoom = parent.tileZoom
                    if let key = TileGrid.key(lat: p.lat, lon: p.lon, zoom: zoom), !store.tiles(zoom).contains(key) {
                        parent.plan.toggle(.tile(zoom, key))
                    }
                case .gemeenten:
                    if let a = store.municipalityAreas?.area(at: p), !store.visitedMunicipalities.contains(a.code) {
                        parent.plan.toggle(.municipality(a.code))
                    }
                case .postcodes:
                    if let a = store.postcodeAreas?.area(at: p), !store.visitedPostcodes.contains(a.code) {
                        parent.plan.toggle(.postcode(a.code))
                    }
                case .climbs:
                    if let climb = nearestClimb(to: p, on: map) { parent.plan.toggle(.climb(climb.id)) }
                case .trappists:
                    if let t = nearestPlace(parent.store.trappists, to: p, on: map) { parent.plan.toggle(.trappist(t.id)) }
                case .boscafes:
                    if let b = nearestPlace(parent.store.boscafes, to: p, on: map) { parent.plan.toggle(.boscafe(b.id)) }
                case .klompenpaden, .mtb, .ferries:
                    break // routes and crossings to ride themselves, not planning targets
                }
                return
            }

            if parent.mode == .klompenpaden {
                parent.selectedKlompenpad = nearestRoute(parent.store.klompenpaden, to: p, on: map)
                return
            }
            if parent.mode == .mtb {
                parent.selectedMTBRoute = nearestRoute(parent.store.mtbRoutes, to: p, on: map)
                return
            }

            if parent.mode == .trappists {
                parent.selectedTrappist = nearestPlace(parent.store.trappists, to: p, on: map)
                return
            }
            if parent.mode == .boscafes {
                parent.selectedBoscafe = nearestPlace(parent.store.boscafes, to: p, on: map)
                return
            }
            if parent.mode == .ferries {
                parent.selectedFerry = nearestPlace(parent.store.ferries, to: p, on: map)
                return
            }

            if parent.mode == .climbs {
                parent.selectedClimb = nearestClimb(to: p, on: map)
                return
            }
            guard let (areas, _) = parent.mode.areas(in: store) else { return }
            parent.selectedArea = areas.area(at: p)
        }

        /// The route (Klompenpad, MTB route) drawn closest to a tap, within about 25 points on screen.
        private func nearestRoute<Route: ChallengeRoute>(_ routes: [Route], to p: GeoPoint, on map: MKMapView) -> Route? {
            let metresPerPoint = map.visibleMapRect.width / max(map.bounds.width, 1) * MKMetersPerMapPointAtLatitude(p.lat)
            let limit = 25 * metresPerPoint
            let dLat = limit / 111_000, dLon = dLat / max(cos(p.lat * .pi / 180), 0.2)
            var best: (Route, Double)?
            for path in routes {
                for piece in path.pieces {
                    // Skip pieces far from the tap without measuring every segment.
                    guard piece.contains(where: { abs($0.lat - p.lat) < dLat * 40 && abs($0.lon - p.lon) < dLon * 40 }) else { continue }
                    for (a, b) in zip(piece, piece.dropFirst()) {
                        let d = TrappistMatcher.distance(from: p, toSegment: a, b)
                        if d <= limit, d < best?.1 ?? .infinity { best = (path, d) }
                    }
                }
            }
            return best?.0
        }

        /// The brewery or boscafé closest to a tap, within its badge (about 25 points on screen).
        private func nearestPlace<Place: ChallengePlace>(_ places: [Place], to p: GeoPoint, on map: MKMapView) -> Place? {
            let metresPerPoint = map.visibleMapRect.width / max(map.bounds.width, 1) * MKMetersPerMapPointAtLatitude(p.lat)
            return places.map { ($0, Geo.distance($0.point, p)) }
                .filter { $0.1 <= 25 * metresPerPoint }
                .min { $0.1 < $1.1 }?.0
        }

        /// The climb drawn closest to a tap, within about 25 points on screen.
        private func nearestClimb(to p: GeoPoint, on map: MKMapView) -> Climb? {
            let metresPerPoint = map.visibleMapRect.width / max(map.bounds.width, 1) * MKMetersPerMapPointAtLatitude(p.lat)
            let limit = 25 * metresPerPoint
            var best: (Climb, Double)?
            for climb in parent.store.climbs.values {
                let points = climb.points
                guard let near = points.map({ Geo.distance($0, p) }).min(), near <= limit, near < best?.1 ?? .infinity else { continue }
                best = (climb, near)
            }
            return best?.0
        }
    }
}
