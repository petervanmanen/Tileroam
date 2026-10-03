import Foundation

/// A climb on the road network, found from elevation data by Tools/build_climbs.py (see
/// docs/CLIMBS.md): from `start` (the bottom) along `line` to `end` (the top).
struct Climb: Codable, Sendable, Identifiable, Hashable {
    enum Category: String, Codable, Sendable, CaseIterable, Comparable {
        case hill, cat4 = "4", cat3 = "3", cat2 = "2", cat1 = "1", hc = "HC"

        /// "HC", "Cat 1" … "Cat 4", "Hill".
        var title: String {
            switch self {
            case .hc: "HC"
            case .cat1: String(localized: "Cat 1")
            case .cat2: String(localized: "Cat 2")
            case .cat3: String(localized: "Cat 3")
            case .cat4: String(localized: "Cat 4")
            case .hill: String(localized: "Hill")
            }
        }

        private var rank: Int { Self.allCases.firstIndex(of: self)! }
        static func < (a: Self, b: Self) -> Bool { a.rank < b.rank }
    }

    let id: String
    /// The road's name or number; nil for unnamed roads.
    let name: String?
    /// The nearest town or village at the top.
    let place: String?
    let cat: Category
    /// Metres.
    let length: Double
    let gain: Double
    /// Percent.
    let avg: Double
    let max: Double
    /// Metres above sea level at the top.
    let top: Double
    let start: [Double]
    let end: [Double]
    /// Encoded polyline (precision 5), bottom to top.
    let line: String

    /// "Cauberg", or "Climb near Valkenburg" for an unnamed road.
    var title: String {
        if let name { return name }
        if let place { return String(localized: "Climb near \(place)") }
        return String(localized: "Climb")
    }

    var bottom: GeoPoint { GeoPoint(lat: start[0], lon: start[1]) }
    var summit: GeoPoint { GeoPoint(lat: end[0], lon: end[1]) }
    var points: [GeoPoint] { StravaImport.decodePolyline(line) }

    /// "2.4 km · 6.1% · 146 m"
    var details: String {
        let km = Measurement(value: length / 1000, unit: UnitLength.kilometers)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(1))))
        let percent = (avg / 100).formatted(.percent.precision(.fractionLength(1)))
        let metres = Measurement(value: gain, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0))))
        return "\(km) · \(percent) · \(metres)"
    }
}

/// Recognises climbs in tracks: a track climbed a climb when it passes close to nearly all of
/// the climb's line, reaching the bottom before the top.
enum ClimbMatcher {
    /// Metres between a climb point and the nearest track point.
    static let tolerance = 30.0
    /// Share of the climb's points the track must pass.
    static let coverage = 0.9

    /// Points along the climb about every 50 m, bottom first.
    static func checkpoints(_ climb: Climb) -> [GeoPoint] {
        let points = climb.points
        guard points.count >= 2 else { return points }
        var out = [points[0]]
        var since = 0.0
        for (a, b) in zip(points, points.dropFirst()) {
            since += Geo.distance(a, b)
            if since >= 50 { out.append(b); since = 0 }
        }
        if out.last != points.last { out.append(points.last!) }
        return out
    }

    /// Whether `track` climbed `climb` (uphill, bottom to top).
    static func climbed(_ climb: Climb, by track: [GeoPoint]) -> Bool {
        climbed(checkpoints(climb), by: track)
    }

    static func climbed(_ checkpoints: [GeoPoint], by track: [GeoPoint]) -> Bool {
        guard checkpoints.count >= 2, track.count >= 2 else { return false }
        // Index of the nearest track point to each checkpoint, within the tolerance.
        let grid = TrackGrid(track)
        var hits = 0
        var bottomIndex: Int?, topIndex: Int?
        for (i, p) in checkpoints.enumerated() {
            guard let index = grid.nearest(to: p, within: tolerance) else { continue }
            hits += 1
            if i == 0 { bottomIndex = index }
            if i == checkpoints.count - 1 { topIndex = index }
        }
        guard Double(hits) >= coverage * Double(checkpoints.count) else { return false }
        // Uphill: the bottom is passed before the top (when both are matched).
        if let bottomIndex, let topIndex { return bottomIndex < topIndex }
        return true
    }

    /// Track points in ~50 m cells, for fast nearest-point lookups.
    private struct TrackGrid {
        let points: [GeoPoint]
        var cells: [Int64: [Int]] = [:]
        static let cell = 0.0005 // degrees, about 55 m of latitude

        init(_ track: [GeoPoint]) {
            // Densify long gaps, so a straight stretch between two far-apart points still matches.
            var dense = [GeoPoint]()
            for (a, b) in zip(track, track.dropFirst()) {
                let steps = Swift.max(1, Int(Geo.distance(a, b) / 20))
                for k in 0..<steps {
                    let f = Double(k) / Double(steps)
                    dense.append(GeoPoint(lat: a.lat + (b.lat - a.lat) * f, lon: a.lon + (b.lon - a.lon) * f))
                }
            }
            dense.append(track.last!)
            points = dense
            for (i, p) in dense.enumerated() { cells[Self.key(p), default: []].append(i) }
        }

        static func key(_ p: GeoPoint) -> Int64 {
            Int64((p.lat / cell).rounded(.down)) << 32 | Int64(UInt32(bitPattern: Int32((p.lon / cell).rounded(.down))))
        }

        func nearest(to p: GeoPoint, within limit: Double) -> Int? {
            let la = Int64((p.lat / Self.cell).rounded(.down)), lo = Int32((p.lon / Self.cell).rounded(.down))
            var best: (Int, Double)?
            for dy in -1...1 {
                for dx in -1...1 {
                    let key = (la + Int64(dy)) << 32 | Int64(UInt32(bitPattern: lo + Int32(dx)))
                    for i in cells[key] ?? [] {
                        let d = Geo.distance(points[i], p)
                        if d <= limit, d < best?.1 ?? .infinity { best = (i, d) }
                    }
                }
            }
            return best?.0
        }
    }
}

extension ClimbMatcher {
    /// For each activity, the climbs it rode uphill. Climbs are only checked against activities
    /// whose box they overlap.
    static func match(_ activities: [Activity], climbs: [Climb]) -> [String: [String]] {
        let prepared = climbs.map { climb -> (Climb, [GeoPoint], ClosedRange<Double>, ClosedRange<Double>) in
            let points = checkpoints(climb)
            let lats = points.map(\.lat), lons = points.map(\.lon)
            // With room for the matching tolerance: a climb running exactly north-south has a box
            // without width, and the track rides beside it.
            let m = 0.001 // about 70–110 m
            return (climb, points, ((lats.min() ?? 0) - m)...((lats.max() ?? 0) + m), ((lons.min() ?? 0) - m)...((lons.max() ?? 0) + m))
        }
        var result = [String: [String]]()
        for a in activities {
            let track = a.coordinates.map { GeoPoint(lat: $0.latitude, lon: $0.longitude) }
            guard let minLat = track.map(\.lat).min(), let maxLat = track.map(\.lat).max(),
                  let minLon = track.map(\.lon).min(), let maxLon = track.map(\.lon).max() else {
                result[a.id] = []
                continue
            }
            result[a.id] = prepared.compactMap { climb, points, lats, lons in
                guard lats.lowerBound <= maxLat, lats.upperBound >= minLat, lons.lowerBound <= maxLon, lons.upperBound >= minLon,
                      climbed(points, by: track) else { return nil }
                return climb.id
            }
        }
        return result
    }
}
