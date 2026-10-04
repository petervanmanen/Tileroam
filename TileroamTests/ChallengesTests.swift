import Testing
@testable import Tileroam

struct ChallengesTests {
    @Test func offByDefault() {
        #expect(Challenges.decode("").isEmpty)
        #expect(Challenges.visibleModes("") == [.squares])
    }

    @Test func turnedOnChallengesFollowTiles() {
        let raw = Challenges.encode([.climbs, .gemeenten])
        #expect(raw == "gemeenten,climbs")
        #expect(Challenges.visibleModes(raw) == [.squares, .gemeenten, .climbs])
    }

    @Test func ignoresUnknownAndNonChallengeModes() {
        // "activities" was the Routes mode, removed in 1.5.3.
        #expect(Challenges.decode("postcodes,squares,activities,bogus,") == [.postcodes])
        #expect(MapMode.squares.isChallenge == false && MapMode.climbs.isChallenge)
        #expect(MapMode(rawValue: "activities") == nil)
    }
}
