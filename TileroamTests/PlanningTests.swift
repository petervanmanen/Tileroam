import Foundation
import Testing
@testable import Tileroam

struct PlanningTests {
    @Test func gpxRoundTrip() throws {
        let track = (0..<20).map { GeoPoint(lat: 52.09 + Double($0) * 0.001, lon: 5.12 + Double($0) * 0.0005) }
        let data = GPX.write(name: "Test & <route>", track: track, waypoints: [(track[5], "Stop 1")])
        let parsed = try #require(GPX.parse(data))
        #expect(parsed.name == "Test & <route>")
        #expect(parsed.points.count == 20)
        #expect(parsed.waypoints.count == 1)
        #expect(Geo.distance(parsed.points[19], track[19]) < 0.5)
    }

    @Test func gpxWithRoutePointsOnly() throws {
        let xml = """
        <gpx xmlns="http://www.topografix.com/GPX/1/1"><rte><name>R</name>
        <rtept lat="52.1" lon="5.1"/><rtept lat="52.2" lon="5.2"/></rte></gpx>
        """
        let parsed = try #require(GPX.parse(Data(xml.utf8)))
        #expect(parsed.points.count == 2)
        #expect(parsed.name == "R")
    }

    @Test func candidatesLieInsideTargets() throws {
        for zoom in TileZoom.allCases {
            let key = try #require(TileGrid.key(lat: 52.0907, lon: 5.1214, zoom: zoom))
            let tile = try #require(TargetGeometry(.tile(zoom, key), regions: nil))
            #expect(tile.candidates().count == 36)
            #expect(tile.candidates().allSatisfy(tile.contains))
        }

        let utrecht = try #require(TargetGeometry(.municipality("NL:GM0344"), regions: GeoTests.regions))
        let points = utrecht.candidates()
        #expect(points.count >= 12)
        #expect(points.allSatisfy(utrecht.contains))
        #expect(utrecht.name == "Utrecht")
    }

    @Test func refinePicksCandidateOnTheWay() {
        // Start at 0,0. Target A has candidates far away and close; target B likewise.
        let start = GeoPoint(lat: 0, lon: 0)
        let a = [GeoPoint(lat: 10, lon: 0), GeoPoint(lat: 1, lon: 0)]
        let b = [GeoPoint(lat: 1, lon: 1), GeoPoint(lat: 10, lon: 10)]
        let flat: (GeoPoint, GeoPoint) -> Double = { hypot($0.lat - $1.lat, $0.lon - $1.lon) }
        #expect(RoutePlanner.refine(start: start, candidates: [a, b], distance: flat) == [1, 0])
    }

    @Test func decodesValhallaRoute() throws {
        // A real response (Luxembourg, round trip via one stop), trimmed to the fields used.
        let json = #"{"trip": {"legs": [{"shape": "it`s}A{xfuJvMPZfDl@dHnHfcAfBvUHlA|@rLjBfWvA|RT~ClF`r@dSZ`HLtV^vBDbAAr@?nOODnFh@lo@\\lb@L|D\\lFFbBTtFX`HPrD`Wdo@F|@Az@nArDf@fEpDqErA}Af@i@~@kAl@kBD_Cg@qBsEyHmBgFwAoI_@qCbAoAjAc@|@j@vHfK~KbMpAj@rA]r@_B?eCe@oBmDkIuAeE}AcFgFkSyC}MfCp@rB|CpGzNjHvSdL`]rDbFxEbKrCfF"}, {"shape": "euyr}AexytJsCgFyEcKsDcFeLa]kHwSqG{NsB}CgCq@xC|MfFjS|AbFtAdElDjId@nB?dCs@~AsA\\qAk@_LcMwHgK}@k@kAb@cAnA^pCvAnIlBfFrExHf@pBE~Bm@jB_AjAg@h@_EgLiOk_@YmA}@oD_@qB]gB}@_Ig@oFKeBKwEe@c`@KsDe@mIk@a\\[{YaBBqBDF~FoONs@?cA@wBEuV_@aHMeS[mFar@U_DwA}RkBgW}@sLImAgBwUoHgcAm@eH[gDwMQ"}], "summary": {"length": 2.147, "time": 538.705}}}"#
        let response = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let r = try ValhallaRouter.decodeRoute(response)
        #expect(r.distance == 2147)
        #expect(r.duration == 538.705)
        #expect(r.snapped.count == 3) // start, the stop, back at the start
        #expect(Geo.distance(r.snapped[0], GeoPoint(lat: 49.6116, lon: 6.1319)) < 100)
        #expect(Geo.distance(r.snapped[1], GeoPoint(lat: 49.6080, lon: 6.1250)) < 100)
        #expect(zip(r.coordinates, r.coordinates.dropFirst()).allSatisfy { $0 != $1 }) // legs joined without repeats

        #expect(throws: RoutingError.self) { try ValhallaRouter.decodeRoute(["trip": [String: Any]()]) }
    }

