import Foundation

struct Area: Sendable, Identifiable {
    struct Polygon: Sendable {
        /// First ring is the outer boundary, following rings are holes. Points are (lat, lon).
        var rings: [[GeoPoint]]
    }

    var id: String { code }
    /// Country-prefixed, e.g. "NL:GM0344" or "DE:10115".
    let code: String
    let name: String
    let polygons: [Polygon]
    let minLat, maxLat, minLon, maxLon: Double

    var country: String { String(code.prefix { $0 != ":" }) }

    /// The code without country prefix ("GM0344", "10115").
    var localCode: String { code.firstIndex(of: ":").map { String(code[code.index(after: $0)...]) } ?? code }

    /// Label for postcodes: the code, plus the place name when the data has one.
    var postcodeLabel: String { name == localCode ? localCode : "\(localCode) \(name)" }

    func contains(_ p: GeoPoint) -> Bool {
        guard p.lat >= minLat, p.lat <= maxLat, p.lon >= minLon, p.lon <= maxLon else { return false }
        for polygon in polygons {
            guard let outer = polygon.rings.first, Self.ringContains(outer, p) else { continue }
            if !polygon.rings.dropFirst().contains(where: { Self.ringContains($0, p) }) { return true }
        }
        return false
    }

    private static func ringContains(_ ring: [GeoPoint], _ p: GeoPoint) -> Bool {
        var inside = false
        var j = ring.count - 1
        for i in 0..<ring.count {
            let a = ring[i], b = ring[j]
            if (a.lat > p.lat) != (b.lat > p.lat),
               p.lon < (b.lon - a.lon) * (p.lat - a.lat) / (b.lat - a.lat) + a.lon {
                inside.toggle()
            }
            j = i
        }
        return inside
    }
}

/// A set of areas (municipalities or postcodes) with a spatial index.
struct AreaSet: Sendable {
    let all: [Area]
    /// Grid cell -> indices of areas whose bounding box touches the cell.
    private let grid: [Int: [Int]]
    private let byCode: [String: Int]
    private static let cellSize = 0.05

    init(areas: [Area]) {
        all = areas
        byCode = Dictionary(areas.enumerated().map { ($1.code, $0) }, uniquingKeysWith: { a, _ in a })
        var grid = [Int: [Int]]()
        for (i, a) in areas.enumerated() where a.minLat <= a.maxLat {
            for x in Self.cell(a.minLon)...Self.cell(a.maxLon) {
                for y in Self.cell(a.minLat)...Self.cell(a.maxLat) { grid[Self.key(x, y), default: []].append(i) }
            }
        }
        self.grid = grid
    }

    /// Number of areas per country code ("NL", "DE", …).
    func countByCountry() -> [String: Int] {
        Dictionary(grouping: all, by: \.country).mapValues(\.count)
    }

    private static func cell(_ v: Double) -> Int { Int((v / cellSize).rounded(.down)) }
    private static func key(_ x: Int, _ y: Int) -> Int { x &* 100_000 &+ y }

    func area(code: String) -> Area? {
        byCode[code].map { all[$0] }
    }

    func area(at p: GeoPoint) -> Area? {
        guard let candidates = grid[Self.key(Self.cell(p.lon), Self.cell(p.lat))] else { return nil }
        for i in candidates where all[i].contains(p) { return all[i] }
        return nil
    }

    /// Codes of all areas touched by the (densified) track.
    func visited(by points: [GeoPoint]) -> Set<String> {
        var result = Set<String>()
        var last: Area?
        for p in points {
            if let last, last.contains(p) { continue }
            if let m = area(at: p) {
                result.insert(m.code)
                last = m
            }
        }
        return result
    }
}
