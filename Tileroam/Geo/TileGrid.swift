import Foundation

/// Web Mercator map tiles ("slippy map" tiles), as used by OpenStreetMap, Apple and Google.
///
/// - Zoom 14: explorer tiles (VeloViewer, StatsHunters, rideeverytile.com), ~1.5 km in the Netherlands.
///
/// Tile width = 40,075 km × cos(latitude) / 2^zoom.
enum TileZoom: Int, CaseIterable, Identifiable, Sendable, Codable {
    case explorer = 14
    // Zoom 17 "squadratinhos" were removed in 1.5.9; a stored 17 no longer decodes (zoom 14).

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .explorer: String(localized: "Tiles (14)")
        }
    }

    /// "812 tiles", localized with plural rules.
    func countLabel(_ count: Int) -> String {
        switch self {
        case .explorer: String(localized: "\(count) tiles")
        }
    }

    var shortTitle: String {
        switch self {
        case .explorer: String(localized: "Zoom 14")
        }
    }

    /// Spacing (meters) between points when testing which tiles a track passes.
    var trackSpacing: Double {
        switch self {
        case .explorer: 100
        }
    }
}

enum TileGrid {
    static func tilesPerSide(_ zoom: TileZoom) -> Double { Double(1 << zoom.rawValue) }

    static func key(x: Int, y: Int) -> Int64 {
        Int64(x) << 32 | Int64(UInt32(truncatingIfNeeded: y))
    }

    static func cell(of key: Int64) -> (x: Int, y: Int) {
        (Int(key >> 32), Int(Int32(truncatingIfNeeded: key)))
    }

    /// Tile containing a coordinate (Web Mercator latitude limit ±85.05°).
    static func cell(lat: Double, lon: Double, zoom: TileZoom) -> (x: Int, y: Int)? {
        guard abs(lat) < 85.0511, (-180...180).contains(lon) else { return nil }
        let n = tilesPerSide(zoom)
        let φ = lat * .pi / 180
        let x = Int(((lon + 180) / 360 * n).rounded(.down))
        let y = Int(((1 - log(tan(φ) + 1 / cos(φ)) / .pi) / 2 * n).rounded(.down))
        let max = Int(n) - 1
        return (Swift.min(Swift.max(x, 0), max), Swift.min(Swift.max(y, 0), max))
    }

    static func key(lat: Double, lon: Double, zoom: TileZoom) -> Int64? {
        cell(lat: lat, lon: lon, zoom: zoom).map { key(x: $0.x, y: $0.y) }
    }

    /// North-west corner of tile (x, y); (x + 1, y + 1) gives the south-east corner.
    static func corner(x: Int, y: Int, zoom: TileZoom) -> GeoPoint {
        let n = tilesPerSide(zoom)
        let lon = Double(x) / n * 360 - 180
        let lat = atan(sinh(.pi * (1 - 2 * Double(y) / n))) * 180 / .pi
        return GeoPoint(lat: lat, lon: lon)
    }

    /// Coordinate of a fractional tile position (e.g. x + 0.5 for the tile center).
    static func coordinate(x: Double, y: Double, zoom: TileZoom) -> GeoPoint {
        let n = tilesPerSide(zoom)
        return GeoPoint(lat: atan(sinh(.pi * (1 - 2 * y / n))) * 180 / .pi, lon: x / n * 360 - 180)
    }

    /// Tiles touched by a track.
    static func tiles(for points: [GeoPoint], zoom: TileZoom) -> Set<Int64> {
        var result = Set<Int64>()
        for p in Geo.densified(points, spacing: zoom.trackSpacing) {
            if let k = key(lat: p.lat, lon: p.lon, zoom: zoom) { result.insert(k) }
        }
        return result
    }
}

struct SquareStats: Sendable, Equatable {
    var count = 0
    /// Side length of the largest fully visited square block.
    var maxSquare = 0
    /// Top-left tile of the max square.
    var maxSquareOrigin: (x: Int, y: Int)?
    /// Size of the largest connected group of tiles whose 4 neighbours are all visited.
    var maxCluster = 0
    /// Average tile position (x, y) of the max cluster; tile centers are at +0.5.
    var maxClusterCenter: (x: Double, y: Double)?

    static func == (a: SquareStats, b: SquareStats) -> Bool {
        a.count == b.count && a.maxSquare == b.maxSquare && a.maxCluster == b.maxCluster
            && a.maxSquareOrigin?.x == b.maxSquareOrigin?.x && a.maxSquareOrigin?.y == b.maxSquareOrigin?.y
    }

    init() {}

    /// Works on the visited tiles only, so memory stays small even for zoom 17 tiles spread over Europe.
    init(visited: Set<Int64>) {
        count = visited.count
        guard !visited.isEmpty else { return }
        let cells = visited.map(TileGrid.cell(of:)).sorted { $0.y != $1.y ? $0.y < $1.y : $0.x < $1.x }

        // Largest square: dp = side of the largest square whose bottom-right tile is (x, y).
        var dp = [Int64: Int](minimumCapacity: cells.count)
        for c in cells {
            let up = dp[TileGrid.key(x: c.x, y: c.y - 1)] ?? 0
            let left = dp[TileGrid.key(x: c.x - 1, y: c.y)] ?? 0
            let diagonal = dp[TileGrid.key(x: c.x - 1, y: c.y - 1)] ?? 0
            let v = 1 + min(up, left, diagonal)
            dp[TileGrid.key(x: c.x, y: c.y)] = v
            if v > maxSquare {
                maxSquare = v
                maxSquareOrigin = (c.x - v + 1, c.y - v + 1)
            }
        }

        // Cluster: tiles with all four neighbours visited, largest 4-connected component.
        func has(_ x: Int, _ y: Int) -> Bool { visited.contains(TileGrid.key(x: x, y: y)) }
        var clusterCells = Set<Int64>()
        for c in cells where has(c.x + 1, c.y) && has(c.x - 1, c.y) && has(c.x, c.y + 1) && has(c.x, c.y - 1) {
            clusterCells.insert(TileGrid.key(x: c.x, y: c.y))
        }
        var seen = Set<Int64>()
        for start in clusterCells where !seen.contains(start) {
            var stack = [start]
            seen.insert(start)
            var size = 0
            var sumX = 0.0, sumY = 0.0
            while let k = stack.popLast() {
                size += 1
                let (x, y) = TileGrid.cell(of: k)
                sumX += Double(x)
                sumY += Double(y)
                for (nx, ny) in [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)] {
                    let nk = TileGrid.key(x: nx, y: ny)
                    if clusterCells.contains(nk), seen.insert(nk).inserted { stack.append(nk) }
                }
            }
            if size > maxCluster {
                maxCluster = size
                maxClusterCenter = (sumX / Double(size) + 0.5, sumY / Double(size) + 0.5)
            }
        }
    }
}
