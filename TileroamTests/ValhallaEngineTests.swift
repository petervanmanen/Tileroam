import Foundation
import Testing
@testable import Tileroam

/// Runs Valhalla in the simulator on the Luxembourg test build that
/// `ROUTING_COUNTRIES=LU Tools/build_routing_tiles.sh lu-test luxembourg` writes to
/// AssetPacks/build/routing (not in Git, so these tests are skipped where it is missing).
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
        UserDefaults.standard.removeObject(forKey: "RoutingServer")
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
        let order = try await router.tripOrder(points, end: nil)
        #expect(order.first == 0)
        #expect(Set(order) == [0, 1, 2, 3])
    }

    @Test func routesFromDownloadedTiles() async throws {
        // The production path: only the tiles around the plan, downloaded (here from the local copy
        // of what goes to R2, AssetPacks/build/routing/r2) and decompressed into a tile directory.
        UserDefaults.standard.removeObject(forKey: "RoutingTar")
        UserDefaults.standard.set(routingBuild!.appending(path: "r2", directoryHint: .isDirectory).absoluteString, forKey: "RoutingServer")
        defer { UserDefaults.standard.removeObject(forKey: "RoutingServer") }
        let index = try JSONDecoder().decode(RoutingIndex.self,
                                             from: Data(contentsOf: routingBuild!.appending(path: "routing-lu-test.json")))
        RoutingData.removeAll(index)

        let tiles = RoutingData.tiles(around: [Self.luxembourg, Self.bertrange], margin: 15_000, in: index)
        #expect(Set(tiles.map(\.level)) == [0, 1, 2])
        #expect(tiles.count < index.tiles.count / 2) // only the surroundings

        let router = ValhallaRouter()
        try await router.prepare(around: [Self.luxembourg, Self.bertrange], margin: 15_000, index: index)
        let r = try await router.route([Self.luxembourg, Self.bertrange])
        #expect((6000...9000).contains(r.distance))
        #expect(RoutingData.downloadedTiles(index).count == tiles.count)
        RoutingData.removeAll(index)
    }

    @Test func plansARoundTripFromAChosenStart() async throws {
        // A chosen starting point (Bertrange) instead of the current location: the round trip
        // begins and ends there and passes the selected tile in Luxembourg City.
        useTileExtract()
        let start = StartPoint(name: "Bertrange", Self.bertrange)
        let key = try #require(TileGrid.key(lat: Self.luxembourg.lat, lon: Self.luxembourg.lon, zoom: .explorer))
        let target = try #require(TargetGeometry(.tile(.explorer, key), regions: nil))
        let router = ValhallaRouter()
        try await router.prepare(around: [start.point] + target.candidates(), margin: 15_000)
        let route = try await RoutePlanner.planRoute(
            start: start.point, targets: [target], client: router,
            coverage: { RouteCoverage(route: $0, visitedTiles14: [], visitedMunicipalities: [],
                                      visitedPostcodes: [], regions: nil) },
            progress: { _ in })
        let first = try #require(route.coordinates.first), last = try #require(route.coordinates.last)
        #expect(Geo.distance(first, start.point) < 300)
        #expect(Geo.distance(last, start.point) < 300)
        #expect(route.missed.isEmpty)
        #expect((8_000...25_000).contains(route.distance))
    }

    /// The west build: routes cross the Dutch–German border. In this suite, because both change
    /// the global RoutingTar/RoutingServer settings and must not run at the same time.
    @Test(.enabled(if: westBuild != nil)) func routesAcrossTheGermanBorder() async throws {
        UserDefaults.standard.removeObject(forKey: "RoutingServer")
        UserDefaults.standard.set(westBuild!.path(percentEncoded: false), forKey: "RoutingTar")
        defer { UserDefaults.standard.removeObject(forKey: "RoutingTar") }
        let kerkrade = GeoPoint(lat: 50.8657, lon: 6.0628), aachen = GeoPoint(lat: 50.7753, lon: 6.0839)
        #expect(RoutingData.covers(kerkrade) && RoutingData.covers(aachen))
        let router = ValhallaRouter()
        try await router.prepare(around: [kerkrade, aachen], margin: 15_000)
        let r = try await router.route([kerkrade, aachen])
        #expect((9_000...20_000).contains(r.distance)) // about 12 km by bike
    }

    @Test(.enabled(if: westBuild != nil)) func routesAcrossFrenchSwissAndAustrianBorders() async throws {
        UserDefaults.standard.removeObject(forKey: "RoutingServer")
        UserDefaults.standard.set(westBuild!.path(percentEncoded: false), forKey: "RoutingTar")
        defer { UserDefaults.standard.removeObject(forKey: "RoutingTar") }
        // Saint-Louis (FR) → Basel (CH) → Weil am Rhein (DE), and Lindau (DE) → Bregenz (AT).
        let saintLouis = GeoPoint(lat: 47.5900, lon: 7.5600), basel = GeoPoint(lat: 47.5596, lon: 7.5886)
        let weil = GeoPoint(lat: 47.5947, lon: 7.6110)
        let lindau = GeoPoint(lat: 47.5460, lon: 9.6840), bregenz = GeoPoint(lat: 47.5031, lon: 9.7471)
        #expect([saintLouis, basel, weil, lindau, bregenz].allSatisfy(RoutingData.covers))
        let router = ValhallaRouter()
        try await router.prepare(around: [saintLouis, basel, weil], margin: 10_000)
        let tri = try await router.route([saintLouis, basel, weil])
        #expect((4_000...15_000).contains(tri.distance))
        try await router.prepare(around: [lindau, bregenz], margin: 10_000)
        let lake = try await router.route([lindau, bregenz])
        #expect((6_000...16_000).contains(lake.distance)) // about 9 km along the lake
    }
}

/// The production build (Tools/build_routing_tiles.sh west …, not in Git): checks that routes cross
/// borders, which needs the countries in one build.
private let westBuild: URL? = {
    let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    let tar = root.appending(path: "AssetPacks/build/routing/routing-west.tar")
    return FileManager.default.fileExists(atPath: tar.path(percentEncoded: false)) ? tar : nil
}()
