import Foundation
import Testing
@testable import Tileroam

struct TrappistTests {
    private let westmalle = Trappist(id: "westmalle", name: "Westmalle", abbey: "Abdij", place: "Westmalle", country: "BE",
                                     lat: 51.28472, lon: 4.65667)

    @Test func bundledBreweries() {
        #expect(Trappist.all.count == 8)
        #expect(Trappist.all.allSatisfy { $0.icon != nil })
        #expect(Set(Trappist.all.map(\.id)).count == Trappist.all.count)
    }

    @Test func passingWithin200Metres() {
        // A ride 150 m north of the brewery, east to west.
        let north = 150.0 / 111_000
        let ride = [GeoPoint(lat: 51.28472 + north, lon: 4.64), GeoPoint(lat: 51.28472 + north, lon: 4.67)]
        #expect(TrappistMatcher.visited(by: ride, among: [westmalle]) == ["westmalle"])
    }

    @Test func sparseTrackCountsBetweenItsPoints() {
        // Two points 2 km apart on either side of the brewery: the line between them passes it.
        let ride = [GeoPoint(lat: 51.28472, lon: 4.64), GeoPoint(lat: 51.28472, lon: 4.67)]
        #expect(TrappistMatcher.visited(by: ride, among: [westmalle]) == ["westmalle"])
    }

    @Test func notWhenFurtherAway() {
        let north = 300.0 / 111_000
        let ride = [GeoPoint(lat: 51.28472 + north, lon: 4.64), GeoPoint(lat: 51.28472 + north, lon: 4.67)]
        #expect(TrappistMatcher.visited(by: ride, among: [westmalle]).isEmpty)
        #expect(TrappistMatcher.visited(by: [], among: [westmalle]).isEmpty)
    }

    @Test func segmentDistance() {
        let p = GeoPoint(lat: 51, lon: 5)
        let a = GeoPoint(lat: 51.001, lon: 4.99), b = GeoPoint(lat: 51.001, lon: 5.01)
        #expect(abs(TrappistMatcher.distance(from: p, toSegment: a, b) - 110.6) < 1)
        // Beyond the segment's end: the distance to that end.
        let c = GeoPoint(lat: 51, lon: 5.01), d = GeoPoint(lat: 51, lon: 5.02)
        #expect(abs(TrappistMatcher.distance(from: p, toSegment: c, d) - Geo.distance(p, c)) < 2)
    }

    @Test func challengeIsOffByDefault() {
        #expect(MapMode.trappists.isChallenge)
        #expect(!Challenges.visibleModes("").contains(.trappists))
    }
}
