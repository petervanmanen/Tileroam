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
        #expect(ChallengeResults.boscafesKey([]).hasPrefix("b\(TrappistMatcher.version)-"))
        #expect(ChallengeResults.klompenpadKey([]).hasPrefix("k\(KlompenpadMatcher.version)-"))
        #expect(ChallengeResults.countriesKey.hasPrefix("c\(CountryOutlines.worldVersion)-"))
    }

    private func current(_ trappists: [Trappist], boscafes: [Boscafe] = [], mtb: [MTBRoute] = []) -> ChallengeResults.Current {
        ChallengeResults.Current(trappists: trappists, trappistsKey: ChallengeResults.trappistsKey(trappists),
                                 boscafes: boscafes, boscafesKey: ChallengeResults.boscafesKey(boscafes),
                                 paths: .init([Klompenpad]()), klompenpadKey: ChallengeResults.klompenpadKey([]),
                                 mtb: .init(mtb, spacing: MTBRoute.spacing), mtbKey: ChallengeResults.mtbKey(mtb))
    }

    private func store(_ r: ChallengeResults.Result, _ c: ChallengeResults.Current, in a: inout Activity) {
        if let t = r.trappists { a.trappists = t; a.trappistsKey = c.trappistsKey }
        if let b = r.boscafes { a.boscafes = b; a.boscafesKey = c.boscafesKey }
        if let h = r.klompenpadHits { a.klompenpadHits = h; a.klompenpadKey = c.klompenpadKey }
        if let h = r.mtbHits { a.mtbHits = h; a.mtbKey = c.mtbKey }
        if let co = r.countries { a.countries = co; a.countriesKey = ChallengeResults.countriesKey }
    }

    @Test func storedResultsEndPending() {
        let track = [GeoPoint(lat: 51.28472, lon: 4.64), GeoPoint(lat: 51.28472, lon: 4.67)]
        var a = ride(track)
        let c = current([westmalle])
        #expect(ChallengeResults.isPending(a, c))
        let r = ChallengeResults.compute(a, c)
        #expect(r.trappists == ["westmalle"])
        #expect(r.countries == ["BE"])
        store(r, c, in: &a)
        #expect(!ChallengeResults.isPending(a, c))
        // A new brewery list makes it pending again; only that part is computed.
        let newer = current([])
        #expect(ChallengeResults.isPending(a, newer))
        let again = ChallengeResults.compute(a, newer)
        #expect(again.trappists == [] && again.boscafes == nil && again.klompenpadHits == nil && again.mtbHits == nil && again.countries == nil)
    }

    @Test func boscafesAreVisitedLikeBreweries() {
        // A walk 150 m south of De Boshut in Hilversum, east to west.
        let boshut = Boscafe(id: "de-boshut-hilversum", name: "De Boshut", place: "Hilversum", emoji: "🌲", lat: 52.24173, lon: 5.1609)
        let south = 150.0 / 111_000
        var walk = Importer.makeActivity(points: [GeoPoint(lat: 52.24173 - south, lon: 5.15), GeoPoint(lat: 52.24173 - south, lon: 5.17)],
                                         id: "walk", cacheKey: "", name: "Walk", sport: "Walking", startDate: .now, distance: nil)
        let c = current([], boscafes: [boshut])
        let r = ChallengeResults.compute(walk, c)
        #expect(r.boscafes == ["de-boshut-hilversum"])
        store(r, c, in: &walk)
        #expect(!ChallengeResults.isPending(walk, c))
        #expect(ChallengeResults.isPending(walk, current([]))) // another list: checked again
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

    @Test func mtbRoutesCountRidesOnly() throws {
        // A 3 km route going east from 50.5°N 5.9°E.
        let points = (0...30).map { GeoPoint(lat: 50.5, lon: 5.9 + Double($0) * 0.0014) }
        let route = MTBRoute(id: "osm-1", name: "Test", ref: nil, network: "lcn", country: "BE", length: 3_000,
                             url: "https://www.openstreetmap.org/relation/1", website: nil, lat: 50.5, lon: 5.9,
                             lines: [ClimbMatcherTests.encode(points)], ascent: 12, grade: 0, signposted: false, technical: nil)
        let c = current([], mtb: [route])
        var ridden = ride(points)
        let r = ChallengeResults.compute(ridden, c)
        #expect(KlompenpadMatcher.progress(hits: [r.mtbHits ?? [:]], counts: c.mtb.counts)["osm-1"] ?? 0 >= KlompenpadMatcher.done)
        store(r, c, in: &ridden)
        #expect(!ChallengeResults.isPending(ridden, c))
        // A walk along the same trail doesn't count.
        let walk = Importer.makeActivity(points: points, id: "walk", cacheKey: "", name: "Walk", sport: "Walking",
                                         startDate: .now, distance: nil)
        #expect(ChallengeResults.compute(walk, c).mtbHits == [:])
    }
}

@MainActor
struct ChallengeEngineTests {
    @Test func addsUpStoredResultsWithTheCurrentKeysOnly() {
        let engine = ChallengeEngine()
        let boshut = Boscafe(id: "b", name: "B", place: "P", emoji: "🌲", lat: 52.24, lon: 5.16)
        let current = ChallengeResults.Current(trappists: [], trappistsKey: "t", boscafes: [boshut], boscafesKey: "b-now",
                                               paths: .init([Klompenpad]()), klompenpadKey: "k",
                                               mtb: .init([MTBRoute](), spacing: MTBRoute.spacing), mtbKey: "m")
        func walk(_ id: String, key: String, days: Double) -> Activity {
            var a = Importer.makeActivity(points: [GeoPoint(lat: 52.24, lon: 5.15), GeoPoint(lat: 52.24, lon: 5.17)],
                                          id: id, cacheKey: "", name: "Walk", sport: "Walking",
                                          startDate: Date(timeIntervalSince1970: days * 86_400), distance: 1_400)
            a.boscafes = ["b"]
            a.boscafesKey = key
            return a
        }
        let activities = [walk("1", key: "b-now", days: 1), walk("2", key: "b-now", days: 3), walk("3", key: "b-old", days: 5)]
        #expect(engine.aggregate(activities, current))
        // The stale result (another list) doesn't count; visits newest first.
        #expect(engine.boscafeVisits["b"] == [Date(timeIntervalSince1970: 3 * 86_400), Date(timeIntervalSince1970: 86_400)])
        #expect(!engine.aggregate(activities, current)) // nothing changed
        // A deleted activity drops out.
        #expect(engine.aggregate(Array(activities.dropFirst()), current))
        #expect(engine.boscafeVisits["b"]?.count == 1)
    }
}
