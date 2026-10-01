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

    @Test func decodesOSRMResponses() throws {
        let trip = #"{"code":"Ok","waypoints":[{"waypoint_index":0,"trips_index":0},{"waypoint_index":2,"trips_index":0},{"waypoint_index":1,"trips_index":0}],"trips":[]}"#
        #expect(try OSRMClient.decodeTripOrder(Data(trip.utf8)) == [0, 2, 1])

        let route = #"{"code":"Ok","routes":[{"distance":3242.5,"duration":1030.1,"geometry":{"type":"LineString","coordinates":[[5.1214,52.0907],[5.13,52.1]]}}],"waypoints":[{"location":[5.1214,52.0907]},{"location":[5.13,52.1]}]}"#
        let r = try OSRMClient.decodeRoute(Data(route.utf8))
        #expect(r.distance == 3242.5)
        #expect(r.coordinates.count == 2)
        #expect(r.coordinates[1] == GeoPoint(lat: 52.1, lon: 5.13))
        #expect(r.snapped.count == 2)

        let error = #"{"code":"NoRoute","message":"Impossible route"}"#
        #expect(throws: OSRMClient.OSRMError.self) { try OSRMClient.decodeRoute(Data(error.utf8)) }
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
