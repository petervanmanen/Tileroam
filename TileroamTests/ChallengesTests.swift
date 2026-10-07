import Foundation
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

struct CustomModeTests {
    @Test func customModesRoundTrip() {
        #expect(MapMode(rawValue: "custom:trappist-breweries") == .custom("trappist-breweries"))
        #expect(MapMode.custom("ferries").rawValue == "custom:ferries")
        #expect(MapMode(rawValue: "custom:Not Valid") == nil)
        // The built-in modes of 1.12 and earlier no longer decode.
        #expect(MapMode(rawValue: "trappists") == nil && MapMode(rawValue: "mtb") == nil)
    }

    @Test func visibleModesKeepOnlyExistingChallenges() {
        let raw = Challenges.encode([.custom("b"), .gemeenten, .custom("a")])
        #expect(raw == "gemeenten,custom:a,custom:b")
        #expect(Challenges.visibleModes(raw, custom: ["b", "c"]) == [.squares, .gemeenten, .custom("b")])
    }

    @Test func newChallengesAreTurnedOnOnce() throws {
        let defaults = try #require(UserDefaults(suiteName: "CustomModeTests"))
        defaults.removePersistentDomain(forName: "CustomModeTests")
        defaults.set("climbs", forKey: Challenges.key)
        Challenges.turnOnNew(["a"], defaults: defaults)
        #expect(Challenges.decode(defaults.string(forKey: Challenges.key) ?? "") == [.climbs, .custom("a")])
        // Turned off by the user: stays off.
        defaults.set("climbs", forKey: Challenges.key)
        Challenges.turnOnNew(["a", "b"], defaults: defaults)
        #expect(Challenges.decode(defaults.string(forKey: Challenges.key) ?? "") == [.climbs, .custom("b")])
    }
}
