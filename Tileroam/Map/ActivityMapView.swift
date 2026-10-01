import CoreLocation
import MapKit
import SwiftUI

enum MapMode: String, CaseIterable, Identifiable {
    case squares, activities, gemeenten, postcodes

    var id: Self { self }

    var title: String {
        switch self {
        case .squares: String(localized: "Tiles")
        case .activities: String(localized: "Routes")
        case .gemeenten: String(localized: "Municipalities", comment: "Map mode: municipalities (gemeenten, communes, Gemeinden…)")
        case .postcodes: String(localized: "Postcodes")
        }
    }

    /// Short name for the segmented control at the top of the map.
    var tabTitle: String {
        switch self {
        case .squares: String(localized: "tab.tiles", defaultValue: "Tiles")
        case .activities: String(localized: "tab.routes", defaultValue: "Routes")
        case .gemeenten: String(localized: "tab.municipalities", defaultValue: "Towns")
        case .postcodes: String(localized: "tab.postcodes", defaultValue: "Postcodes")
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

struct ActivityMapView: UIViewRepresentable {
    let mode: MapMode
    /// Tile zoom level shown (both are always calculated).
    let tileZoom: TileZoom
    let store: ActivityStore
    /// Passed explicitly so SwiftUI updates the view when the data changes.
    let version: Int
    @Binding var selectedArea: Area?
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
        map.preferredConfiguration = MKStandardMapConfiguration(emphasisStyle: .muted)
        map.pointOfInterestFilter = .excludingAll
        map.region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 52.2, longitude: 5.3),
                                        span: MKCoordinateSpan(latitudeDelta: 3.4, longitudeDelta: 3.4))
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        map.addGestureRecognizer(tap)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        // Keeps the Apple Maps legal label and compass clear of the side panel.
        if map.layoutMargins.left != leadingInset {
            map.layoutMargins = UIEdgeInsets(top: 0, left: leadingInset, bottom: 0, right: 0)
        }
        context.coordinator.parent = self
        context.coordinator.update(map)
        context.coordinator.handleLocateRequest(map)
    }

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate, CLLocationManagerDelegate {
        var parent: ActivityMapView
        private let locationManager = CLLocationManager()
        private var handledLocateRequest = 0
        private weak var mapView: MKMapView?
        private var centerWhenAuthorized = false
        private var appliedMode: MapMode?
        private var appliedVersion = -1
        private var appliedPlanVersion = -1
        private var appliedTileZoom: TileZoom?
        private var zoomedRouteID: UUID?
        private var hasFocused = false
        /// Focused on Apple Park for lack of data; refocus once data arrives.
        private var focusedOnFallback = false

        private var trackColors: [ObjectIdentifier: UIColor] = [:]
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

        func mapView(_ mapView: MKMapView, didChange mode: MKUserTrackingMode, animated: Bool) {
            parent.isFollowingUser = mode != .none
        }

        func update(_ map: MKMapView) {
            guard appliedMode != parent.mode || appliedVersion != parent.version || appliedPlanVersion != parent.planVersion
                || appliedTileZoom != parent.tileZoom else { return }
            appliedTileZoom = parent.tileZoom
            appliedMode = parent.mode
            appliedVersion = parent.version
            appliedPlanVersion = parent.planVersion

            map.removeOverlays(map.overlays)
            map.removeAnnotations(map.annotations.filter { !($0 is MKUserLocation) })
            trackColors = [:]
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
            case .activities:
                for (sport, activities) in Dictionary(grouping: store.activities, by: \.sport) {
                    let lines = activities.map { a in
                        let coords = a.coordinates
                        return MKPolyline(coordinates: coords, count: coords.count)
                    }
                    let multi = MKMultiPolyline(lines)
                    trackColors[ObjectIdentifier(multi)] = Self.color(for: sport)
                    map.addOverlay(multi, level: .aboveRoads)
                }
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
            case .activities:
                center = MapFocus.densestCenter(store.activities.flatMap { a in
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

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard !(annotation is MKUserLocation) else { return nil }
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

        static func color(for sport: String) -> UIColor {
            switch sport {
            case "Cycling", "E-biking": .systemBlue
            case "Running": .systemRed
            case "Walking", "Hiking": .systemGreen
            default: .systemPurple
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
            case let lines as MKMultiPolyline:
                let r = MKMultiPolylineRenderer(multiPolyline: lines)
                r.strokeColor = (trackColors[ObjectIdentifier(lines)] ?? .systemPurple).withAlphaComponent(0.6)
                r.lineWidth = 2
                return r
            case let areas as AreaOverlay:
                return AreaRenderer(overlay: areas)
            default:
                return MKOverlayRenderer(overlay: overlay)
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
                case .activities:
                    break
                }
                return
            }

            guard let (areas, _) = parent.mode.areas(in: store) else { return }
            parent.selectedArea = areas.area(at: p)
        }
    }
}
