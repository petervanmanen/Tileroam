import Foundation
import Testing
@testable import Tileroam

/// Challenge files in the format of challenges/README.md.
enum ChallengeFixtures {
    static let repository = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    static func file(_ header: [String: Any], features: [[String: Any]]) -> Data {
        try! JSONSerialization.data(withJSONObject: ["type": "FeatureCollection", "tileroam": header, "features": features], options: .sortedKeys)
    }

    static func point(_ id: String, _ name: String, lat: Double, lon: Double, properties: [String: Any] = [:]) -> [String: Any] {
        ["type": "Feature", "id": id, "geometry": ["type": "Point", "coordinates": [lon, lat]],
         "properties": properties.merging(["name": name]) { a, _ in a }]
    }

    static func line(_ id: String, _ name: String, _ points: [GeoPoint]) -> [String: Any] {
        ["type": "Feature", "id": id, "geometry": ["type": "LineString", "coordinates": points.map { [$0.lon, $0.lat] }],
         "properties": ["name": name]]
    }

    static func challenge(_ header: [String: Any], features: [[String: Any]], fileName: String = "test.geojson") throws -> CustomChallenge {
        try CustomChallenge.parse(file(header, features: features), fileName: fileName).challenge
    }

    static var westmalle: [String: Any] { point("westmalle", "Westmalle", lat: 51.28472, lon: 4.65667) }
    static func breweries() throws -> CustomChallenge {
        try challenge(["format": 1, "id": "beer", "name": "Breweries", "kind": "locations", "icon": "🍺"], features: [westmalle])
    }

    static func ride(_ points: [GeoPoint], sport: String = "Cycling", id: String = UUID().uuidString, date: Date = .now) -> Activity {
        Importer.makeActivity(points: points, id: id, cacheKey: "", name: sport, sport: sport, startDate: date, distance: nil)
    }
}

struct ChallengeFileTests {
    @Test func readsALocationChallenge() throws {
        let c = try ChallengeFixtures.challenge(
            ["format": 1, "id": "beer", "name": "Breweries", "tab": "Beer", "kind": "locations", "icon": "🍺", "radius": 150,
             "attribution": "Public sources"],
            features: [ChallengeFixtures.point("a", "A", lat: 52, lon: 5, properties: ["subtitle": "Town", "icon": "🌲", "url": "https://example.com"]),
                       ChallengeFixtures.point("b", "B", lat: 52.1, lon: 5.1)])
        #expect(c.id == "beer" && c.name == "Breweries" && c.tab == "Beer" && c.icon == "🍺" && c.radius == 150)
        #expect(c.kind == .locations && c.isPlanningTarget && c.attribution == "Public sources")
        let a = try #require(c.item("a"))
        #expect(a.subtitle == "Town" && a.icon == "🌲" && a.link?.host() == "example.com" && a.point == GeoPoint(lat: 52, lon: 5))
        #expect(c.items.count == 2)
    }

    @Test func defaults() throws {
        let c = try ChallengeFixtures.challenge(["format": 1, "name": "My Places", "kind": "locations"],
                                                features: [ChallengeFixtures.westmalle], fileName: "Mijn Plekken.geojson")
        #expect(c.id == "mijn-plekken" && c.tab == "My Places" && c.icon == "📍" && c.radius == 200 && c.sports == nil)
        let r = try ChallengeFixtures.challenge(["format": 1, "name": "Paths", "kind": "routes"],
                                                features: [ChallengeFixtures.line("p", "P", [GeoPoint(lat: 52, lon: 5), GeoPoint(lat: 52, lon: 5.01)])])
        #expect(r.completion == .cover && r.coverage == 0.9 && r.spacing == 50 && !r.isPlanningTarget && r.isCoverRoutes)
        #expect((680...690).contains(r.items[0].length))
    }

