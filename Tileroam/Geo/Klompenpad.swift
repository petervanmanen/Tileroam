import BackgroundAssets
import Foundation
import System

/// A Klompenpad (www.klompenpaden.nl): a walking path through the countryside of Gelderland and
/// Utrecht. The list is an asset pack (see `KlompenpadData`), made by Tools/build_klompenpaden.py. A path is walked when the user's
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

/// The Klompenpaden list: an Apple-hosted asset pack, `klompenpaden` (klompenpaden.json, built by
/// Tools/build_klompenpaden.py and packaged by Tools/build_asset_packs.sh klompenpaden; uploaded
/// with Tools/upload_asset_packs.sh klompenpaden, or by the Asset packs workflow when the list
/// changes on main). Downloaded on demand at the first refresh; the system keeps it.
enum KlompenpadData {
    static let packID = "klompenpaden"
    private static let fileName = "klompenpaden.json"

    /// The list, if the pack is on the device already (empty otherwise).
    static func cached() -> [Klompenpad] {
        (try? data()).flatMap { try? JSONDecoder().decode([Klompenpad].self, from: $0) } ?? []
    }

    /// The list, downloading the pack when it isn't on the device yet (retried once).
    static func load() async throws -> [Klompenpad] {
        #if DEBUG
        if localFile != nil { return cached() }
        #endif
        let manager = AssetPackManager.shared
        var lastError: (any Error)?
        for attempt in 0..<2 {
            if attempt > 0 { try await Task.sleep(for: .seconds(2)) }
            do {
                let pack = try await manager.assetPack(withID: packID)
                if #available(iOS 26.4, *) {
                    try await manager.ensureLocalAvailability(of: pack, requireLatestVersion: false)
                } else {
                    try await manager.ensureLocalAvailability(of: pack)
                }
                return try JSONDecoder().decode([Klompenpad].self, from: try data())
            } catch {
                lastError = error
            }
        }
        throw lastError!
    }

    private static func data() throws -> Data {
        #if DEBUG
        if let localFile { return try Data(contentsOf: localFile) }
        #endif
        return try AssetPackManager.shared.contents(at: FilePath(fileName), searchingInAssetPackWithID: packID)
    }

    #if DEBUG
    /// Simulator and screenshots: read the list from the Mac instead of the asset pack, e.g.
    /// `-KlompenpadenFile /path/to/Tileroam/AssetPacks/Klompenpaden/klompenpaden.json`.
    /// Debug builds for the Mac use the repository's file by default (see `RegionAssets.localDirectory`).
    static var localFile: URL? {
        if let file = UserDefaults.standard.string(forKey: "KlompenpadenFile") { return URL(filePath: file) }
        #if targetEnvironment(macCatalyst)
        let repo = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "AssetPacks/Klompenpaden/klompenpaden.json")
        if FileManager.default.fileExists(atPath: repo.path(percentEncoded: false)) { return repo }
        #endif
        return nil
    }
    #endif
}

/// How much of each path the user has walked: the share of points along its main route (one
/// every 50 m) that any activity passed within 30 m of, over all activities together.
enum KlompenpadMatcher {
    /// Raise when the rules below change: stored results are then computed again (see `ChallengeResults`).
    static let version = 1
    static let tolerance = 30.0
    static let spacing = 50.0
    /// From this share a path counts as walked (GPS and the path's drawing differ a little).
    static let done = 0.9

    static func checkpoints(_ path: Klompenpad) -> [GeoPoint] {
        path.pieces.flatMap { Geo.densified($0, spacing: spacing, maxGap: .infinity) }
    }

    /// The paths' checkpoints and boxes, made once per list.
    struct Prepared: Sendable {
        struct Path: Sendable {
            let id: String
            let points: [GeoPoint]
            let minLat, maxLat, minLon, maxLon: Double
        }
        let paths: [Path]

        init(_ list: [Klompenpad]) {
            let m = KlompenpadMatcher.tolerance / 111_000 * 2
            paths = list.map { p in
                let points = KlompenpadMatcher.checkpoints(p)
                let lats = points.map(\.lat), lons = points.map(\.lon)
                return Path(id: p.id, points: points, minLat: (lats.min() ?? 0) - m, maxLat: (lats.max() ?? 0) + m,
                            minLon: (lons.min() ?? 0) - m * 1.6, maxLon: (lons.max() ?? 0) + m * 1.6)
            }
        }

        /// Checkpoints per path.
        var counts: [String: Int] { Dictionary(paths.map { ($0.id, $0.points.count) }, uniquingKeysWith: { a, _ in a }) }
    }

    /// For one track: per path it comes near, the indexes of the checkpoints it passes within
    /// `tolerance`.
    static func hits(_ track: [GeoPoint], paths: Prepared) -> [String: [Int]] {
        guard let minLat = track.map(\.lat).min(), let maxLat = track.map(\.lat).max(),
              let minLon = track.map(\.lon).min(), let maxLon = track.map(\.lon).max() else { return [:] }
        var grid: ClimbMatcher.TrackGrid?
        var result = [String: [Int]]()
        for path in paths.paths where path.minLat <= maxLat && path.maxLat >= minLat && path.minLon <= maxLon && path.maxLon >= minLon {
            if grid == nil { grid = ClimbMatcher.TrackGrid(track) }
            let hit = path.points.indices.filter { grid!.nearest(to: path.points[$0], within: tolerance) != nil }
            if !hit.isEmpty { result[path.id] = hit }
        }
        return result
    }

    /// For each path with any progress, the share of its main route covered (0…1), from the
    /// activities' hits together (several walks add up).
    static func progress(hits: [[String: [Int]]], counts: [String: Int]) -> [String: Double] {
        var union = [String: Set<Int>]()
        for h in hits { for (id, indexes) in h { union[id, default: []].formUnion(indexes) } }
        var result = [String: Double]()
        for (id, passed) in union {
            guard let total = counts[id], total > 0 else { continue } // a path no longer in the list
            result[id] = min(1, Double(passed.count) / Double(total))
        }
        return result
    }

    /// The same for activities computed now (tests; the app stores the hits per activity).
    static func progress(_ activities: [Activity], paths: [Klompenpad]) -> [String: Double] {
        let prepared = Prepared(paths)
        let hits = activities.filter(\.isOnMap).map { a in
            self.hits(a.coordinates.map { GeoPoint(lat: $0.latitude, lon: $0.longitude) }, paths: prepared)
        }
        return progress(hits: hits, counts: prepared.counts)
    }
}
