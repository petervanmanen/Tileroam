import BackgroundAssets
import Foundation

/// The on-device routing data: Valhalla tiles for the supported countries, built from
/// OpenStreetMap by `Tools/build_routing_tiles.sh` and served from Cloudflare R2. A plan downloads
/// only the tiles around it, of each of Valhalla's three levels. See docs/ROUTING.md.
enum RoutingData {
    /// Countries the routing data covers. Built together, so routes cross their borders.
    static let countries: Set<String> = ["NL", "BE", "LU", "DE", "FR", "CH", "AT"]
    /// The build whose index (`Resources/routing-<name>.json`) the app bundles. Keep the name; new
    /// data is a new version of it (docs/ROUTING.md, "Versions").
    static let build = "west"
    /// Where the tiles are: `<server>/<build>/v<version>/<tile>.gph.gz` (Tools/upload_routing_r2.sh).
    /// Set in Servers.plist.
    static var server: URL { Servers.routingTiles }

    /// Whether `p` lies in a country the routing data covers.
    static func covers(_ p: GeoPoint) -> Bool {
        guard let country = CountryOutlines.bundled?.country(at: p) else { return false }
        return countries.contains(country)
    }

    /// Where Valhalla reads its tiles from.
    enum Tiles: Equatable {
        /// One tile extract with all tiles (simulator and tests: -RoutingTar).
        case extract(URL)
        /// A directory with the downloaded tiles.
        case directory(URL)
    }