    @Test func badHeaders() {
        func error(_ header: [String: Any]) -> CustomChallenge.ParseError? {
            do {
                _ = try ChallengeFixtures.challenge(header, features: [ChallengeFixtures.westmalle])
                return nil
            } catch {
                return error as? CustomChallenge.ParseError
            }
        }
        #expect(error(["name": "X", "kind": "locations"]) == .missing("tileroam.format"))
        #expect(error(["format": 2, "name": "X", "kind": "locations"]) == .unsupportedFormat(2))
        #expect(error(["format": 1, "kind": "locations"]) == .missing("tileroam.name"))
        #expect(error(["format": 1, "name": "X", "kind": "areas"]) == .invalid("tileroam.kind"))
        #expect(error(["format": 1, "name": "X", "kind": "locations", "id": "Bad Id"]) == .invalid("tileroam.id"))
        #expect(error(["format": 1, "name": "X", "kind": "locations", "radius": 1]) == .invalid("tileroam.radius"))
        #expect(error(["format": 1, "name": "X", "kind": "locations", "complete": "cross"]) == .invalid("tileroam.complete"))
        #expect(error(["format": 1, "name": "X", "kind": "locations", "icon": "beer"]) == .invalid("tileroam.icon"))
        #expect(error(["format": 1, "name": "X", "kind": "routes"]) == .noItems) // a Point in a route challenge
        #expect(throws: CustomChallenge.ParseError.notJSON) { try CustomChallenge.parse(Data("nope".utf8), fileName: "x.geojson") }
        #expect(throws: CustomChallenge.ParseError.noHeader) {
            try CustomChallenge.parse(Data(#"{"type":"FeatureCollection","features":[]}"#.utf8), fileName: "x.geojson")
        }
    }

    @Test func skipsUnusableFeatures() throws {
        let features: [[String: Any]] = [
            ChallengeFixtures.westmalle,
            ChallengeFixtures.westmalle, // the same id again
            ["type": "Feature", "geometry": ["type": "Point", "coordinates": [5, 52]], "properties": ["name": "No id"]],
            ["type": "Feature", "id": 7, "geometry": ["type": "Point", "coordinates": [5, 52]], "properties": [:]], // no name
            ["type": "Feature", "id": 8, "geometry": ["type": "Point", "coordinates": [5, 95]], "properties": ["name": "Off the map"]],
            ["type": "Feature", "properties": ["id": 9, "name": "Id in properties"], "geometry": ["type": "Point", "coordinates": [5, 52]]],
        ]
        let (c, skipped) = try CustomChallenge.parse(ChallengeFixtures.file(["format": 1, "name": "X", "kind": "locations"], features: features),
                                                     fileName: "x.geojson")
        #expect(c.items.map(\.id) == ["westmalle", "9"] && skipped == 4)
    }

    @Test func crossingsAreOneLine() throws {
        let multi: [String: Any] = ["type": "Feature", "id": "m", "properties": ["name": "M"],
                                    "geometry": ["type": "MultiLineString", "coordinates": [[[5, 52], [5, 52.001]], [[5.1, 52], [5.1, 52.001]]]]]
        let line = ChallengeFixtures.line("f", "F", [GeoPoint(lat: 52, lon: 5), GeoPoint(lat: 52.002, lon: 5)])
        let c = try ChallengeFixtures.challenge(["format": 1, "name": "Ferries", "kind": "routes", "complete": "cross"], features: [multi, line])
        #expect(c.items.map(\.id) == ["f"])
        // Drawn at the middle of the crossing.
        #expect(abs(c.items[0].point.lat - 52.001) < 0.000_01)
        // A cover route may have several pieces.
        let paths = try ChallengeFixtures.challenge(["format": 1, "name": "Paths", "kind": "routes"], features: [multi])
        #expect(paths.items[0].pieces.count == 2)
    }

    @Test func keyFollowsTheFile() throws {
        let header: [String: Any] = ["format": 1, "id": "beer", "name": "Breweries", "kind": "locations"]
        let a = try ChallengeFixtures.challenge(header, features: [ChallengeFixtures.westmalle])
        let b = try ChallengeFixtures.challenge(header, features: [ChallengeFixtures.westmalle])
        let c = try ChallengeFixtures.challenge(header.merging(["radius": 300]) { _, new in new }, features: [ChallengeFixtures.westmalle])
        #expect(a.key == b.key && a.key != c.key && a.key.hasPrefix("x\(ChallengeResults.version)-"))
    }

    @Test func emoji() {
        #expect(CustomChallenge.isEmoji("🍺") && CustomChallenge.isEmoji("⛴️") && CustomChallenge.isEmoji("🇳🇱"))
        #expect(!CustomChallenge.isEmoji("A") && !CustomChallenge.isEmoji("🍺🍺") && !CustomChallenge.isEmoji("1"))
    }

    /// The sample challenge in the repository (challenges/trappist-breweries.geojson).
    @Test func sampleChallenge() throws {
        let url = ChallengeFixtures.repository.appending(path: "challenges/trappist-breweries.geojson")
        let (c, skipped) = try CustomChallenge.parse(Data(contentsOf: url), fileName: url.lastPathComponent)
        #expect(c.id == "trappist-breweries" && c.icon == "🍺" && c.kind == .locations && skipped == 0)
        #expect(c.items.count >= 8 && c.item("westmalle") != nil)
    }
}

struct ChallengeMatcherTests {
    private let westmalle = GeoPoint(lat: 51.28472, lon: 4.65667)
    private var brewery: ChallengeItem { ChallengeItem(id: "westmalle", name: "Westmalle", point: westmalle) }

