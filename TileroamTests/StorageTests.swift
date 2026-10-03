import Foundation
import Testing
@testable import Tileroam

struct MapDataDownloadTests {
    @Test func largeDownloadsWaitForWiFi() {
        let mb = 1_000_000
        // Small downloads: always.
        #expect(MapDataDownloads.mayDownload(bytes: 20 * mb, isExpensive: true, isConstrained: false, allowMobileData: false))
        // Large downloads: on Wi-Fi…
        #expect(MapDataDownloads.mayDownload(bytes: 73 * mb, isExpensive: false, isConstrained: false, allowMobileData: false))
        // …not on mobile data or in Low Data Mode…
        #expect(!MapDataDownloads.mayDownload(bytes: 73 * mb, isExpensive: true, isConstrained: false, allowMobileData: false))
        #expect(!MapDataDownloads.mayDownload(bytes: 73 * mb, isExpensive: false, isConstrained: true, allowMobileData: false))
        // …unless allowed (setting or Download Anyway).
        #expect(MapDataDownloads.mayDownload(bytes: 73 * mb, isExpensive: true, isConstrained: true, allowMobileData: true))
    }

    @Test func formatsMegabytes() {
        #expect(MapDataDownloads.format(73_400_000).contains("73"))
        #expect(!MapDataDownloads.format(73_400_000).contains("4"))
        #expect(MapDataDownloads.format(2_000).hasPrefix("0") && MapDataDownloads.format(2_000).contains("1"))
        #expect(MapDataDownloads.format(0).hasPrefix("0"))
    }
}


@Suite(.serialized)
struct RoutingDownloadTests {
    /// A tiny build on a local "server" (a folder, reached through a file:// URL as -RoutingServer
    /// does in the simulator), laid out as Tools/pack_routing_tiles.py and the R2 upload make it.
    private func server(version: Int = 1, gzip: Bool = true) throws -> (RoutingIndex, URL) {
        let root = FileManager.default.temporaryDirectory.appending(path: "r2-\(UUID())", directoryHint: .isDirectory)
        // Level 2 tile 818663 lies at 52°N 5.75°E; level 1 tile 51305 at 52°N 5°E; level 0 tile 3196
        // covers 50–54°N 4–8°E.
        let contents: [(String, Data)] = [("2/000/818/663", Data(repeating: 2, count: 3000)),
                                          ("1/051/305", Data(repeating: 1, count: 2000)),
                                          ("0/003/196", Data(repeating: 0, count: 1000))]
        var tiles = [RoutingIndex.Tile]()
        for (path, raw) in contents {
            let file = root.appending(path: "download-test/v\(version)/\(path).gph.gz")
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let packed = gzip ? try Self.gzip(raw) : raw
            try packed.write(to: file)
            tiles.append(.init(path: path, bytes: packed.count, rawBytes: raw.count))
        }
        let index = RoutingIndex(name: "download-test", version: version, tiles: tiles)
        RoutingData.removeAll(index)
        return (index, root)
    }

    /// A gzip file as Python's gzip.compress makes it: header, raw deflate, CRC and size.
    static func gzip(_ data: Data) throws -> Data {
        let deflated = try (data as NSData).compressed(using: .zlib) as Data
        var out = Data([0x1F, 0x8B, 8, 0, 0, 0, 0, 0, 2, 255])
        out.append(deflated)
        out.append(contentsOf: [0, 0, 0, 0]) // CRC (not checked)
        var size = UInt32(data.count).littleEndian
        out.append(Data(bytes: &size, count: 4))
        return out
    }

    private func cleanUp(_ root: URL, _ index: RoutingIndex) {
        RoutingData.removeAll(index)
        try? FileManager.default.removeItem(at: root)
    }

    @Test func tileGeometry() {
        let t = RoutingIndex.Tile(path: "2/000/818/663", bytes: 1, rawBytes: 1)
        #expect(t.level == 2 && t.size == 0.25 && t.lat == 52 && t.lon == 5.75)
        let base = RoutingIndex.Tile(path: "0/003/196", bytes: 1, rawBytes: 1)
        #expect(base.level == 0 && base.lat == 50 && base.lon == 4)
    }

    @Test func picksTheTilesAroundAPlan() throws {
        let (index, root) = try server()
        defer { cleanUp(root, index) }
        // Near Amersfoort (52.15°N 5.4°E): the level-1 and level-0 tiles, not the level-2 tile at 5.75°E.
        let near = RoutingData.tiles(around: [GeoPoint(lat: 52.15, lon: 5.4)], margin: 5_000, in: index)
        #expect(Set(near.map(\.path)) == ["1/051/305", "0/003/196"])
        let wide = RoutingData.tiles(around: [GeoPoint(lat: 52.15, lon: 5.4)], margin: 30_000, in: index)
        #expect(wide.count == 3)
    }

