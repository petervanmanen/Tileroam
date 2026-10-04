import Testing
@testable import Tileroam

struct ChallengesTests {
    @Test func offByDefault() {
        #expect(Challenges.decode("").isEmpty)
        #expect(Challenges.visibleModes("", planning: false) == [.squares, .activities])
    }

    @Test func turnedOnChallengesFollowTilesAndRoutes() {
        let raw = Challenges.encode([.climbs, .gemeenten])
        #expect(raw == "gemeenten,climbs")
        #expect(Challenges.visibleModes(raw, planning: false) == [.squares, .activities, .gemeenten, .climbs])
        // Planning has no Routes tab.
        #expect(Challenges.visibleModes(raw, planning: true) == [.squares, .gemeenten, .climbs])
    }

    @Test func ignoresUnknownAndNonChallengeModes() {
        #expect(Challenges.decode("postcodes,squares,activities,bogus,") == [.postcodes])
        #expect(MapMode.squares.isChallenge == false && MapMode.climbs.isChallenge)
    }
}
