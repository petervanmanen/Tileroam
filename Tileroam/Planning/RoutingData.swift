import BackgroundAssets
import Foundation
import System

/// The on-device routing data: Valhalla tiles for the supported countries, built from
/// OpenStreetMap by `Tools/build_routing_tiles.sh` and split into Apple-hosted asset packs per
/// 1° × 1° area, so a plan downloads only the areas it needs. See docs/ROUTING.md.
enum RoutingData {
    /// Countries the routing data covers. Built together, so routes cross their borders.
    static let countries: Set<String> = ["NL", "BE", "LU", "DE"]
    /// The build whose index (`Resources/routing-<name>.json`) the app bundles.
    static let build = "west"

    /// Whether `p` lies in a country the routing data covers.
    static func covers(_ p: GeoPoint) -> Bool {
        guard let country = CountryOutlines.bundled?.country(at: p) else { return false }
        return countries.contains(country)
    }

    /// Where Valhalla reads its tiles from.
    enum Tiles: Equatable {
        /// One tile extract with all tiles (simulator and tests: -RoutingTar).
        case extract(URL)
        /// A directory with links to the tiles of the downloaded area packs.
        case directory(URL)
    }

    /// The bundled index of area packs.
    static let index: RoutingIndex? = {
        guard let url = Bundle.main.url(forResource: "routing-\(build)", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(RoutingIndex.self, from: data)
    }()

    /// The area packs a plan through `points` needs: every 1° area within `margin` meters of the
    /// points' bounding box. Areas without data (sea) aren't in the index.
    static func packs(around points: [GeoPoint], margin: Double, in index: RoutingIndex) -> [RoutingIndex.Area] {
        guard let first = points.first else { return [] }
        var minLat = first.lat, maxLat = first.lat, minLon = first.lon, maxLon = first.lon
        for p in points {
            minLat = min(minLat, p.lat); maxLat = max(maxLat, p.lat)
            minLon = min(minLon, p.lon); maxLon = max(maxLon, p.lon)
        }
        let dLat = margin / 111_000
        let dLon = margin / (111_000 * cos((minLat + maxLat) / 2 * .pi / 180))
        minLat -= dLat; maxLat += dLat; minLon -= dLon; maxLon += dLon
        return index.areas.filter { a in
            Double(a.lat) < maxLat && Double(a.lat + 1) > minLat && Double(a.lon) < maxLon && Double(a.lon + 1) > minLon
        }
    }

    /// Downloads the given area packs (plus the base pack) where needed and links their tiles into
    /// one directory for Valhalla. `replaced` says the data already on the device was thrown away
    /// because it came from another version of the build (see `versionCheck`).
    static func tileDirectory(for areas: [RoutingIndex.Area], index: RoutingIndex) async throws -> (dir: URL, replaced: Bool) {
        let dir = tileDirectory(index)
        let packs = [(index.base, index.baseFiles)] + areas.map { ($0.pack, $0.files) }
        var sources = [String: (String) -> URL]()
        for (pack, _) in packs { sources[pack] = try await packFolder(pack) }
        var replaced = false
        switch versionCheck(packs: packs.map { packVersion($0.0, in: sources[$0.0]!) },
                            linked: linkedVersion(index), indexVersion: index.version) {
        case .consistent:
            break
        case .refresh:
            // Mixed versions don't connect: start over with the latest version of every pack.
            await removeEverything(index)
            replaced = true
            for (pack, _) in packs { sources[pack] = try await packFolder(pack, latest: true) }
            let versions = Set(packs.map { packVersion($0.0, in: sources[$0.0]!) })
            guard versions.count == 1 else {
                throw RoutingError.dataUnavailable("the route planning data is being updated; try again later")
            }
        }
        let version = packVersion(index.base, in: sources[index.base]!)
        for (pack, files) in packs {
            let source = sources[pack]!
            for file in files {
                let link = dir.appending(path: file)
                let target = source(file)
                let linkPath = link.path(percentEncoded: false)
                if (try? FileManager.default.destinationOfSymbolicLink(atPath: linkPath)) == target.path(percentEncoded: false) {
                    continue
                }
                try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? FileManager.default.removeItem(at: link)
                try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
            }
        }
        try? String(version).write(to: dir.appending(path: versionFile), atomically: true, encoding: .utf8)
        // The links are recreated from the packs when needed: keep them out of backups.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var excluded = dir
        try? excluded.setResourceValues(values)
        return (dir, replaced)
    }

    // MARK: Versions

    /// Every build is one version of the routing data. Tiles of different versions don't connect
    /// (Valhalla numbers its graph per build), so the packs linked together must all have the same
    /// version. A refresh or a new country uploads new versions of the same pack IDs, and the
    /// system then hands out the new version for any pack downloaded after that, so a device can
    /// end up with old and new packs side by side. `versionCheck` catches that.
    ///
    /// The version is in the index (`version`) and in each pack, as the file `version/<pack ID>`
    /// (written by Tools/split_routing_tiles.py). Packs and indexes from before versions existed
    /// count as version 1. The tile directory remembers the version of its links (`versionFile`).
    enum VersionCheck: Equatable {
        /// All the same, and not older than the app's index: use them.
        case consistent(Int)
        /// Mixed, or older than the app's index: replace them with the latest versions.
        case refresh
    }

    static func versionCheck(packs: [Int], linked: Int?, indexVersion: Int) -> VersionCheck {
        let all = packs + (linked.map { [$0] } ?? [])
        guard let newest = all.max() else { return .consistent(indexVersion) }
        if all.contains(where: { $0 != newest }) || newest < indexVersion { return .refresh }
        return .consistent(newest)
    }

    private static let versionFile = ".version"

    /// The version of the links in the tile directory; nil when there are none yet. Links made
    /// before versions existed are version 1.
    static func linkedVersion(_ index: RoutingIndex) -> Int? {
        let dir = tileDirectory(index)
        if let text = try? String(contentsOf: dir.appending(path: versionFile), encoding: .utf8) {
            return Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let hasLinks = (try? FileManager.default.contentsOfDirectory(atPath: dir.path(percentEncoded: false)))?
            .contains { $0 != versionFile } ?? false
        return hasLinks ? 1 : nil
    }

    /// The version a downloaded pack belongs to.
    private static func packVersion(_ pack: String, in source: (String) -> URL) -> Int {
        guard let text = try? String(contentsOf: source("version/\(pack)"), encoding: .utf8) else { return 1 }
        return Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1
    }

    /// Removes every pack of the build from the device, and the tile directory.
    private static func removeEverything(_ index: RoutingIndex) async {
        try? FileManager.default.removeItem(at: tileDirectory(index))
        #if DEBUG
        if UserDefaults.standard.string(forKey: "RoutingPacksDir") != nil { return }
        #endif
        for id in possiblePackIDs(index.name, index: index) {
            if #available(iOS 26.4, *), !AssetPackManager.shared.assetPackIsAvailableLocally(withID: id) { continue }
            try? await AssetPackManager.shared.remove(assetPackWithID: id)
        }
    }

    /// Every pack ID a build may have had: its base and all 1° areas from 40°N 5°W to 61°N 30°E
    /// (an older version may have had areas the current index doesn't list). Without iOS 26.4's
    /// local check, only the index's own packs, to keep the number of remove calls down.
    private static func possiblePackIDs(_ build: String, index: RoutingIndex?) -> [String] {
        guard #available(iOS 26.4, *) else {
            return index.map { [$0.base] + $0.areas.map(\.pack) } ?? []
        }
        var ids = ["routing-\(build)-base"]
        for lat in 40...60 {
            for lon in -5...30 {
                ids.append("routing-\(build)-n\(String(format: "%02d", lat))\(lon < 0 ? "w" : "e")\(String(format: "%03d", abs(lon)))")
            }
        }
        return ids
    }

    /// Makes an asset pack available and returns where each of its files is. With `latest`, an
    /// older version on the device is updated first (from iOS 26.4; before that, a removed pack
    /// downloads in its latest version anyway).
    private static func packFolder(_ pack: String, latest: Bool = false) async throws -> (String) -> URL {
        #if DEBUG
        // Simulator: -RoutingPacksDir <repo>/AssetPacks/build/routing/packs-benelux.
        if let dir = UserDefaults.standard.string(forKey: "RoutingPacksDir") {
            let root = URL(filePath: dir, directoryHint: .isDirectory).appending(path: pack, directoryHint: .isDirectory)
            return { root.appending(path: $0) }
        }
        #endif
        let manager = AssetPackManager.shared
        do {
            let assetPack = try await manager.assetPack(withID: pack)
            if #available(iOS 26.4, *) {
                try await manager.ensureLocalAvailability(of: assetPack, requireLatestVersion: latest)
            } else {
                try await manager.ensureLocalAvailability(of: assetPack)
            }
        } catch {
            throw RoutingError.dataUnavailable(error.localizedDescription)
        }
        return { file in (try? manager.url(for: FilePath(file))) ?? URL(filePath: "/missing/\(file)") }
    }

