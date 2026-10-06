import Foundation
import Testing
@testable import Tileroam

struct KlompenpadTests {
    /// The list in the repository (AssetPacks/Klompenpaden), as packaged in the asset pack.
    static let source = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "AssetPacks/Klompenpaden")

    /// A 2 km path going east from 52.0°N 5.6°E.
    private let path: Klompenpad = {
        let points = (0...40).map { GeoPoint(lat: 52.0, lon: 5.6 + Double($0) * 0.000_73) }
        return Klompenpad(id: "test", name: "Testpad", start: "Ede", lengths: [2, 5.5], url: "https://www.klompenpaden.nl",
                          lat: 52.0, lon: 5.6, length: 2_000, lines: [ClimbMatcherTests.encode(points)])
    }()

    private func walk(_ points: [GeoPoint]) -> Activity {
        Importer.makeActivity(points: points, id: UUID().uuidString, cacheKey: "", name: "Walk", sport: "Walking",
                              startDate: .now, distance: nil)
    }

    @Test func repositoryList() throws {
        let list = try JSONDecoder().decode([Klompenpad].self, from: Data(contentsOf: Self.source.appending(path: "klompenpaden.json")))
        #expect(list.count == 167)
        #expect(Set(list.map(\.id)).count == list.count)
        #expect(list.allSatisfy { !$0.pieces.isEmpty && $0.pieces.allSatisfy { $0.count >= 2 } && $0.link != nil })
        // The main route's length matches one of the path's lengths roughly.
        let aalderpad = try #require(list.first { $0.name == "Aalderpad" })
        #expect(aalderpad.lengths == [9, 12, 14] && (9_000...15_000).contains(aalderpad.length))
    }

    @Test func walkedWhole() {
        let ride = (0...40).map { GeoPoint(lat: 52.0001, lon: 5.6 + Double($0) * 0.000_73) } // 11 m beside it
        let progress = KlompenpadMatcher.progress([walk(ride)], paths: [path])
        #expect((progress["test"] ?? 0) >= KlompenpadMatcher.done)
    }

    @Test func halfOverTwoWalks() {
        let first = (0...10).map { GeoPoint(lat: 52.0, lon: 5.6 + Double($0) * 0.000_73) }
        let second = (10...20).map { GeoPoint(lat: 52.0, lon: 5.6 + Double($0) * 0.000_73) }
        let one = KlompenpadMatcher.progress([walk(first)], paths: [path])["test"] ?? 0
        let both = KlompenpadMatcher.progress([walk(first), walk(second)], paths: [path])["test"] ?? 0
        #expect((0.2...0.3).contains(one))
        #expect((0.45...0.55).contains(both)) // walks add up
    }

    @Test func notOnAParallelRoad() {
        let road = (0...40).map { GeoPoint(lat: 52.0009, lon: 5.6 + Double($0) * 0.000_73) } // 100 m away
        #expect(KlompenpadMatcher.progress([walk(road)], paths: [path]).isEmpty)
    }

    @Test func lengthsText() {
        #expect(path.lengthsText == "2, 5.5 km" || path.lengthsText == "2, 5,5 km")
    }

    @Test func readsTheListFromALocalFile() {
        // In the app it comes from the asset pack; Debug builds can read a file instead.
        UserDefaults.standard.set(Self.source.appending(path: "klompenpaden.json").path(percentEncoded: false), forKey: "KlompenpadenFile")
        defer { UserDefaults.standard.removeObject(forKey: "KlompenpadenFile") }
        #expect(KlompenpadData.cached().count == 167)
    }

    @Test func challengeIsOffByDefault() {
        #expect(MapMode.klompenpaden.isChallenge)
        #expect(!Challenges.visibleModes("").contains(.klompenpaden))
    }
}

struct MTBRouteTests {
    static let source = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "AssetPacks/MTB/mtb-routes.json")

    @Test func repositoryList() throws {
        let list = try JSONDecoder().decode([MTBRoute].self, from: Data(contentsOf: Self.source))
        #expect(list.count > 4_000)
        #expect(Set(list.map(\.id)).count == list.count)
        #expect(list.allSatisfy { !$0.pieces.isEmpty && $0.link != nil && $0.length >= 1_000 })
        #expect(Set(list.map(\.country)) == ["NL", "BE", "DE", "FR", "CH", "AT"]) // Luxembourg has none signposted
    }

    @Test func challengeIsOffByDefault() {
        #expect(MapMode.mtb.isChallenge)
        #expect(!Challenges.visibleModes("").contains(.mtb))
    }
}
