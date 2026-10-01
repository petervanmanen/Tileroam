import Foundation

/// Something the user wants to visit on a planned ride.
enum PlanTarget: Hashable, Sendable {
    case tile(TileZoom, Int64)
    /// Country-prefixed codes, e.g. "NL:GM0344", "DE:10115".
    case municipality(String)
    case postcode(String)

    var sortKey: String {
        switch self {
        case .tile(let z, let k): "0\(z.rawValue)-\(k)"
        case .municipality(let c): "1\(c)"
        case .postcode(let c): "2\(c)"
        }
    }
}

/// Geometry of a target: containment test and candidate points to route through.
struct TargetGeometry: Sendable {
    let target: PlanTarget
    let name: String
    /// Set for municipalities and postcodes.
    let area: Area?

    init?(_ target: PlanTarget, regions: RegionData?) {
        self.target = target
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
        }
    }

    func contains(_ p: GeoPoint) -> Bool {
        switch target {
        case .tile(let zoom, let key): TileGrid.key(lat: p.lat, lon: p.lon, zoom: zoom) == key
        default: area?.contains(p) ?? false
        }
    }

    /// Points spread over the inside of the target. The route passes through one of them.
    func candidates() -> [GeoPoint] {
        switch target {
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
