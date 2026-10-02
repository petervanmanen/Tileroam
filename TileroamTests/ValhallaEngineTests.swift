import Foundation
import Testing
@testable import Tileroam

/// Runs Valhalla in the simulator on the Luxembourg test build that
/// `Tools/build_routing_tiles.sh lu-test luxembourg` writes to AssetPacks/build/routing (not in Git,
/// so these tests are skipped where it is missing).
private let routingBuild: URL? = {
    let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    let dir = root.appending(path: "AssetPacks/build/routing", directoryHint: .isDirectory)
    return FileManager.default.fileExists(atPath: dir.appending(path: "routing-lu-test.tar").path(percentEncoded: false)) ? dir : nil
}()

@Suite(.serialized, .enabled(if: routingBuild != nil))
struct ValhallaEngineTests {
    static let luxembourg = GeoPoint(lat: 49.6116, lon: 6.1319)
    static let bertrange = GeoPoint(lat: 49.6111, lon: 6.0500)

    private func useTileExtract() {
        UserDefaults.standard.removeObject(forKey: "RoutingPacksDir")
        UserDefaults.standard.set(routingBuild!.appending(path: "routing-lu-test.tar").path(percentEncoded: false), forKey: "RoutingTar")
    }

    @Test func routesThroughLuxembourg() async throws {
        useTileExtract()
        let router = ValhallaRouter()
        try await router.prepare(around: [Self.luxembourg, Self.bertrange], margin: 15_000)
        let r = try await router.route([Self.luxembourg, Self.bertrange])
        #expect((6000...9000).contains(r.distance)) // Luxembourg → Bertrange, about 7 km by bike
        #expect(r.coordinates.count > 50)
        #expect(r.snapped.count == 2)
    }

    @Test func ordersARoundTrip() async throws {
        let router = ValhallaRouter()
        let points = [Self.luxembourg, Self.bertrange, GeoPoint(lat: 49.5950, lon: 6.1000), GeoPoint(lat: 49.6300, lon: 6.0800)]
        let order = try await router.tripOrder(points)
        #expect(order.first == 0)
        #expect(Set(order) == [0, 1, 2, 3])
    }

    @Test func routesFromAreaPacks() async throws {
        // The production path: only the needed 1° area packs, linked into a tile directory.
        UserDefaults.standard.removeObject(forKey: "RoutingTar")
        UserDefaults.standard.set(routingBuild!.appending(path: "packs-lu-test").path(percentEncoded: false), forKey: "RoutingPacksDir")
        defer { UserDefaults.standard.removeObject(forKey: "RoutingPacksDir") }
        let index = try JSONDecoder().decode(RoutingIndex.self,
                                             from: Data(contentsOf: routingBuild!.appending(path: "routing-lu-test.json")))

        let areas = RoutingData.packs(around: [Self.luxembourg, Self.bertrange], margin: 15_000, in: index)
        // Bertrange is at 6.05°E, so 15 km of room for detours reaches the area west of 6°E too.
        #expect(areas.map(\.pack) == ["routing-lu-test-n49e005", "routing-lu-test-n49e006"])
        #expect(RoutingData.packs(around: [GeoPoint(lat: 49.6, lon: 6.5)], margin: 5_000, in: index).map(\.pack)
                == ["routing-lu-test-n49e006"])
        #expect(RoutingData.packs(around: [Self.luxembourg], margin: 60_000, in: index).count == 4)

        let router = ValhallaRouter()
        try await router.prepare(around: [Self.luxembourg, Self.bertrange], margin: 15_000, index: index)
        let r = try await router.route([Self.luxembourg, Self.bertrange])
        #expect((6000...9000).contains(r.distance))
    }
}
