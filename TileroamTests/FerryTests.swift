import Foundation
import Testing
@testable import Tileroam

struct FerryTests {
    /// A 300 m crossing going north at 51.95°N 5.22°E (like a pontje over the Lek).
    private let ferry: Ferry = {
        let line = [GeoPoint(lat: 51.9500, lon: 5.22), GeoPoint(lat: 51.9527, lon: 5.22)]
        return Ferry(id: "osm-1", ownName: nil, from: "Lexmond", to: "Culemborg", operator: nil, website: nil, country: "NL",
                     length: 300, lat: 51.95135, lon: 5.22, line: ClimbMatcherTests.encode(line))
    }()

    @Test func crossingCounts() {
        // From 500 m south of the landing, across, to 500 m north.
        let ride = [GeoPoint(lat: 51.9455, lon: 5.2201), GeoPoint(lat: 51.9500, lon: 5.2201),
                    GeoPoint(lat: 51.9527, lon: 5.2199), GeoPoint(lat: 51.9572, lon: 5.2199)]
        #expect(FerryMatcher.crossed(by: ride, among: [ferry]) == ["osm-1"])
    }

    @Test func ridingAlongTheBankDoesNot() {
        // East to west along the south bank, past the landing.
        let ride = [GeoPoint(lat: 51.9499, lon: 5.20), GeoPoint(lat: 51.9499, lon: 5.24)]
        #expect(FerryMatcher.crossed(by: ride, among: [ferry]).isEmpty)
        // To the landing and back.
        let back = [GeoPoint(lat: 51.9455, lon: 5.22), GeoPoint(lat: 51.9500, lon: 5.22), GeoPoint(lat: 51.9455, lon: 5.22)]
        #expect(FerryMatcher.crossed(by: back, among: [ferry]).isEmpty)
    }

    @Test func shortPontjeNeedsACrossing() {
        // A 36 m pontje over a ditch: riding along the bank 10 m away doesn't count, crossing does.
        let line = [GeoPoint(lat: 52.0, lon: 5.0), GeoPoint(lat: 52.000324, lon: 5.0)]
        let pontje = Ferry(id: "osm-3", ownName: nil, from: nil, to: nil, operator: nil, website: nil, country: "NL",
                           length: 36, lat: 52.000162, lon: 5.0, line: ClimbMatcherTests.encode(line))
        let bank = [GeoPoint(lat: 51.99991, lon: 4.999), GeoPoint(lat: 51.99991, lon: 5.001)]
        #expect(FerryMatcher.crossed(by: bank, among: [pontje]).isEmpty)
        let across = [GeoPoint(lat: 51.9995, lon: 5.0), GeoPoint(lat: 52.0008, lon: 5.0)]
        #expect(FerryMatcher.crossed(by: across, among: [pontje]) == ["osm-3"])
    }

    @Test func nameFallsBackToThePlaces() {
        #expect(ferry.name == "Lexmond – Culemborg")
        let named = Ferry(id: "osm-2", ownName: "Pont Vianen", from: "A", to: "B", operator: nil, website: nil, country: "NL",
                          length: 200, lat: 52, lon: 5, line: "")
        #expect(named.name == "Pont Vianen")
    }

    @Test func repositoryData() throws {
        let file = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "AssetPacks/Ferries/ferries.json")
        let list = try JSONDecoder().decode([Ferry].self, from: Data(contentsOf: file))
        #expect(list.count > 500)
        #expect(Set(list.map(\.id)).count == list.count)
        #expect(Set(list.map(\.country)).isSuperset(of: ["NL", "DE"]))
        #expect(list.allSatisfy { $0.length >= 30 && $0.length <= 2_000 && $0.points.count >= 2 })
    }

    @Test func challengeIsOffByDefault() {
        #expect(MapMode.ferries.isChallenge)
        #expect(!Challenges.visibleModes("").contains(.ferries))
    }
}