    @Test func decodesPolyline6() {
        // Valhalla's own example: _p~iF~ps|U at precision 6 is 38.5, -120.2 scaled by 10.
        let points = ValhallaRouter.decodePolyline6("_izlhA~rlgdF_{geC~ywl@_kwzCn`{nI")
        #expect(points.count == 3)
        #expect(abs(points[0].lat - 38.5) < 1e-6 && abs(points[0].lon - -120.2) < 1e-6)
    }

    @Test func tripSolverVisitsAroundASquare() {
        // Corners of a square, given in a crossing order: the best tour goes around it.
        let p = [(0.0, 0.0), (1, 1), (1, 0), (0, 1)]
        let cost = p.map { a in p.map { b in hypot(a.0 - b.0, a.1 - b.1) } }
        let order = TripSolver.roundTrip(cost)
        #expect(order.first == 0)
        #expect(Set(order) == [0, 1, 2, 3])
        #expect(order == [0, 2, 1, 3] || order == [0, 3, 1, 2])
        #expect(TripSolver.roundTrip([[0, 1], [1, 0]]) == [0, 1])
    }

    @Test func tripSolverHandlesManyStops() {
        // 50 stops on a circle in shuffled order: the tour must follow the circle.
        var rng = SystemRandomNumberGenerator()
        let angles = [0.0] + (1...50).map { Double($0) / 51 * 2 * .pi }.shuffled(using: &rng)
        let points = angles.map { (cos($0), sin($0)) }
        let cost = points.map { a in points.map { b in hypot(a.0 - b.0, a.1 - b.1) } }
        let order = TripSolver.roundTrip(cost)
        let length = zip(order, order.dropFirst() + [0]).reduce(0) { $0 + cost[$1.0][$1.1] }
        #expect(Set(order).count == 51)
        #expect(length < 2 * .pi * 1.01) // the circle's circumference
    }

    @Test func coverageExcludesVisited() throws {
        // ~2.2 km north from the Dom through Utrecht.
        let route = [GeoPoint(lat: 52.0907, lon: 5.1214), GeoPoint(lat: 52.1107, lon: 5.1214)]
        let all = RouteCoverage(route: route, visitedTiles14: [], visitedTiles17: [], visitedMunicipalities: [], visitedPostcodes: [],
                                regions: GeoTests.regions)
        #expect(all.newTiles14.count >= 2)
        #expect(all.newTiles17.count >= 10)
        #expect(all.newMunicipalities == ["NL:GM0344"])
        #expect(all.newPostcodes.contains("NL:3512"))

        let first = try #require(TileGrid.key(lat: 52.0907, lon: 5.1214, zoom: .explorer))
        let some = RouteCoverage(route: route, visitedTiles14: [first], visitedTiles17: [], visitedMunicipalities: ["NL:GM0344"],
                                 visitedPostcodes: ["NL:3512"], regions: GeoTests.regions)
        #expect(!some.newTiles14.contains(first))
        #expect(all.contains(.tile(.explorer, first)))
        #expect(some.newMunicipalities.isEmpty)
        #expect(!some.newPostcodes.contains("NL:3512"))
        #expect(all.contains(.municipality("NL:GM0344")))
    }
}
