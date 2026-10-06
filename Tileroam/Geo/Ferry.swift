import BackgroundAssets
import Foundation
import System

/// A ferry that takes cyclists, from OpenStreetMap (© OpenStreetMap contributors, ODbL): river
/// ferries and the Wadden ferries of the routing countries (Tools/build_ferries.py, the `ferries`
/// asset pack, see `FerryData`). Taken when an activity crosses it (`FerryMatcher`), issue #54.
struct Ferry: Codable, Sendable, Identifiable, Hashable, ChallengePlace {
    /// "osm-<way id>".
    let id: String
    /// The ferry's own name, if tagged ("Pont Lexmond–Culemborg"); `name` is what to show.
    let ownName: String?
    /// The nearest town, village or hamlet to each landing.
    let from: String?
    let to: String?
    let `operator`: String?
    let website: String?
    /// ISO code of the country whose extract it came from.
    let country: String
    /// Metres.
    let length: Double
    /// The middle of the crossing.
    let lat: Double
    let lon: Double
    /// The crossing, an encoded polyline (precision 5).
    let line: String

    enum CodingKeys: String, CodingKey {
        case id, ownName = "name", from, to, `operator`, website, country, length, lat, lon, line
    }

    /// The ferry's name, else "From – To".
    var name: String {
        if let ownName, !ownName.isEmpty { return ownName }
        switch (from, to) {
        case let (a?, b?) where a != b: return "\(a) – \(b)"
        case let (a?, _), let (_, a?): return String(localized: "Ferry at \(a)")
        default: return String(localized: "Ferry")
        }
    }

    var points: [GeoPoint] { StravaImport.decodePolyline(line) }
    var websiteLink: URL? { website.flatMap(URL.init(string:)) }
    var osmLink: URL? {
        id.hasPrefix("osm-") ? URL(string: "https://www.openstreetmap.org/way/\(id.dropFirst(4))") : nil
    }
}

/// The ferries: an Apple-hosted asset pack, `ferries` (ferries.json, built by
/// Tools/build_ferries.py, packaged by Tools/build_asset_packs.sh ferries; uploaded by the Asset
/// packs workflow when it changes on main).
enum FerryData {
    static let packID = "ferries"
    private static let fileName = "ferries.json"

    /// The list, if the pack is on the device already (empty otherwise).
    static func cached() -> [Ferry] {
        (try? data()).flatMap { try? JSONDecoder().decode([Ferry].self, from: $0) } ?? []
    }

    /// The list, downloading the pack when it isn't on the device yet (retried once).
    static func load() async throws -> [Ferry] {
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
                return try JSONDecoder().decode([Ferry].self, from: try data())
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
    /// Simulator and screenshots: `-FerriesFile <repo>/AssetPacks/Ferries/ferries.json`; Debug
    /// builds for the Mac use the repository's file by default.
    static var localFile: URL? {
        if let file = UserDefaults.standard.string(forKey: "FerriesFile") { return URL(filePath: file) }
        #if targetEnvironment(macCatalyst)
        let repo = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "AssetPacks/Ferries/ferries.json")
        if FileManager.default.fileExists(atPath: repo.path(percentEncoded: false)) { return repo }
        #endif
        return nil
    }
    #endif
}

/// Recognises ferry crossings in tracks.
enum FerryMatcher {
    /// Raise when the rules below change: stored results are then computed again.
    static let version = 1
    /// Metres between the track and a landing, and the crossing's middle: a third of the crossing,
    /// 15–80 m (a 30 m pontje over a ditch would otherwise count for riding along the bank).
    static func tolerance(_ ferry: Ferry) -> Double { min(80, max(15, ferry.length / 3)) }

    /// The ferries a track crossed: it came near both landings and near the middle of the crossing
    /// (so riding past a landing, or along the bank, doesn't count). Measured to the track's
    /// segments, so the straight line of a GPS that lost signal on the water counts too.
    static func crossed(by track: [GeoPoint], among ferries: [Ferry]) -> [String] {
        guard track.count >= 2, let first = track.first else { return [] }
        var box = (minLat: first.lat, maxLat: first.lat, minLon: first.lon, maxLon: first.lon)
        for p in track {
            box = (min(box.minLat, p.lat), max(box.maxLat, p.lat), min(box.minLon, p.lon), max(box.maxLon, p.lon))
        }
        return ferries.filter { ferry in
            let tolerance = tolerance(ferry), dLat = tolerance / 111_000
            let dLon = dLat / max(cos(ferry.lat * .pi / 180), 0.2)
            // The track must pass the middle of the crossing: most ferries end here.
            func near(_ p: GeoPoint) -> Bool {
                guard p.lat >= box.minLat - dLat, p.lat <= box.maxLat + dLat,
                      p.lon >= box.minLon - dLon, p.lon <= box.maxLon + dLon else { return false }
                return zip(track, track.dropFirst()).contains { a, b in TrappistMatcher.distance(from: p, toSegment: a, b) <= tolerance }
            }
            guard near(ferry.point) else { return false }
            let line = ferry.points
            guard let a = line.first, let b = line.last else { return false }
            return near(a) && near(b)
        }.map(\.id)
    }
}
