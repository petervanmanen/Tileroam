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
