import Foundation

/// A Klompenpad (www.klompenpaden.nl): a walking path through the countryside of Gelderland and
/// Utrecht. The list is on Cloudflare R2 (`<server>/Klompenpaden/klompenpaden.json`, see
/// `KlompenpadData`), made by Tools/build_klompenpaden.py. A path is walked when the user's
/// activities cover its main route (`KlompenpadMatcher`).
struct Klompenpad: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let name: String
    /// The village it starts from.
    let start: String
    /// Km, of its variants (the main route and shortcuts or extensions).
    let lengths: [Double]
    let url: String
    let lat: Double
    let lon: Double
    /// Metres of the main route.
    let length: Double
    /// The main route, often in several pieces, as encoded polylines (precision 5).
    let lines: [String]

    var startPoint: GeoPoint { GeoPoint(lat: lat, lon: lon) }
    var pieces: [[GeoPoint]] { lines.map(StravaImport.decodePolyline) }
    var link: URL? { URL(string: url) }

    /// "9, 12, 14 km"
    var lengthsText: String {
        lengths.map { $0.formatted(.number.precision(.fractionLength(0...1))) }.joined(separator: ", ") + " km"
    }
}

/// The Klompenpaden list on R2, uploaded with Tools/upload_klompenpaden_r2.sh from
/// AssetPacks/Klompenpaden; kept in `Application Support/Klompenpaden` (see `RemoteList`).
enum KlompenpadData {
    static var folder: URL { URL.applicationSupportDirectory.appending(path: "Klompenpaden", directoryHint: .isDirectory) }
    private static let listName = "klompenpaden.json"

    static func cached(in folder: URL = folder) -> [Klompenpad] {
        RemoteList.cached(Klompenpad.self, name: listName, in: folder)
    }

    static func load(from server: URL = RoutingData.serverURL, session: URLSession = RoutingData.tileSession,
                     into folder: URL = folder, now: Date = .now) async throws -> [Klompenpad] {
        try await RemoteList.load(Klompenpad.self, name: listName, remote: "Klompenpaden", into: folder,
                                  from: server, session: session, now: now)
    }
}

/// How much of each path the user has walked: the share of points along its main route (one
/// every 50 m) that any activity passed within 30 m of, over all activities together.
enum KlompenpadMatcher {
    static let tolerance = 30.0
    static let spacing = 50.0
    /// From this share a path counts as walked (GPS and the path's drawing differ a little).
    static let done = 0.9

    static func checkpoints(_ path: Klompenpad) -> [GeoPoint] {
        path.pieces.flatMap { Geo.densified($0, spacing: spacing, maxGap: .infinity) }
    }

    /// For each path with any progress, the share of its main route covered (0…1).
    static func progress(_ activities: [Activity], paths: [Klompenpad]) -> [String: Double] {
        struct Prepared { let id: String; let points: [GeoPoint]; let box: (Double, Double, Double, Double); var hit: [Bool] }
        let m = tolerance / 111_000 * 2
        var prepared = paths.map { p -> Prepared in
            let points = checkpoints(p)
            let lats = points.map(\.lat), lons = points.map(\.lon)
            return Prepared(id: p.id, points: points,
                            box: ((lats.min() ?? 0) - m, (lats.max() ?? 0) + m, (lons.min() ?? 0) - m * 1.6, (lons.max() ?? 0) + m * 1.6),
                            hit: Array(repeating: false, count: points.count))
        }
        for a in activities where a.isOnMap {
            let track = a.coordinates.map { GeoPoint(lat: $0.latitude, lon: $0.longitude) }
            guard let minLat = track.map(\.lat).min(), let maxLat = track.map(\.lat).max(),
                  let minLon = track.map(\.lon).min(), let maxLon = track.map(\.lon).max() else { continue }
            var grid: ClimbMatcher.TrackGrid?
            for i in prepared.indices {
                let b = prepared[i].box
                guard b.0 <= maxLat, b.1 >= minLat, b.2 <= maxLon, b.3 >= minLon else { continue }
                if grid == nil { grid = ClimbMatcher.TrackGrid(track) }
                for (k, p) in prepared[i].points.enumerated() where !prepared[i].hit[k] {
                    if grid!.nearest(to: p, within: tolerance) != nil { prepared[i].hit[k] = true }
                }
            }
        }
        var result = [String: Double]()
        for p in prepared where !p.points.isEmpty {
            let share = Double(p.hit.count(where: { $0 })) / Double(p.points.count)
            if share > 0 { result[p.id] = share }
        }
        return result
    }
}