    /// Whether a pack is on the device: its tiles are linked into the tile directory (works on
    /// every iOS version) or, from iOS 26.4, the system says so.
    static func isDownloaded(_ pack: String, firstFile: String?, index: RoutingIndex) -> Bool {
        #if DEBUG
        if UserDefaults.standard.string(forKey: "RoutingPacksDir") != nil { return true }
        #endif
        if let firstFile {
            let link = tileDirectory(index).appending(path: firstFile).path(percentEncoded: false)
            if let target = try? FileManager.default.destinationOfSymbolicLink(atPath: link),
               FileManager.default.fileExists(atPath: target) { return true }
        }
        if #available(iOS 26.4, *) { return AssetPackManager.shared.assetPackIsAvailableLocally(withID: pack) }
        return false
    }

    static func isDownloaded(_ area: RoutingIndex.Area, index: RoutingIndex) -> Bool {
        isDownloaded(area.pack, firstFile: area.files.first, index: index)
    }

    static func isBaseDownloaded(_ index: RoutingIndex) -> Bool {
        isDownloaded(index.base, firstFile: index.baseFiles.first, index: index)
    }

    /// Estimated download size of the areas (and the base pack) that aren't on the device yet.
    /// Packs download compressed, at about 40% of the tiles' size.
    static func downloadBytes(for areas: [RoutingIndex.Area], index: RoutingIndex) -> Int {
        let tiles = areas.filter { !isDownloaded($0, index: index) }.reduce(0) { $0 + $1.bytes }
            + (isBaseDownloaded(index) ? 0 : index.baseBytes)
        return Int(Double(tiles) * 0.4)
    }