    @Test func passingWithinTheRadius() {
        // A ride 150 m north of the brewery, east to west; a sparse track counts between its points.
        let north = 150.0 / 111_000
        let ride = [GeoPoint(lat: westmalle.lat + north, lon: 4.64), GeoPoint(lat: westmalle.lat + north, lon: 4.67)]
        #expect(PlaceMatcher.visited(by: ride, among: [brewery], radius: 200) == ["westmalle"])
        #expect(PlaceMatcher.visited(by: ride, among: [brewery], radius: 100).isEmpty)
        #expect(PlaceMatcher.visited(by: [], among: [brewery], radius: 200).isEmpty)
    }

    @Test func segmentDistance() {
        let p = GeoPoint(lat: 51, lon: 5)
        let a = GeoPoint(lat: 51.001, lon: 4.99), b = GeoPoint(lat: 51.001, lon: 5.01)
        #expect(abs(PlaceMatcher.distance(from: p, toSegment: a, b) - 110.6) < 1)
        // Beyond the segment's end: the distance to that end.
        let c = GeoPoint(lat: 51, lon: 5.01), d = GeoPoint(lat: 51, lon: 5.02)
        #expect(abs(PlaceMatcher.distance(from: p, toSegment: c, d) - Geo.distance(p, c)) < 2)
    }

    /// A 300 m crossing going north at 51.95°N 5.22°E (like a pontje over the Lek).
    private let ferry = ChallengeItem(id: "f", name: "Lexmond – Culemborg",
                                      pieces: [[GeoPoint(lat: 51.9500, lon: 5.22), GeoPoint(lat: 51.9527, lon: 5.22)]], crossing: true)

    @Test func crossingCounts() {
        let ride = [GeoPoint(lat: 51.9455, lon: 5.2201), GeoPoint(lat: 51.9500, lon: 5.2201),
                    GeoPoint(lat: 51.9527, lon: 5.2199), GeoPoint(lat: 51.9572, lon: 5.2199)]
        #expect(CrossingMatcher.crossed(by: ride, among: [ferry]) == ["f"])
    }

    @Test func ridingAlongTheBankDoesNot() {
        let bank = [GeoPoint(lat: 51.9499, lon: 5.20), GeoPoint(lat: 51.9499, lon: 5.24)]
        #expect(CrossingMatcher.crossed(by: bank, among: [ferry]).isEmpty)
        let back = [GeoPoint(lat: 51.9455, lon: 5.22), GeoPoint(lat: 51.9500, lon: 5.22), GeoPoint(lat: 51.9455, lon: 5.22)]
        #expect(CrossingMatcher.crossed(by: back, among: [ferry]).isEmpty)
    }

    @Test func shortPontjeNeedsACrossing() {
        let pontje = ChallengeItem(id: "p", name: "Pontje", pieces: [[GeoPoint(lat: 52.0, lon: 5.0), GeoPoint(lat: 52.000324, lon: 5.0)]], crossing: true)
        let bank = [GeoPoint(lat: 51.99991, lon: 4.999), GeoPoint(lat: 51.99991, lon: 5.001)]
        #expect(CrossingMatcher.crossed(by: bank, among: [pontje]).isEmpty)
        let across = [GeoPoint(lat: 51.9995, lon: 5.0), GeoPoint(lat: 52.0008, lon: 5.0)]
        #expect(CrossingMatcher.crossed(by: across, among: [pontje]) == ["p"])
    }

