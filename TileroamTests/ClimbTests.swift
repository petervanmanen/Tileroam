import Foundation
import Testing
@testable import Tileroam

struct ClimbMatcherTests {
    /// A 2 km climb going north from 50.80°N 5.80°E.
    private let climb: Climb = {
        let points = (0...20).map { GeoPoint(lat: 50.80 + Double($0) * 0.0009, lon: 5.80) }
        return Climb(id: "test", name: "Testberg", place: nil, cat: .cat4, length: 2000, gain: 120, avg: 6, max: 9, top: 250,
                     start: [50.80, 5.80], end: [50.818, 5.80], line: ClimbMatcherTests.encode(points))
    }()

    /// Google polyline precision 5, as the build writes it.
    static func encode(_ points: [GeoPoint]) -> String {
        var out = "", pLat = 0, pLon = 0
        for p in points {
            let lat = Int((p.lat * 1e5).rounded()), lon = Int((p.lon * 1e5).rounded())
            for d in [lat - pLat, lon - pLon] {
                var v = d < 0 ? ~(d << 1) : d << 1
                while v >= 0x20 { out.append(Character(UnicodeScalar(UInt8((0x20 | (v & 0x1F)) + 63)))); v >>= 5 }
                out.append(Character(UnicodeScalar(UInt8(v + 63))))
            }
            pLat = lat; pLon = lon
        }
        return out
    }

    /// A ride from south of the climb to north of it, 10 m beside the road, every ~100 m.
    private func ride(from: Double, to: Double, offset: Double = 0.00014) -> [GeoPoint] {
        stride(from: from, through: to, by: from < to ? 0.0009 : -0.0009).map { GeoPoint(lat: $0, lon: 5.80 + offset) }
    }

    @Test func decodesTheLine() {
        #expect(climb.points.count == 21)
        #expect(abs(climb.points.last!.lat - 50.818) < 0.00001)
    }

    @Test func climbedUphill() {
        #expect(ClimbMatcher.climbed(climb, by: ride(from: 50.79, to: 50.83)))
    }

    @Test func upAndBackDownTheSameRoad() {
        // Up the climb and back down it: the bottom is passed twice, the last time after the top.
        let up = (0...20).map { GeoPoint(lat: 50.80 + Double($0) * 0.0009, lon: 5.80) }
        let ride = up + up.reversed().dropFirst()
        #expect(ClimbMatcher.climbed(climb, by: ride))
    }

    @Test func notWhenDescending() {
        #expect(!ClimbMatcher.climbed(climb, by: ride(from: 50.83, to: 50.79)))
    }

    @Test func notWhenOnlyPartly() {
        #expect(!ClimbMatcher.climbed(climb, by: ride(from: 50.79, to: 50.809)))
    }

    @Test func notOnAParallelRoad() {
        // 300 m to the east.
        #expect(!ClimbMatcher.climbed(climb, by: ride(from: 50.79, to: 50.83, offset: 0.0043)))
    }

    @Test func titles() {
        #expect(climb.title == "Testberg")
        let unnamed = Climb(id: "x", name: nil, place: "Valkenburg", cat: .hill, length: 400, gain: 30, avg: 7, max: 10, top: 180,
                            start: [0, 0], end: [0, 0], line: "")
        #expect(unnamed.title.contains("Valkenburg"))
        #expect(Climb.Category.hc > .cat1 && Climb.Category.cat4 > .hill)
    }
}

struct ClimbDataTests {
    @Test func readsTheIndex() throws {
        let json = #"{"name":"west","version":2,"areas":[["n50e005",3246,250000],["n47w002",10,900]]}"#
        let index = try JSONDecoder().decode(ClimbIndex.self, from: Data(json.utf8))
        #expect(index.version == 2 && ClimbData.key(index) == "west-v2")
        #expect(index.areas[0].lat == 50 && index.areas[0].lon == 5)
        #expect(index.areas[1].lat == 47 && index.areas[1].lon == -2)
        // Around Valkenburg: only its own area.
        let near = ClimbData.areas(around: [GeoPoint(lat: 50.86, lon: 5.83)], in: index)
        #expect(near.map(\.key) == ["n50e005"])
    }