    @Test func downloadsDecompressesAndRemoves() async throws {
        let (index, root) = try server()
        defer { cleanUp(root, index) }
        #expect(RoutingData.downloadBytes(for: index.tiles, index: index) == index.tiles.reduce(0) { $0 + $1.bytes })

        let dir = try await RoutingData.download(index.tiles, index: index, from: root)
        let tile = try Data(contentsOf: dir.appending(path: "2/000/818/663.gph"))
        #expect(tile == Data(repeating: 2, count: 3000))
        #expect(RoutingData.downloadBytes(for: index.tiles, index: index) == 0)
        #expect(RoutingData.downloadedTiles(index).count == 3)

        RoutingData.remove([index.tiles[0]], index: index)
        #expect(RoutingData.downloadedTiles(index).count == 2)
        RoutingData.removeAll(index)
        #expect(RoutingData.downloadedTiles(index).isEmpty)
    }

    @Test func refusesDamagedTiles() async throws {
        let (index, root) = try server()
        defer { cleanUp(root, index) }
        try Self.gzip(Data(repeating: 9, count: 10)).write(to: root.appending(path: "download-test/v1/1/051/305.gph.gz"))
        await #expect(throws: RoutingError.self) { _ = try await RoutingData.download(index.tiles, index: index, from: root) }
    }

    @Test func aNewVersionReplacesTheOldTiles() async throws {
        let (v1, root1) = try server(version: 1)
        _ = try await RoutingData.download(v1.tiles, index: v1, from: root1)
        #expect(RoutingData.downloadedTiles(v1).count == 3)
        cleanUp(root1, v1)
        let (v1again, root2) = try server(version: 1)
        _ = try await RoutingData.download(v1again.tiles, index: v1again, from: root2)
        let (v2, root3) = try server(version: 2)
        defer { cleanUp(root2, v1again); cleanUp(root3, v2) }
        _ = try await RoutingData.download([v2.tiles[0]], index: v2, from: root3)
        #expect(RoutingData.downloadedTiles(v2).count == 1)
        #expect(RoutingData.downloadedTiles(v1again).isEmpty) // its folder was removed
    }

    @Test func indexDecodes() throws {
        let json = #"{"name":"west","version":2,"tiles":[["2/000/818/663",1200,3000]]}"#
        let index = try JSONDecoder().decode(RoutingIndex.self, from: Data(json.utf8))
        #expect(index.version == 2 && index.tiles == [.init(path: "2/000/818/663", bytes: 1200, rawBytes: 3000)])
    }

    @Test func gunzipsPythonsGzip() throws {
        // gzip.compress(b"tileroam", mtime=0)
        let python = Data([0x1f, 0x8b, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02, 0xff, 0x2b, 0xc9, 0xcc, 0x49, 0x2d,
                           0xca, 0x4f, 0xcc, 0x05, 0x00, 0x20, 0xdd, 0xaa, 0xb0, 0x08, 0x00, 0x00, 0x00])
        #expect(try Gzip.decompress(python) == Data("tileroam".utf8))
    }
}

struct RecentStartTests {
    private let utrecht = StartPoint(name: "Utrecht Centraal", lat: 52.0894, lon: 5.1101)

    @Test func newestFirstWithoutDuplicates() {
        let nearby = StartPoint(name: "Jaarbeursplein", lat: 52.0893, lon: 5.1095) // about 40 m away
        let arnhem = StartPoint(name: "Arnhem", lat: 51.9851, lon: 5.8987)
        var list = RecentStarts.adding(utrecht, to: [])
        list = RecentStarts.adding(arnhem, to: list)
        list = RecentStarts.adding(nearby, to: list)
        #expect(list.map(\.name) == ["Jaarbeursplein", "Arnhem"])
    }

    @Test func keepsTheLastFive() {
        var list = [StartPoint]()
        for i in 0..<8 { list = RecentStarts.adding(StartPoint(name: "\(i)", lat: 52 + Double(i) * 0.1, lon: 5), to: list) }
        #expect(list.map(\.name) == ["7", "6", "5", "4", "3"])
    }

    @Test func savesAndLoads() throws {
        let defaults = try #require(UserDefaults(suiteName: "RecentStartTests"))
        defer { defaults.removePersistentDomain(forName: "RecentStartTests") }
        #expect(RecentStarts.load(defaults).isEmpty)
        RecentStarts.save([utrecht], defaults)
        #expect(RecentStarts.load(defaults) == [utrecht])
    }
}

/// Answers tile requests from a script: each request takes the next answer.
final class ScriptedTileServer: URLProtocol, @unchecked Sendable {
    enum Answer { case data(Data), status(Int), failure(URLError.Code) }
    nonisolated(unsafe) static var answers = [Answer]()
    nonisolated(unsafe) static var requests = 0
    private static let lock = NSLock()

    static func session(_ answers: [Answer]) -> URLSession {
        lock.withLock { self.answers = answers; requests = 0 }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ScriptedTileServer.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        let answer: Answer = Self.lock.withLock {
            Self.requests += 1
            return Self.answers.isEmpty ? .status(500) : Self.answers.removeFirst()
        }
        switch answer {
        case .data(let data):
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                                cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case .status(let code):
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!,
                                cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        }
    }
}