    /// A 2 km path going east from 52.0°N 5.6°E.
    private let path = ChallengeItem(id: "test", name: "Testpad", pieces: [(0...40).map { GeoPoint(lat: 52.0, lon: 5.6 + Double($0) * 0.000_73) }])

    private func progress(_ tracks: [[GeoPoint]]) -> Double {
        let prepared = RouteMatcher.Prepared([path], spacing: 50)
        return RouteMatcher.progress(hits: tracks.map { RouteMatcher.hits($0, paths: prepared) }, counts: prepared.counts)["test"] ?? 0
    }

    @Test func routeCoveredWhole() {
        #expect(progress([(0...40).map { GeoPoint(lat: 52.0001, lon: 5.6 + Double($0) * 0.000_73) }]) >= 0.9) // 11 m beside it
    }

    @Test func routeHalfOverTwoWalks() {
        let first = (0...10).map { GeoPoint(lat: 52.0, lon: 5.6 + Double($0) * 0.000_73) }
        let second = (10...20).map { GeoPoint(lat: 52.0, lon: 5.6 + Double($0) * 0.000_73) }
        #expect((0.2...0.3).contains(progress([first])))
        #expect((0.45...0.55).contains(progress([first, second]))) // walks add up
    }

    @Test func notOnAParallelRoad() {
        #expect(progress([(0...40).map { GeoPoint(lat: 52.0009, lon: 5.6 + Double($0) * 0.000_73) }]) == 0) // 100 m away
    }

    @Test func progressAddsUpStoredHits() {
        let counts = ["a": 10, "b": 4]
        // Two walks over parts of route a (overlapping), one over b; "gone" is no longer in the file.
        #expect(RouteMatcher.progress(hits: [["a": [0, 1, 2, 3]], ["a": [3, 4, 5], "b": [0, 1, 2, 3]], ["gone": [0]]], counts: counts)
                == ["a": 0.6, "b": 1.0])
        #expect(RouteMatcher.progress(hits: [["a": [0, 1, 2, 3]]], counts: counts) == ["a": 0.4])
    }
}

struct ChallengeResultsTests {
    private func current(_ challenges: [CustomChallenge]) -> ChallengeResults.Current {
        ChallengeResults.Current(challenges: challenges, prepared: Dictionary(uniqueKeysWithValues: challenges.filter(\.isCoverRoutes).map {
            ($0.id, RouteMatcher.Prepared($0.items, spacing: $0.spacing))
        }))
    }

    @Test func storedResultsEndPending() throws {
        let breweries = try ChallengeFixtures.breweries()
        var a = ChallengeFixtures.ride([GeoPoint(lat: 51.28472, lon: 4.64), GeoPoint(lat: 51.28472, lon: 4.67)])
        let c = current([breweries])
        #expect(ChallengeResults.isPending(a, c))
        let r = ChallengeResults.compute(a, c)
        #expect(r.hits["beer"]?.ids == ["westmalle"] && r.countries == ["BE"])
        ChallengeResults.store(r, c, in: &a)
        #expect(!ChallengeResults.isPending(a, c))
        // A changed file makes it pending again; only that challenge is checked.
        let changed = try ChallengeFixtures.challenge(["format": 1, "id": "beer", "name": "Breweries", "kind": "locations", "radius": 50],
                                                      features: [ChallengeFixtures.westmalle])
        let newer = current([changed])
        #expect(ChallengeResults.isPending(a, newer))
        let again = ChallengeResults.compute(a, newer)
        #expect(again.hits["beer"]?.key == changed.key && again.countries == nil)
        // A challenge that's gone is dropped from the activity.
        ChallengeResults.store(ChallengeResults.Result(), current([]), in: &a)
        #expect(a.challengeHits == nil)
    }

