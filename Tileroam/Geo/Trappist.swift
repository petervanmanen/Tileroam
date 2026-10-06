import Foundation
import UIKit

/// A Trappist brewery of the Trappist Challenge. The list and the logos are on Cloudflare R2
/// (`<server>/Trappist/`, see `TrappistData`). An activity visits a brewery by passing within
/// `TrappistMatcher.radius` of it.
struct Trappist: Codable, Sendable, Identifiable, Hashable, ChallengePlace {
    let id: String
    let name: String
    let abbey: String
    let place: String
    /// ISO country code.
    let country: String
    let lat: Double
    let lon: Double

    /// The brewery's logo, black on white, once downloaded.
    var icon: UIImage? { UIImage(contentsOfFile: TrappistData.iconFile(id).path(percentEncoded: false)) }
}

/// The Trappist Challenge's data on Cloudflare R2, uploaded with Tools/upload_trappists_r2.sh from
/// AssetPacks/Trappist: `Trappist/trappists.json` and a logo per brewery, `Trappist/<id>.png`.
/// The app keeps a copy in `Application Support/Trappist`, checks for a new list at most once a
/// day, and uses its copy when offline.
enum TrappistData {
    static var folder: URL { URL.applicationSupportDirectory.appending(path: "Trappist", directoryHint: .isDirectory) }
    static func iconFile(_ id: String, in folder: URL = folder) -> URL { folder.appending(path: "\(id).png") }
    private static let listName = "trappists.json"
    static var maxAge: TimeInterval { RemoteList.maxAge }

    /// The list on the device (empty before the first download).
    static func cached(in folder: URL = folder) -> [Trappist] {
        RemoteList.cached(Trappist.self, name: listName, in: folder)
    }

    /// The list (see `RemoteList`), plus the logos not on the device yet. Throws when there's no
    /// list at all (offline on first use).
    static func load(from server: URL = RoutingData.serverURL, session: URLSession = RoutingData.tileSession,
                     into folder: URL = folder, now: Date = .now) async throws -> [Trappist] {
        let list = try await RemoteList.load(Trappist.self, name: listName, remote: "Trappist", into: folder,
                                             from: server, session: session, now: now)
        for t in list where !FileManager.default.fileExists(atPath: iconFile(t.id, in: folder).path(percentEncoded: false)) {
            // A missing logo isn't fatal: the badge shows the brewery's initial until it arrives.
            if let png = try? await RemoteFile.get(server.appending(path: "Trappist/\(t.id).png"), session: session, isValid: {
                UIImage(data: $0) != nil
            }) {
                try? png.write(to: iconFile(t.id, in: folder), options: .atomic)
            }
        }
        return list
    }
}

/// A place to pass in a challenge (a Trappist brewery, a boscafé): visited by passing within
/// `TrappistMatcher.radius` of it.
protocol ChallengePlace: Sendable {
    var id: String { get }
    var name: String { get }
    var lat: Double { get }
    var lon: Double { get }
}

extension ChallengePlace {
    var point: GeoPoint { GeoPoint(lat: lat, lon: lon) }
}

/// Matches tracks to challenge places: the Trappist breweries and the boscafés.
enum TrappistMatcher {
    /// Raise when the rules below change: stored results are then computed again (see `ChallengeResults`).
    static let version = 1
    /// Metres between a place and the track.
    static let radius = 200.0

    /// The places a track passes within `radius` of: measured to the track's segments, so a
    /// sparse track (a Strava summary line) counts too.
    static func visited(by track: [GeoPoint], among trappists: [some ChallengePlace]) -> [String] {
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

    /// For each place, the start dates of the activities that visited it, newest first.
    static func visits(_ activities: [Activity], among trappists: [some ChallengePlace]) -> [String: [Date]] {
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