@Suite(.serialized)
struct ResilientDownloadTests {
    private let raw = Data(repeating: 7, count: 500)
    private var index: RoutingIndex {
        RoutingIndex(name: "resilience-test", version: 1, tiles: [.init(path: "1/051/305", bytes: 100, rawBytes: 500)])
    }
    private let server = URL(string: "https://tiles.test")!

    @Test func retriesTimeoutsAndServerErrors() async throws {
        RoutingData.removeAll(index)
        defer { RoutingData.removeAll(index) }
        let session = ScriptedTileServer.session([.failure(.timedOut), .status(503), .data(try RoutingDownloadTests.gzip(raw))])
        let dir = try await RoutingData.download(index.tiles, index: index, from: server, session: session)
        #expect(ScriptedTileServer.requests == 3)
        #expect(try Data(contentsOf: dir.appending(path: "1/051/305.gph")) == raw)
    }

    @Test func givesUpAfterThreeTries() async throws {
        RoutingData.removeAll(index)
        defer { RoutingData.removeAll(index) }
        let session = ScriptedTileServer.session([.failure(.timedOut), .failure(.timedOut), .failure(.timedOut)])
        await #expect(throws: RoutingError.download(.timedOut)) {
            _ = try await RoutingData.download(index.tiles, index: index, from: server, session: session)
        }
        #expect(ScriptedTileServer.requests == 3)
    }

    @Test func doesNotRetryWhatWontChange() async throws {
        RoutingData.removeAll(index)
        defer { RoutingData.removeAll(index) }
        await #expect(throws: RoutingError.download(.server(404))) {
            _ = try await RoutingData.download(index.tiles, index: index, from: server, session: ScriptedTileServer.session([.status(404)]))
        }
        #expect(ScriptedTileServer.requests == 1)
        await #expect(throws: RoutingError.download(.offline)) {
            _ = try await RoutingData.download(index.tiles, index: index, from: server,
                                               session: ScriptedTileServer.session([.failure(.notConnectedToInternet)]))
        }
        #expect(ScriptedTileServer.requests == 1)
    }

    @Test func reportsProgress() async throws {
        RoutingData.removeAll(index)
        defer { RoutingData.removeAll(index) }
        let reports = Reports()
        _ = try await RoutingData.download(index.tiles, index: index, from: server,
                                           session: ScriptedTileServer.session([.data(try RoutingDownloadTests.gzip(raw))])) { done, total in
            await reports.add(done, total)
        }
        #expect(await reports.all == [[100, 100]])
    }

    actor Reports {
        var all = [[Int]]()
        func add(_ done: Int, _ total: Int) { all.append([done, total]) }
    }
}

struct RoutingCorridorTests {
    @Test func downloadsAlongTheRouteNotTheWholeBox() {
        // Two stops 2° apart diagonally; a level-2 tile on the line between them and one in the
        // far corner of the bounding box.
        let onLine = RoutingIndex.Tile(path: "2/000/818/663", bytes: 1, rawBytes: 1) // 52°N 5.75°E
        let corner = RoutingIndex.Tile(path: "2/000/822/978", bytes: 1, rawBytes: 1) // 52.75°N 4.5°E
        let index = RoutingIndex(name: "corridor", version: 1, tiles: [onLine, corner])
        #expect(corner.lat > 52.5 && corner.lon < 5) // north-west, away from the line
        let path = [GeoPoint(lat: 51.0, lon: 4.5), GeoPoint(lat: 53.0, lon: 7.0)]
        let picked = RoutingData.tiles(along: path, near: path, margin: 15_000, in: index)
        #expect(picked == [onLine])
    }

    @Test func tooLongRoundTripsAreCaughtFirst() {
        let utrecht = GeoPoint(lat: 52.09, lon: 5.12), munich = GeoPoint(lat: 48.14, lon: 11.58)
        let loop = [utrecht, munich, utrecht]
        #expect(RoutePlanner.length(loop) / 1000 > Double(RoutePlanner.maxLoopKilometers))
        // The distance as the device formats it ("1200", "1.200" or "1,200", depending on the language).
        #expect(RoutingError.tooLong(km: 1200).localizedDescription.contains(1200.formatted()))
    }

    @Test func explainsValhallaErrors() {
        // Each known Valhalla error gets its own explanation instead of the raw text (in any
        // language); unknown ones show the raw text.
        let known = ["Path distance exceeds the max distance limit", "No path could be found for input",
                     "No suitable edges near location"]
        let texts = known.map { RoutingError.engine($0).localizedDescription }
        #expect(Set(texts).count == 3)
        #expect(zip(known, texts).allSatisfy { !$1.contains($0) })
        #expect(RoutingError.engine("something new").localizedDescription.contains("something new"))
        #expect(RoutingError.engine("No path could be found for input").widerAreaMayHelp)
        #expect(!RoutingError.engine("Path distance exceeds the max distance limit").widerAreaMayHelp)
        #expect(!RoutingError.engine("No suitable edges near location").widerAreaMayHelp)
        #expect(!RoutingError.download(.timedOut).widerAreaMayHelp)
    }
}
