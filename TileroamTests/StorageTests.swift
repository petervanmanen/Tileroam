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
struct RoutingStorageTests {
    /// A tiny index with two areas, its "downloaded" files in a temporary folder.
    private func fixture() throws -> (RoutingIndex, URL) {
        let index = RoutingIndex(
            name: "storage-test", base: "routing-storage-test-base",
            areas: [
                .init(pack: "routing-storage-test-n52e005", lat: 52, lon: 5, bytes: 100_000_000, files: ["2/000/001/001.gph"]),
                .init(pack: "routing-storage-test-n51e005", lat: 51, lon: 5, bytes: 50_000_000, files: ["2/000/001/002.gph"]),
            ],
            baseFiles: ["0/000/001.gph"], baseBytes: 10_000_000)
        let packs = FileManager.default.temporaryDirectory.appending(path: "storage-test-\(UUID())")
        for file in index.baseFiles + index.areas.flatMap(\.files) {
            let url = packs.appending(path: file)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data([1]).write(to: url)
        }
        try? FileManager.default.removeItem(at: RoutingData.tileDirectory(index))
        return (index, packs)
    }

    /// Links a pack's files into the tile directory, as RoutingData.tileDirectory does after a download.
    private func link(_ files: [String], from packs: URL, index: RoutingIndex) throws {
        for file in files {
            let link = RoutingData.tileDirectory(index).appending(path: file)
            try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: packs.appending(path: file))
        }
    }

    @Test func downloadedAreasAndRemoval() async throws {
        UserDefaults.standard.removeObject(forKey: "RoutingPacksDir")
        let (index, packs) = try fixture()
        defer { try? FileManager.default.removeItem(at: packs) }
        let utrecht = index.areas[0], eindhoven = index.areas[1]

        // Nothing downloaded: both areas and the base count (at 40%, compressed).
        #expect(!RoutingData.isDownloaded(utrecht, index: index))
        #expect(RoutingData.downloadBytes(for: [utrecht], index: index) == 44_000_000)

        // After "downloading" Utrecht and the base, only Eindhoven is left.
        try link(utrecht.files + index.baseFiles, from: packs, index: index)
        #expect(RoutingData.isDownloaded(utrecht, index: index))
        #expect(RoutingData.isBaseDownloaded(index))
        #expect(RoutingData.downloadBytes(for: [utrecht], index: index) == 0)
        #expect(RoutingData.downloadBytes(for: [utrecht, eindhoven], index: index) == 20_000_000)

        // Removing Utrecht removes its links (the pack removal is skipped in this test).
        UserDefaults.standard.set(packs.path(percentEncoded: false), forKey: "RoutingPacksDir")
        await RoutingData.remove([utrecht], includingBase: false, index: index)
        UserDefaults.standard.removeObject(forKey: "RoutingPacksDir")
        #expect(!RoutingData.isDownloaded(utrecht, index: index))
        #expect(RoutingData.isBaseDownloaded(index))
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

struct RoutingVersionTests {
    @Test func decidesWhenToReplaceTheData() {
        // Fresh device, packs of the index's version.
        #expect(RoutingData.versionCheck(packs: [2, 2], linked: nil, indexVersion: 2) == .consistent(2))
        // Packs from before versions existed (version 1), on a version-1 index.
        #expect(RoutingData.versionCheck(packs: [1], linked: 1, indexVersion: 1) == .consistent(1))
        // New data uploaded, app not updated yet: newer packs alone are fine...
        #expect(RoutingData.versionCheck(packs: [2], linked: nil, indexVersion: 1) == .consistent(2))
        // ...but not next to older links: replace everything.
        #expect(RoutingData.versionCheck(packs: [2], linked: 1, indexVersion: 1) == .refresh)
        #expect(RoutingData.versionCheck(packs: [1, 2], linked: nil, indexVersion: 1) == .refresh)
        // App updated to a newer index while the device still has older data.
        #expect(RoutingData.versionCheck(packs: [1], linked: 1, indexVersion: 2) == .refresh)
    }

    @Test func indexWithoutVersionIsVersionOne() throws {
        let old = #"{"name":"t","base":"routing-t-base","areas":[],"baseFiles":[],"baseBytes":0}"#
        #expect(try JSONDecoder().decode(RoutingIndex.self, from: Data(old.utf8)).version == 1)
        let new = #"{"name":"t","version":3,"base":"routing-t-base","areas":[],"baseFiles":[],"baseBytes":0}"#
        #expect(try JSONDecoder().decode(RoutingIndex.self, from: Data(new.utf8)).version == 3)
    }
}

@Suite(.serialized)
struct RoutingVersionLinkTests {
    /// Staged packs as Tools/split_routing_tiles.py writes them (the simulator's -RoutingPacksDir),
    /// with the given versions (nil: no version file, as before versions existed).
    private func stage(base: Int?, area: Int?) throws -> (RoutingIndex, URL) {
        let root = FileManager.default.temporaryDirectory.appending(path: "versions-\(UUID())")
        let index = RoutingIndex(name: "version-test", version: 2, base: "routing-version-test-base",
                                 areas: [.init(pack: "routing-version-test-n52e005", lat: 52, lon: 5, bytes: 1, files: ["1/051/305.gph"])],
                                 baseFiles: ["0/003/195.gph"], baseBytes: 1)
        for (pack, file, version) in [(index.base, index.baseFiles[0], base), (index.areas[0].pack, index.areas[0].files[0], area)] {
            let tile = root.appending(path: "\(pack)/\(file)")
            try FileManager.default.createDirectory(at: tile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data([1]).write(to: tile)
            if let version {
                let marker = root.appending(path: "\(pack)/version/\(pack)")
                try FileManager.default.createDirectory(at: marker.deletingLastPathComponent(), withIntermediateDirectories: true)
                try String(version).write(to: marker, atomically: true, encoding: .utf8)
            }
        }
        try? FileManager.default.removeItem(at: RoutingData.tileDirectory(index))
        UserDefaults.standard.set(root.path(percentEncoded: false), forKey: "RoutingPacksDir")
        return (index, root)
    }

    @Test func linksPacksOfOneVersion() async throws {
        let (index, root) = try stage(base: 2, area: 2)
        defer { UserDefaults.standard.removeObject(forKey: "RoutingPacksDir"); try? FileManager.default.removeItem(at: root) }
        let (dir, replaced) = try await RoutingData.tileDirectory(for: index.areas, index: index)
        #expect(!replaced)
        #expect(FileManager.default.fileExists(atPath: dir.appending(path: "1/051/305.gph").path(percentEncoded: false)))
        #expect(RoutingData.linkedVersion(index) == 2)
    }

    @Test func refusesMixedVersions() async throws {
        // A version-2 base next to an area from before versions existed: they don't connect, and
        // here (staged packs can't be updated) they stay mixed, so planning must not use them.
        let (index, root) = try stage(base: 2, area: nil)
        defer { UserDefaults.standard.removeObject(forKey: "RoutingPacksDir"); try? FileManager.default.removeItem(at: root) }
        await #expect(throws: RoutingError.self) {
            _ = try await RoutingData.tileDirectory(for: index.areas, index: index)
        }
    }
}
