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
