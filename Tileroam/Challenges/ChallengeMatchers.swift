import Foundation

/// Matches tracks to the places of a location challenge: visited by passing within the
/// challenge's radius.
enum PlaceMatcher {
    /// The places a track passes within `radius` of: measured to the track's segments, so a
    /// sparse track (a Strava summary line) counts too.
    static func visited(by track: [GeoPoint], among places: [ChallengeItem], radius: Double) -> [String] {
        guard let first = track.first else { return [] }
        let box = Geo.box(track)
        let dLat = radius / 111_000
        return places.filter { place in
            let p = place.point
            let dLon = dLat / max(cos(p.lat * .pi / 180), 0.2)
            guard p.lat >= box.minLat - dLat, p.lat <= box.maxLat + dLat,
                  p.lon >= box.minLon - dLon, p.lon <= box.maxLon + dLon else { return false }
            if track.count == 1 { return Geo.distance(first, p) <= radius }
            return zip(track, track.dropFirst()).contains { a, b in distance(from: p, toSegment: a, b) <= radius }
        }.map(\.id)
    }

    /// Metres from `p` to the segment a–b, in a local flat approximation (fine over a few km).
    static func distance(from p: GeoPoint, toSegment a: GeoPoint, _ b: GeoPoint) -> Double {
        let k = cos(p.lat * .pi / 180) * 111_320, m = 110_574.0
        let ax = (a.lon - p.lon) * k, ay = (a.lat - p.lat) * m
        let bx = (b.lon - p.lon) * k, by = (b.lat - p.lat) * m
        let dx = bx - ax, dy = by - ay
        let len2 = dx * dx + dy * dy
        let t = len2 > 0 ? max(0, min(1, -(ax * dx + ay * dy) / len2)) : 0
        return hypot(ax + t * dx, ay + t * dy)
    }
}

/// Recognises crossings in tracks: the routes of a challenge with `complete: "cross"` (ferries).
enum CrossingMatcher {
    /// Metres between the track and an end, and the crossing's middle: a third of the crossing,
    /// 15–80 m (a 30 m pontje over a ditch would otherwise count for riding along the bank).
    static func tolerance(_ crossing: ChallengeItem) -> Double { min(80, max(15, crossing.length / 3)) }

    /// The crossings a track made: it came near both ends and near the middle (so riding past an
    /// end, or along the bank, doesn't count). Measured to the track's segments, so the straight
    /// line of a GPS that lost signal on the water counts too.
    static func crossed(by track: [GeoPoint], among crossings: [ChallengeItem]) -> [String] {
        guard track.count >= 2 else { return [] }
        let box = Geo.box(track)
        return crossings.filter { crossing in
            let tolerance = tolerance(crossing), dLat = tolerance / 111_000
            let dLon = dLat / max(cos(crossing.point.lat * .pi / 180), 0.2)
            func near(_ p: GeoPoint) -> Bool {
                guard p.lat >= box.minLat - dLat, p.lat <= box.maxLat + dLat,
                      p.lon >= box.minLon - dLon, p.lon <= box.maxLon + dLon else { return false }
                return zip(track, track.dropFirst()).contains { a, b in PlaceMatcher.distance(from: p, toSegment: a, b) <= tolerance }
            }
            // The middle first: most crossings end there.
            guard near(crossing.point), let line = crossing.pieces.first, let a = line.first, let b = line.last else { return false }
            return near(a) && near(b)
        }.map(\.id)
    }
}

/// How much of each route the user has covered: the share of points along it (one every
/// `spacing` metres) that any activity passed within `tolerance`, over all activities together.
/// For challenges with `complete: "cover"` (Klompenpaden, MTB routes).
enum RouteMatcher {
    static let tolerance = 30.0

    static func checkpoints(_ route: ChallengeItem, spacing: Double) -> [GeoPoint] {
        route.pieces.flatMap { Geo.densified($0, spacing: spacing, maxGap: .infinity) }
    }

    /// The routes' checkpoints and boxes, made once per challenge.
    struct Prepared: Sendable {
        struct Path: Sendable {
            let id: String
            let points: [GeoPoint]
            let minLat, maxLat, minLon, maxLon: Double
        }
        let paths: [Path]

        init(_ routes: [ChallengeItem], spacing: Double) {
            let m = RouteMatcher.tolerance / 111_000 * 2
            paths = routes.map { r in
                let points = RouteMatcher.checkpoints(r, spacing: spacing)
                let lats = points.map(\.lat), lons = points.map(\.lon)
                return Path(id: r.id, points: points, minLat: (lats.min() ?? 0) - m, maxLat: (lats.max() ?? 0) + m,
                            minLon: (lons.min() ?? 0) - m * 1.6, maxLon: (lons.max() ?? 0) + m * 1.6)
            }
        }

        /// Checkpoints per route.
        var counts: [String: Int] { Dictionary(paths.map { ($0.id, $0.points.count) }, uniquingKeysWith: { a, _ in a }) }
    }

    /// For one track: per route it comes near, the indexes of the checkpoints it passes within
    /// `tolerance`.
    static func hits(_ track: [GeoPoint], paths: Prepared) -> [String: [Int]] {
        guard !track.isEmpty else { return [:] }
        let box = Geo.box(track)
        var grid: ClimbMatcher.TrackGrid?
        var result = [String: [Int]]()
        for path in paths.paths where path.minLat <= box.maxLat && path.maxLat >= box.minLat
            && path.minLon <= box.maxLon && path.maxLon >= box.minLon {
            if grid == nil { grid = ClimbMatcher.TrackGrid(track) }
            let hit = path.points.indices.filter { grid!.nearest(to: path.points[$0], within: tolerance) != nil }
            if !hit.isEmpty { result[path.id] = hit }
        }
        return result
    }

    /// For each route with any progress, the share covered (0…1), from the activities' hits
    /// together (several rides add up).
    static func progress(hits: [[String: [Int]]], counts: [String: Int]) -> [String: Double] {
        var union = [String: Set<Int>]()
        for h in hits { for (id, indexes) in h { union[id, default: []].formUnion(indexes) } }
        var result = [String: Double]()
        for (id, passed) in union {
            guard let total = counts[id], total > 0 else { continue } // a route no longer in the file
            result[id] = min(1, Double(passed.count) / Double(total))
        }
        return result
    }
}

extension Geo {
    /// The bounding box of a non-empty track.
    static func box(_ track: [GeoPoint]) -> (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double) {
        var box = (minLat: track[0].lat, maxLat: track[0].lat, minLon: track[0].lon, maxLon: track[0].lon)
        for p in track {
            box = (min(box.minLat, p.lat), max(box.maxLat, p.lat), min(box.minLon, p.lon), max(box.maxLon, p.lon))
        }
        return box
    }
}
