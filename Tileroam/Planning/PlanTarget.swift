import Foundation

/// Something the user wants to visit on a planned ride.
enum PlanTarget: Hashable, Sendable {
    case tile(TileZoom, Int64)
    /// Country-prefixed codes, e.g. "NL:GM0344", "DE:10115".
    case municipality(String)
    case postcode(String)
    /// `Climb.id`: ridden uphill, bottom to top.
    case climb(String)
    /// `Trappist.id`: passed within `TrappistMatcher.radius`.
    case trappist(String)

    var sortKey: String {
        switch self {
        case .tile(let z, let k): "0\(z.rawValue)-\(k)"
        case .municipality(let c): "1\(c)"
        case .postcode(let c): "2\(c)"
        case .climb(let id): "3\(id)"
        case .trappist(let id): "4\(id)"
        }
    }
}

/// Geometry of a target: containment test and candidate points to route through.
struct TargetGeometry: Sendable {
    let target: PlanTarget
    let name: String
    /// Set for municipalities and postcodes.
    let area: Area?
    /// Set for climbs.
    let climb: Climb?
    /// Set for Trappist breweries.
    let trappist: Trappist?

    init?(_ target: PlanTarget, regions: RegionData?, climbs: [String: Climb] = [:], trappists: [Trappist] = []) {
        self.target = target
        climb = if case .climb(let id) = target { climbs[id] } else { nil }
        trappist = if case .trappist(let id) = target { trappists.first { $0.id == id } } else { nil }
        switch target {
        case .tile(let zoom, let key):
            let c = TileGrid.cell(of: key)
            name = zoom == .explorer ? String(localized: "Tile \(c.x)/\(c.y)") : String(localized: "Squadratinho \(c.x)/\(c.y)")
            area = nil
        case .municipality(let code):
            guard let a = regions?.municipalities.area(code: code) else { return nil }
            name = a.name
            area = a
        case .postcode(let code):
            guard let a = regions?.postcodes.area(code: code) else { return nil }
            name = String(localized: "Postcode \(a.postcodeLabel)")
            area = a
        case .climb:
            guard let climb else { return nil }
            name = climb.title
            area = nil
        case .trappist:
            guard let trappist else { return nil }
            name = trappist.name
            area = nil
        }
    }

    /// For a climb: the points after its bottom that keep the route on the climb up to the top,
    /// at least every 400 m and at most four (Valhalla takes 60 points per route).
    var climbVia: [GeoPoint] {
        guard let climb else { return [] }
        let points = climb.points
        let spacing = max(400, climb.length / 4)
        var out = [GeoPoint](), since = 0.0
        for (a, b) in zip(points, points.dropFirst()) {
            since += Geo.distance(a, b)
            if since >= spacing, out.count < 3 { out.append(b); since = 0 }
        }
        if out.last != climb.summit { out.append(climb.summit) }
        return out
    }

    func contains(_ p: GeoPoint) -> Bool {
        switch target {
        case .tile(let zoom, let key): TileGrid.key(lat: p.lat, lon: p.lon, zoom: zoom) == key
        case .climb: climb.map { Geo.distance($0.bottom, p) < 60 } ?? false
        case .trappist: trappist.map { Geo.distance($0.point, p) <= TrappistMatcher.radius } ?? false
        default: area?.contains(p) ?? false
        }
    }

    /// Points spread over the inside of the target. The route passes through one of them.
    func candidates() -> [GeoPoint] {
        switch target {
        case .climb:
            return climb.map { [$0.bottom] } ?? []
        case .trappist:
            // The brewery, then a ring 120 m around it: abbeys often lie back from the road, and
            // the router snaps a point to the nearest road.
            guard let p = trappist?.point else { return [] }
            let dLat = 120 / 111_000.0, dLon = dLat / max(cos(p.lat * .pi / 180), 0.2)
            return [p] + (0..<8).map { k in
                let a = Double(k) * .pi / 4
                return GeoPoint(lat: p.lat + dLat * sin(a), lon: p.lon + dLon * cos(a))
            }
        case .tile(let zoom, let key):
            let c = TileGrid.cell(of: key)
            let nw = TileGrid.corner(x: c.x, y: c.y, zoom: zoom)
            let se = TileGrid.corner(x: c.x + 1, y: c.y + 1, zoom: zoom)
            // 6×6 grid, away from the edges so small snapping errors stay inside.
            return (0..<6).flatMap { i in
                (0..<6).map { j in
                    GeoPoint(lat: nw.lat + (se.lat - nw.lat) * (Double(i) + 0.5) / 6,
                             lon: nw.lon + (se.lon - nw.lon) * (Double(j) + 0.5) / 6)
                }
            }
        default:
            guard let area else { return [] }
            for n in [12, 24, 48] {
                var points = [GeoPoint]()
                for i in 0..<n {
                    for j in 0..<n {
                        let p = GeoPoint(lat: area.minLat + (area.maxLat - area.minLat) * (Double(i) + 0.5) / Double(n),
                                         lon: area.minLon + (area.maxLon - area.minLon) * (Double(j) + 0.5) / Double(n))
                        if area.contains(p) { points.append(p) }
                    }
                }
                if points.count >= 12 || n == 48 { return points }
            }
            return []
        }
    }
}
