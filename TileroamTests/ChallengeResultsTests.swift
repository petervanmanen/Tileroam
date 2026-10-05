import Foundation
import Testing
@testable import Tileroam

struct ChallengeResultsTests {
    private let westmalle = Trappist(id: "westmalle", name: "Westmalle", abbey: "Abdij", place: "Westmalle", country: "BE",
                                     lat: 51.28472, lon: 4.65667)

    private func ride(_ points: [GeoPoint]) -> Activity {
        Importer.makeActivity(points: points, id: UUID().uuidString, cacheKey: "", name: "Ride", sport: "Cycling",
                              startDate: .now, distance: nil)
    }

    @Test func keysFollowTheListsAndRules() {
        let a = ChallengeResults.trappistsKey([westmalle])
        #expect(a == ChallengeResults.trappistsKey([westmalle])) // stable
        #expect(a != ChallengeResults.trappistsKey([]))           // another list
        #expect(a.hasPrefix("t\(TrappistMatcher.version)-"))      // a new version changes it
        #expect(ChallengeResults.klompenpadKey([]).hasPrefix("k\(KlompenpadMatcher.version)-"))
        #expect(ChallengeResults.countriesKey.hasPrefix("c\(CountryOutlines.worldVersion)-"))
    }

    @Test func storedResultsEndPending() {
        let track = [GeoPoint(lat: 51.28472, lon: 4.64), GeoPoint(lat: 51.28472, lon: 4.67)]
        var a = ride(track)
        let tKey = ChallengeResults.trappistsKey([westmalle]), kKey = ChallengeResults.klompenpadKey([])
        #expect(ChallengeResults.isPending(a, trappistsKey: tKey, klompenpadKey: kKey))
        let r = ChallengeResults.compute(a, trappists: [westmalle], trappistsKey: tKey, paths: .init([]), klompenpadKey: kKey)
        #expect(r.trappists == ["westmalle"])
        #expect(r.countries == ["BE"])
        a.trappists = r.trappists; a.trappistsKey = tKey
        a.klompenpadHits = r.klompenpadHits; a.klompenpadKey = kKey
        a.countries = r.countries; a.countriesKey = ChallengeResults.countriesKey
        #expect(!ChallengeResults.isPending(a, trappistsKey: tKey, klompenpadKey: kKey))
        // A new brewery list makes it pending again; only that part is computed.
        let newKey = ChallengeResults.trappistsKey([])
        #expect(ChallengeResults.isPending(a, trappistsKey: newKey, klompenpadKey: kKey))
        let again = ChallengeResults.compute(a, trappists: [], trappistsKey: newKey, paths: .init([]), klompenpadKey: kKey)
        #expect(again.trappists == [] && again.klompenpadHits == nil && again.countries == nil)
    }

    @Test func klompenpadProgressAddsUpStoredHits() {
        let counts = ["a": 10, "b": 4]
        // Two walks over parts of path a (overlapping), one over b; "gone" is no longer in the list.
        let progress = KlompenpadMatcher.progress(hits: [["a": [0, 1, 2, 3]], ["a": [3, 4, 5], "b": [0, 1, 2, 3]], ["gone": [0]]],
                                                  counts: counts)
        #expect(progress == ["a": 0.6, "b": 1.0])
        // Without the second walk (deleted), a drops back.
        #expect(KlompenpadMatcher.progress(hits: [["a": [0, 1, 2, 3]]], counts: counts) == ["a": 0.4])
    }
}