    /// The bundled index of tiles.
    static let index: RoutingIndex? = {
        guard let url = Bundle.main.url(forResource: "routing-\(build)", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(RoutingIndex.self, from: data)
    }()

    /// The tiles a plan through `points` needs: those of every level that overlap the points'
    /// bounding box widened by `margin` meters. Tiles without data (sea) aren't in the index.
    static func tiles(around points: [GeoPoint], margin: Double, in index: RoutingIndex) -> [RoutingIndex.Tile] {
        guard let first = points.first else { return [] }
        var minLat = first.lat, maxLat = first.lat, minLon = first.lon, maxLon = first.lon
        for p in points {
            minLat = min(minLat, p.lat); maxLat = max(maxLat, p.lat)
            minLon = min(minLon, p.lon); maxLon = max(maxLon, p.lon)
        }
        let dLat = margin / 111_000
        let dLon = margin / (111_000 * cos((minLat + maxLat) / 2 * .pi / 180))
        minLat -= dLat; maxLat += dLat; minLon -= dLon; maxLon += dLon
        return index.tiles.filter { t in
            t.lat < maxLat && t.lat + t.size > minLat && t.lon < maxLon && t.lon + t.size > minLon
        }
    }

    /// The tiles a plan needs when its stops are spread out: those within `margin` meters of the
    /// straight lines between the stops (`path`, in visiting order) or of any of `points` (the
    /// candidate points inside each target). Unlike the bounding box, this doesn't pull in every
    /// tile between far-apart targets.
    static func tiles(along path: [GeoPoint], near points: [GeoPoint], margin: Double, in index: RoutingIndex) -> [RoutingIndex.Tile] {
        var samples = points
        for (a, b) in zip(path, path.dropFirst()) {
            let steps = max(1, Int(Geo.distance(a, b) / 2_000))
            for k in 0...steps {
                let f = Double(k) / Double(steps)
                samples.append(GeoPoint(lat: a.lat + (b.lat - a.lat) * f, lon: a.lon + (b.lon - a.lon) * f))
            }
        }
        guard !samples.isEmpty else { return [] }
        let dLat = margin / 111_000
        return index.tiles.filter { t in
            let dLon = margin / (111_000 * max(cos((t.lat + t.size / 2) * .pi / 180), 0.2))
            return samples.contains { p in
                p.lat > t.lat - dLat && p.lat < t.lat + t.size + dLat && p.lon > t.lon - dLon && p.lon < t.lon + t.size + dLon
            }
        }
    }

    // MARK: On the device

    /// Where the downloaded tiles of this version live. Each version has its own folder, because
    /// tiles of different builds don't connect.
    static func tileDirectory(_ index: RoutingIndex) -> URL {
        URL.applicationSupportDirectory.appending(path: "Routing/\(index.name)-v\(index.version)", directoryHint: .isDirectory)
    }

    static func isDownloaded(_ tile: RoutingIndex.Tile, index: RoutingIndex) -> Bool {
        FileManager.default.fileExists(atPath: tileDirectory(index).appending(path: tile.file).path(percentEncoded: false))
    }

    /// Download size of the tiles that aren't on the device yet.
    static func downloadBytes(for tiles: [RoutingIndex.Tile], index: RoutingIndex) -> Int {
        tiles.filter { !isDownloaded($0, index: index) }.reduce(0) { $0 + $1.bytes }
    }

    /// The downloaded tiles.
    static func downloadedTiles(_ index: RoutingIndex) -> [RoutingIndex.Tile] {
        index.tiles.filter { isDownloaded($0, index: index) }
    }

    /// Downloads the tiles that aren't on the device yet, six at a time, and returns the tile
    /// directory for Valhalla. `progress` gets the bytes downloaded so far and the total. Every
    /// finished tile is kept, so after a failure the next try only fetches what's still missing.
    static func download(_ tiles: [RoutingIndex.Tile], index: RoutingIndex, from server: URL = serverURL,
                         session: URLSession = tileSession,
                         progress: (@Sendable (_ done: Int, _ total: Int) async -> Void)? = nil) async throws -> URL {
        removeOtherVersions(index)
        let dir = tileDirectory(index)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let missing = tiles.filter { !isDownloaded($0, index: index) }
        let total = missing.reduce(0) { $0 + $1.bytes }
        var done = 0
        try await withThrowingTaskGroup(of: Int.self) { group in
            var next = 0
            func addNext() {
                guard next < missing.count else { return }
                let tile = missing[next]
                next += 1
                group.addTask {
                    try await fetch(tile, index: index, from: server, session: session, into: dir)
                    return tile.bytes
                }
            }
            for _ in 0..<6 { addNext() }
            while let bytes = try await group.next() {
                done += bytes
                await progress?(done, total)
                addNext()
            }
        }
        // Downloaded again when needed: keep them out of backups.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var excluded = dir
        try? excluded.setResourceValues(values)
        return dir
    }

    /// The server, or in Debug builds -RoutingServer (for example a file:// URL to
    /// AssetPacks/build/routing/r2 for the simulator and tests).
    static var serverURL: URL {
        #if DEBUG
        if let text = UserDefaults.standard.string(forKey: "RoutingServer"), let url = URL(string: text) { return url }
        #endif
        return server
    }

    /// For tile downloads: a request that gets no data for 30 seconds fails (and is retried); a
    /// tile may take up to 5 minutes on a slow connection.
    static let tileSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    /// Downloads one tile (see `RemoteFile.get`), checking its size against the index.
    private static func fetch(_ tile: RoutingIndex.Tile, index: RoutingIndex, from server: URL, session: URLSession,
                              into dir: URL) async throws {
        let url = server.appending(path: "\(index.name)/v\(index.version)/\(tile.path).gph.gz")
        let tiles = try await RemoteFile.get(url, session: session) { $0.count == tile.rawBytes }
        let file = dir.appending(path: tile.file)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try tiles.write(to: file, options: .atomic)
    }

    /// Removes downloaded tiles (Settings → Storage). They download again when a plan needs them.
    static func remove(_ tiles: [RoutingIndex.Tile], index: RoutingIndex) {
        let dir = tileDirectory(index)
        for tile in tiles { try? FileManager.default.removeItem(at: dir.appending(path: tile.file)) }
    }

    static func removeAll(_ index: RoutingIndex) {
        try? FileManager.default.removeItem(at: tileDirectory(index))
    }

    // MARK: Cleaning up

    /// Removes the tiles of the build's other versions ("west-v1" next to "west-v2"), and the tile
    /// folders from before R2 ("tiles-west", "tiles-benelux"; see `removeAssetPackData`).
    static func removeOtherVersions(_ index: RoutingIndex) {
        let routing = URL.applicationSupportDirectory.appending(path: "Routing", directoryHint: .isDirectory)
        let current = "\(index.name)-v\(index.version)"
        for item in (try? FileManager.default.contentsOfDirectory(atPath: routing.path(percentEncoded: false))) ?? []
        where item != current && (item.hasPrefix("\(index.name)-v") || item.hasPrefix("tiles-")) {
            try? FileManager.default.removeItem(at: routing.appending(path: item))
        }
    }

    /// Builds whose tiles came as Apple-hosted asset packs, before R2 (TestFlight versions of
    /// October 2026): "benelux" and the first "west".
    static let assetPackBuilds = ["benelux", "west"]

    /// Removes the routing asset packs of earlier versions from the device, and the old tile
    /// folders. Their IDs followed a 1° grid ("routing-west-n52e005"), so every possible ID in the
    /// region is tried; only packs on the device are removed (needs iOS 26.4 to check).
    static func removeAssetPackData() async {
        if let index { removeOtherVersions(index) }
        guard #available(iOS 26.4, *) else { return }
        for build in assetPackBuilds {
            var ids = ["routing-\(build)-base"]
            for lat in 40...60 {
                for lon in -5...30 {
                    ids.append("routing-\(build)-n\(String(format: "%02d", lat))\(lon < 0 ? "w" : "e")\(String(format: "%03d", abs(lon)))")
                }
            }
            for id in ids where AssetPackManager.shared.assetPackIsAvailableLocally(withID: id) {
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

/// The tiles of a routing build (`Resources/routing-<name>.json`, written by
/// Tools/pack_routing_tiles.py).
struct RoutingIndex: Decodable, Sendable {
    struct Tile: Decodable, Sendable, Hashable {
        /// Valhalla's tile path without extension: "2/000/791/223" (level 2, tile 791223).
        let path: String
        /// Download size (gzipped).
        let bytes: Int
        /// Size on the device.
        let rawBytes: Int

        /// Valhalla's tile sizes per level: 4°, 1° and 0.25°.
        static let sizes = [4.0, 1.0, 0.25]

        var level: Int { Int(path.prefix(1)) ?? 2 }
        var size: Double { Self.sizes[min(level, 2)] }
        var file: String { path + ".gph" }
        private var id: Int { Int(path.dropFirst(2).filter(\.isNumber)) ?? 0 }
        /// South-west corner.
        var lat: Double { -90 + Double(id / Int(360 / size)) * size }
        var lon: Double { -180 + Double(id % Int(360 / size)) * size }

        init(path: String, bytes: Int, rawBytes: Int) {
            self.path = path
            self.bytes = bytes
            self.rawBytes = rawBytes
        }

        /// Stored as [path, bytes, rawBytes], to keep the index small.
        init(from decoder: Decoder) throws {
            var c = try decoder.unkeyedContainer()
            path = try c.decode(String.self)
            bytes = try c.decode(Int.self)
            rawBytes = try c.decode(Int.self)
        }
    }

    let name: String
    /// The version of the build's data: its folder on the server (docs/ROUTING.md, "Versions").
    let version: Int
    let tiles: [Tile]
}

/// Files from Tileroam's server (Cloudflare R2): map tiles and climbs.
enum RemoteFile {
    /// Downloads a gzipped file, trying up to three times when the connection times out or drops,
    /// the server has a passing problem (5xx, 429) or the file arrives damaged (`isValid` says no).
    /// Errors are `RoutingError.download`.
    static func get(_ url: URL, session: URLSession, isValid: @Sendable (Data) -> Bool) async throws -> Data {
        var attempt = 0
        while true {
            attempt += 1
            do {
                return try await getOnce(url, session: session, isValid: isValid)
            } catch let problem as DownloadProblem where problem.isTransient && attempt < 3 {
                try await Task.sleep(for: .seconds(2 * attempt)) // throws when the plan is stopped
            } catch let problem as DownloadProblem {
                throw RoutingError.download(problem)
            }
        }
    }

    private static func getOnce(_ url: URL, session: URLSession, isValid: @Sendable (Data) -> Bool) async throws -> Data {
        var data: Data
        do {
            let (body, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                throw DownloadProblem.server(http.statusCode)
            }
            data = body
        } catch let error as URLError {
            switch error.code {
            case .cancelled: throw CancellationError()
            case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff: throw DownloadProblem.offline
            case .timedOut: throw DownloadProblem.timedOut
            case .fileDoesNotExist: throw DownloadProblem.server(404)
            default: throw DownloadProblem.connection(error.localizedDescription)
            }
        }
        // Normally URLSession has already decompressed it (Content-Encoding: gzip); a server or
        // file:// URL that doesn't say so hands over the gzip file itself.
        if data.starts(with: [0x1F, 0x8B]) {
            guard let unpacked = try? Gzip.decompress(data) else { throw DownloadProblem.damaged }
            data = unpacked
        }
        guard isValid(data) else { throw DownloadProblem.damaged }
        return data
    }
}

/// Gzip files (RFC 1952), for files a server hands over without decompressing them.
enum Gzip {
    static func decompress(_ data: Data) throws -> Data {
        let bytes = [UInt8](data)
        guard bytes.count > 18, bytes[0] == 0x1F, bytes[1] == 0x8B, bytes[2] == 8 else {
            throw RoutingError.dataUnavailable("not a gzip file")
        }
        let flags = bytes[3]
        var i = 10
        if flags & 0x04 != 0 { i += 2 + Int(bytes[i]) + Int(bytes[i + 1]) << 8 } // extra field
        if flags & 0x08 != 0 { while i < bytes.count, bytes[i] != 0 { i += 1 }; i += 1 } // name
        if flags & 0x10 != 0 { while i < bytes.count, bytes[i] != 0 { i += 1 }; i += 1 } // comment
        if flags & 0x02 != 0 { i += 2 } // header checksum
        guard i < bytes.count - 8 else { throw RoutingError.dataUnavailable("damaged gzip file") }
        // The deflate stream without the 8-byte trailer; NSData's .zlib is raw deflate.
        let deflated = Data(bytes[i..<(bytes.count - 8)]) as NSData
        return try deflated.decompressed(using: .zlib) as Data
    }
}