    /// Where the links to the downloaded tiles live.
    static func tileDirectory(_ index: RoutingIndex) -> URL {
        URL.applicationSupportDirectory.appending(path: "Routing/tiles-\(index.name)", directoryHint: .isDirectory)
    }

    /// Removes downloaded area packs (or, with `includingBase`, everything): their tile links and
    /// the packs themselves. They download again when a plan needs them.
    static func remove(_ areas: [RoutingIndex.Area], includingBase: Bool, index: RoutingIndex) async {
        let dir = tileDirectory(index)
        var packs = areas.map { ($0.pack, $0.files) }
        if includingBase { packs.append((index.base, index.baseFiles)) }
        for (pack, files) in packs {
            for file in files { try? FileManager.default.removeItem(at: dir.appending(path: file)) }
            #if DEBUG
            if UserDefaults.standard.string(forKey: "RoutingPacksDir") != nil { continue }
            #endif
            try? await AssetPackManager.shared.remove(assetPackWithID: pack)
        }
    }

    /// Earlier builds whose packs may still be on the device (from TestFlight versions). Their tiles
    /// don't connect with the current build, so they're only taking space.
    static let retiredBuilds = ["benelux"]

    /// Removes the tile links and downloaded packs of `retiredBuilds`. Their area IDs follow the
    /// 1° grid, so every possible ID in the region is tried; only packs on the device are removed.
    static func removeRetiredBuilds() async {
        for build in retiredBuilds {
            let dir = URL.applicationSupportDirectory.appending(path: "Routing/tiles-\(build)", directoryHint: .isDirectory)
            try? FileManager.default.removeItem(at: dir)
            guard #available(iOS 26.4, *) else { continue }
            for id in possiblePackIDs(build, index: nil) where AssetPackManager.shared.assetPackIsAvailableLocally(withID: id) {
                try? await AssetPackManager.shared.remove(assetPackWithID: id)
            }
        }
    }

    /// Valhalla's configuration (`Resources/valhalla.json`, made with the same Valhalla version as
    /// the tiles) pointing at `tiles`, written to Application Support.
    static func writeConfig(_ tiles: Tiles) throws -> URL {
        guard let template = Bundle.main.url(forResource: "valhalla", withExtension: "json"),
              let data = try? Data(contentsOf: template),
              var config = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var mjolnir = config["mjolnir"] as? [String: Any] else {
            throw RoutingError.dataUnavailable("valhalla.json")
        }
        switch tiles {
        case .extract(let url):
            mjolnir["tile_extract"] = url.path(percentEncoded: false)
            mjolnir["tile_dir"] = ""
        case .directory(let url):
            mjolnir["tile_extract"] = ""
            mjolnir["tile_dir"] = url.path(percentEncoded: false)
        }
        config["mjolnir"] = mjolnir
        let folder = URL.applicationSupportDirectory.appending(path: "Routing", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "valhalla.json")
        try JSONSerialization.data(withJSONObject: config).write(to: url, options: .atomic)
        return url
    }
}

/// The areas of a routing build (`Resources/routing-<name>.json`, written by
/// `Tools/split_routing_tiles.py`).
struct RoutingIndex: Decodable, Sendable {
    struct Area: Decodable, Sendable, Hashable {
        /// Asset pack id, e.g. "routing-benelux-n51e005".
        let pack: String
        /// South-west corner of the 1° area.
        let lat: Int
        let lon: Int
        /// Uncompressed size of its tiles.
        let bytes: Int
        /// Tile paths inside the pack ("2/000/791/223.gph").
        let files: [String]
    }

    let name: String
    /// The version of the build's data (see `RoutingData.VersionCheck`); 1 for indexes from before
    /// versions existed.
    let version: Int
    /// The pack with the level-0 (main road) tiles, needed by every plan.
    let base: String
    let areas: [Area]
    let baseFiles: [String]
    let baseBytes: Int

    private enum CodingKeys: String, CodingKey { case name, version, base, areas, baseFiles, baseBytes }

    init(name: String, version: Int = 1, base: String, areas: [Area], baseFiles: [String], baseBytes: Int) {
        self.name = name
        self.version = version
        self.base = base
        self.areas = areas
        self.baseFiles = baseFiles
        self.baseBytes = baseBytes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        base = try c.decode(String.self, forKey: .base)
        areas = try c.decode([Area].self, forKey: .areas)
        baseFiles = try c.decode([String].self, forKey: .baseFiles)
        baseBytes = try c.decode(Int.self, forKey: .baseBytes)
    }
}