    @Test func sportsLimitWhatCounts() throws {
        let points = (0...30).map { GeoPoint(lat: 50.5, lon: 5.9 + Double($0) * 0.0014) } // a 3 km route east
        let mtb = try ChallengeFixtures.challenge(["format": 1, "id": "mtb", "name": "MTB", "kind": "routes", "sports": ["Cycling", "E-biking"], "spacing": 100],
                                                  features: [ChallengeFixtures.line("r", "Route", points)])
        let c = current([mtb])
        let ride = ChallengeResults.compute(ChallengeFixtures.ride(points), c).hits["mtb"]
        #expect(RouteMatcher.progress(hits: [ride?.checkpoints ?? [:]], counts: c.prepared["mtb"]!.counts)["r"] ?? 0 >= 0.9)
        // A walk along the same trail doesn't count, but is stored, so it isn't checked again.
        var walk = ChallengeFixtures.ride(points, sport: "Walking")
        let r = ChallengeResults.compute(walk, c)
        #expect(r.hits["mtb"] == ChallengeHits(key: mtb.key))
        ChallengeResults.store(r, c, in: &walk)
        #expect(!ChallengeResults.isPending(walk, c))
    }
}

@MainActor
struct ChallengeEngineTests {
    @Test func addsUpStoredResultsWithTheCurrentKeysOnly() throws {
        let engine = ChallengeEngine()
        let breweries = try ChallengeFixtures.breweries()
        let current = ChallengeResults.Current(challenges: [breweries], prepared: [:])
        func walk(_ id: String, key: String, days: Double) -> Activity {
            var a = ChallengeFixtures.ride([GeoPoint(lat: 52.24, lon: 5.15), GeoPoint(lat: 52.24, lon: 5.17)], sport: "Walking", id: id,
                                           date: Date(timeIntervalSince1970: days * 86_400))
            a.challengeHits = ["beer": ChallengeHits(key: key, ids: ["westmalle"])]
            return a
        }
        let activities = [walk("1", key: breweries.key, days: 1), walk("2", key: breweries.key, days: 3), walk("3", key: "old", days: 5)]
        #expect(engine.aggregate(activities, current))
        // The stale result (another file) doesn't count; visits newest first.
        #expect(engine.progress(of: "beer").visits["westmalle"] == [Date(timeIntervalSince1970: 3 * 86_400), Date(timeIntervalSince1970: 86_400)])
        #expect(engine.progress(of: "beer").done(in: breweries) == 1)
        #expect(!engine.aggregate(activities, current)) // nothing changed
        // A deleted activity drops out.
        #expect(engine.aggregate(Array(activities.dropFirst()), current))
        #expect(engine.progress(of: "beer").visits["westmalle"]?.count == 1)
    }
}

struct ChallengePlanningTests {
    @Test func placeAsATarget() throws {
        let breweries = try ChallengeFixtures.breweries()
        let target = try #require(TargetGeometry(.place("beer", "westmalle"), regions: nil, challenges: [breweries]))
        #expect(target.name == "Westmalle")
        let candidates = target.candidates()
        #expect(candidates.first == GeoPoint(lat: 51.28472, lon: 4.65667) && candidates.count == 9)
        #expect(candidates.allSatisfy(target.contains)) // the ring lies within the radius
        #expect(!target.contains(GeoPoint(lat: 51.28472 + 300 / 111_000.0, lon: 4.65667)))
        #expect(TargetGeometry(.place("beer", "unknown"), regions: nil, challenges: [breweries]) == nil)
        #expect(TargetGeometry(.place("other", "westmalle"), regions: nil, challenges: [breweries]) == nil)
    }

    @Test func routeVisitsThePlace() async throws {
        let breweries = try ChallengeFixtures.breweries()
        let target = try #require(TargetGeometry(.place("beer", "westmalle"), regions: nil, challenges: [breweries]))
        let route = try await RoutePlanner.planRoute(
            start: GeoPoint(lat: 51.25, lon: 4.60), targets: [target], client: StraightRouter(),
            coverage: { RouteCoverage(route: $0, visitedTiles14: [], visitedMunicipalities: [], visitedPostcodes: [], regions: nil,
                                      challenges: [(breweries, [])]) },
            progress: { _ in })
        #expect(route.coverage.places["beer"] == ["westmalle"] && route.coverage.newPlaces["beer"] == ["westmalle"])
        #expect(route.coverage.contains(.place("beer", "westmalle")))
        #expect(route.coverage.summary(.explorer).contains("Breweries: 1"))
        #expect(route.missed.isEmpty)
    }
}
