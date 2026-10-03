import Foundation

/// The climbs of the routing countries, per 1° area on Cloudflare R2
/// (`<server>/<build>/climbs/v<version>/<area>.json.gz`, from Tools/build_climbs.sh). The app
/// downloads the areas around the user's activities, the map they look at and their plans, and
/// keeps them in `Application Support/Climbs/<build>-v<version>`. See docs/CLIMBS.md.
enum ClimbData {
    /// The bundled index of areas (`Resources/climbs-<build>.json`).
    static let index: ClimbIndex? = {
        guard let url = Bundle.main.url(forResource: "climbs-\(RoutingData.build)", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ClimbIndex.self, from: data)
    }()

    /// Identifies the climbs a result was computed with ("west-v1"), so activities are matched
    /// again when the climbs change.
    static func key(_ index: ClimbIndex) -> String { "\(index.name)-v\(index.version)" }

    static func folder(_ index: ClimbIndex) -> URL {
        URL.applicationSupportDirectory.appending(path: "Climbs/\(key(index))", directoryHint: .isDirectory)
    }

    /// Areas with climbs within `margin` degrees of the given box.
    static func areas(minLat: Double, maxLat: Double, minLon: Double, maxLon: Double, margin: Double = 0.05,
                      in index: ClimbIndex) -> [ClimbIndex.Area] {
        index.areas.filter { a in
            Double(a.lat) < maxLat + margin && Double(a.lat + 1) > minLat - margin
                && Double(a.lon) < maxLon + margin && Double(a.lon + 1) > minLon - margin
        }
    }

    /// Areas around points (a route, a plan).
    static func areas(around points: [GeoPoint], in index: ClimbIndex) -> [ClimbIndex.Area] {
        guard let first = points.first else { return [] }
        var box = (minLat: first.lat, maxLat: first.lat, minLon: first.lon, maxLon: first.lon)
        for p in points {
            box = (min(box.minLat, p.lat), max(box.maxLat, p.lat), min(box.minLon, p.lon), max(box.maxLon, p.lon))
        }
        return areas(minLat: box.minLat, maxLat: box.maxLat, minLon: box.minLon, maxLon: box.maxLon, in: index)
    }

    static func isDownloaded(_ area: ClimbIndex.Area, index: ClimbIndex) -> Bool {
        FileManager.default.fileExists(atPath: folder(index).appending(path: area.file).path(percentEncoded: false))
    }

    /// The climbs of these areas, downloading those not on the device yet (four at a time).
    static func load(_ areas: [ClimbIndex.Area], index: ClimbIndex, from server: URL = RoutingData.serverURL,
                     session: URLSession = RoutingData.tileSession) async throws -> [Climb] {
        removeOtherVersions(index)
        let dir = folder(index)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let missing = areas.filter { !isDownloaded($0, index: index) }
        try await withThrowingTaskGroup(of: Void.self) { group in
            var next = 0
            func addNext() {
                guard next < missing.count else { return }
                let area = missing[next]
                next += 1
                group.addTask {
                    let url = server.appending(path: "\(index.name)/climbs/v\(index.version)/\(area.key).json.gz")
                    let data = try await RemoteFile.get(url, session: session) { (try? JSONDecoder().decode([Climb].self, from: $0)) != nil }
                    try data.write(to: dir.appending(path: area.file), options: .atomic)
                }
            }
            for _ in 0..<4 { addNext() }
            while try await group.next() != nil { addNext() }
        }
        return areas.flatMap { area in
            (try? Data(contentsOf: dir.appending(path: area.file))).flatMap { try? JSONDecoder().decode([Climb].self, from: $0) } ?? []
        }
    }

    /// The climbs already on the device (all downloaded areas).
    static func downloaded(_ index: ClimbIndex) -> [Climb] {
        index.areas.filter { isDownloaded($0, index: index) }.flatMap { area in
            (try? Data(contentsOf: folder(index).appending(path: area.file))).flatMap { try? JSONDecoder().decode([Climb].self, from: $0) } ?? []
        }
    }

    /// Removes the climbs of other versions.
    static func removeOtherVersions(_ index: ClimbIndex) {
        let climbs = URL.applicationSupportDirectory.appending(path: "Climbs", directoryHint: .isDirectory)
        for item in (try? FileManager.default.contentsOfDirectory(atPath: climbs.path(percentEncoded: false))) ?? []
        where item != key(index) {
            try? FileManager.default.removeItem(at: climbs.appending(path: item))
        }
    }
}

/// The areas of a climbs build (`Resources/climbs-<build>.json`, written by Tools/split_climbs.py).
struct ClimbIndex: Decodable, Sendable {
    struct Area: Decodable, Sendable, Hashable {
        /// "n50e005": the 1° area from 50°N 5°E.
        let key: String
        let count: Int
        /// Download size.
        let bytes: Int

        var file: String { key + ".json" }
        var lat: Int { (key.hasPrefix("s") ? -1 : 1) * (Int(key.dropFirst().prefix(2)) ?? 0) }
        var lon: Int { (key.dropFirst(3).hasPrefix("w") ? -1 : 1) * (Int(key.suffix(3)) ?? 0) }

        init(key: String, count: Int, bytes: Int) {
            self.key = key
            self.count = count
            self.bytes = bytes
        }

        /// Stored as [key, count, bytes].
        init(from decoder: Decoder) throws {
            var c = try decoder.unkeyedContainer()
            key = try c.decode(String.self)
            count = try c.decode(Int.self)
            bytes = try c.decode(Int.self)
        }
    }

    let name: String
    let version: Int
    let areas: [Area]
}
