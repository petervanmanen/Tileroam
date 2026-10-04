import Foundation
import UIKit

/// A Trappist brewery of the Trappist Challenge (`Resources/trappists.json`, icons
/// `Resources/Trappists/trappist-<id>.png`). An activity visits it by passing within
/// `TrappistMatcher.radius` of it.
struct Trappist: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let name: String
    let abbey: String
    let place: String
    /// ISO country code.
    let country: String
    let lat: Double
    let lon: Double

    var point: GeoPoint { GeoPoint(lat: lat, lon: lon) }
    /// The brewery's logo, black on white.
    var icon: UIImage? { UIImage(named: "trappist-\(id)") }

    static let all: [Trappist] = {
        guard let url = Bundle.main.url(forResource: "trappists", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Trappist].self, from: data)) ?? []
    }()
}

enum TrappistMatcher {
    /// Metres between a brewery and the track.
    static let radius = 200.0

    /// The breweries a track passes within `radius` of: measured to the track's segments, so a
    /// sparse track (a Strava summary line) counts too.
    static func visited(by track: [GeoPoint], among trappists: [Trappist]) -> [String] {
        guard let first = track.first else { return [] }
        var box = (minLat: first.lat, maxLat: first.lat, minLon: first.lon, maxLon: first.lon)
        for p in track {
            box = (min(box.minLat, p.lat), max(box.maxLat, p.lat), min(box.minLon, p.lon), max(box.maxLon, p.lon))
        }
        let dLat = radius / 111_000
        return trappists.filter { t in
            let dLon = dLat / max(cos(t.lat * .pi / 180), 0.2)
            guard t.lat >= box.minLat - dLat, t.lat <= box.maxLat + dLat,
                  t.lon >= box.minLon - dLon, t.lon <= box.maxLon + dLon else { return false }
            if track.count == 1 { return Geo.distance(first, t.point) <= radius }
            return zip(track, track.dropFirst()).contains { a, b in distance(from: t.point, toSegment: a, b) <= radius }
        }.map(\.id)
    }

    /// For each brewery, the start dates of the activities that visited it, newest first.
    static func visits(_ activities: [Activity], among trappists: [Trappist]) -> [String: [Date]] {
        var result = [String: [Date]]()
        for a in activities where a.isOnMap {
            let track = a.coordinates.map { GeoPoint(lat: $0.latitude, lon: $0.longitude) }
            for id in visited(by: track, among: trappists) {
                result[id, default: []].append(a.startDate ?? .distantPast)
            }
        }
        return result.mapValues { $0.sorted(by: >) }
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