    @Test func decodesClimbsAsTheBuildWritesThem() throws {
        let json = #"[{"id":"a1","name":"Cauberg","place":"Valkenburg","cat":"hill","length":720,"gain":57,"avg":7.9,"max":13.9,"top":171,"start":[50.86,5.83],"end":[50.855,5.84],"line":"_p~iF~ps|U_ulLnnqC"},{"id":"b2","name":null,"place":null,"cat":"HC","length":12000,"gain":1100,"avg":9.2,"max":13,"top":2100,"start":[0,0],"end":[1,1],"line":""}]"#
        let climbs = try JSONDecoder().decode([Climb].self, from: Data(json.utf8))
        #expect(climbs[0].cat == .hill && climbs[0].title == "Cauberg")
        #expect(climbs[1].cat == .hc && climbs[1].name == nil)
    }
}

/// A router that follows the points straight, to see what the planner asks for.
actor StraightRouter: CyclingRouter {
    private(set) var requested = [[GeoPoint]]()
    func tripOrder(_ points: [GeoPoint]) async throws -> [Int] { Array(points.indices) }
    func route(_ points: [GeoPoint]) async throws -> RoutedPath {
        requested.append(points)
        let dense = Geo.densified(points, spacing: 20, maxGap: 100_000)
        return RoutedPath(coordinates: dense, distance: 0, duration: 0, snapped: points)
    }
}

struct ClimbPlanningTests {
    /// 2 km going north from 50.80°N 5.80°E.
    private let climb: Climb = {
        let points = (0...20).map { GeoPoint(lat: 50.80 + Double($0) * 0.0009, lon: 5.80) }
        return Climb(id: "test", name: "Testberg", place: nil, cat: .cat4, length: 2000, gain: 120, avg: 6, max: 9, top: 250,
                     start: [50.80, 5.80], end: [50.818, 5.80], line: ClimbMatcherTests.encode(points))
    }()

    @Test func ridesTheClimbBottomToTop() async throws {
        let target = try #require(TargetGeometry(.climb("test"), regions: nil, climbs: ["test": climb]))
        #expect(target.candidates() == [climb.bottom])
        #expect(target.climbVia.last == climb.summit && target.climbVia.count <= 4)
        let router = StraightRouter()
        let start = GeoPoint(lat: 50.79, lon: 5.79)
        let route = try await RoutePlanner.planRoute(
            start: start, targets: [target], client: router,
            coverage: { RouteCoverage(route: $0, visitedTiles14: [], visitedMunicipalities: [],
                                      visitedPostcodes: [], regions: nil, climbs: [climb], climbed: []) },
            progress: { _ in })
        let asked = try #require(await router.requested.first)
        // Start, bottom, the points up the climb, back to the start.
        #expect(asked.first == start && asked[1] == climb.bottom && asked.dropLast().last == climb.summit && asked.last == start)
        #expect(route.coverage.climbs == ["test"] && route.coverage.newClimbs == ["test"])
        #expect(route.missed.isEmpty)
    }

    @Test @MainActor func climbsCountAgainstValhallasPointLimit() {
        let plan = PlanStore()
        for k in 0..<11 { plan.toggle(.climb("c\(k)")) }
        #expect(RoutePlanner.locations(plan.selected) == 57)
        // 57 + 5 > 60: one more climb doesn't fit, a tile does.
        plan.toggle(.climb("c11"))
        #expect(plan.selected.count == 11 && plan.error != nil)
        plan.toggle(.tile(.explorer, 1))
        #expect(plan.selected.count == 12 && plan.error == nil)
    }

    @Test func climbedBeforeIsNotNew() {
        let ride = (0...25).map { GeoPoint(lat: 50.795 + Double($0) * 0.0009, lon: 5.8001) }
        let coverage = RouteCoverage(route: ride, visitedTiles14: [], visitedMunicipalities: [],
                                     visitedPostcodes: [], regions: nil, climbs: [climb], climbed: ["test"])
        #expect(coverage.climbs == ["test"] && coverage.newClimbs.isEmpty)
    }
}
