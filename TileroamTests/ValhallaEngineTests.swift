import Foundation
import Testing
@testable import Tileroam

/// Runs Valhalla in the simulator on the Luxembourg tiles that Tools/build_routing_tiles.sh writes to
/// AssetPacks/build/routing (not in Git, so these tests are skipped where the file is missing).
private let luxembourgTiles: URL? = {
    let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    let url = root.appending(path: "AssetPacks/build/routing/routing-lu-test.tar")
    return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
}()

@Suite(.serialized, .enabled(if: luxembourgTiles != nil))
struct ValhallaEngineTests {
    init() {
        UserDefaults.standard.set(luxembourgTiles!.path(percentEncoded: false), forKey: "RoutingTar")
    }

    @Test func routesThroughLuxembourg() async throws {
        let router = ValhallaRouter()
        let r = try await router.route([GeoPoint(lat: 49.6116, lon: 6.1319), GeoPoint(lat: 49.6111, lon: 6.0500)])
        #expect((6000...9000).contains(r.distance)) // Luxembourg → Bertrange, about 7 km by bike
        #expect(r.coordinates.count > 50)
        #expect(r.snapped.count == 2)
    }

    @Test func ordersARoundTrip() async throws {
        let router = ValhallaRouter()
        let points = [GeoPoint(lat: 49.6116, lon: 6.1319), GeoPoint(lat: 49.6111, lon: 6.0500),
                      GeoPoint(lat: 49.5950, lon: 6.1000), GeoPoint(lat: 49.6300, lon: 6.0800)]
        let order = try await router.tripOrder(points)
        #expect(order.first == 0)
        #expect(Set(order) == [0, 1, 2, 3])
    }
}
