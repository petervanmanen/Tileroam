import Foundation
import Testing
@testable import Tileroam

struct TrappistTests {
    private let westmalle = Trappist(id: "westmalle", name: "Westmalle", abbey: "Abdij", place: "Westmalle", country: "BE",
                                     lat: 51.28472, lon: 4.65667)

    /// The data in the repository (AssetPacks/Trappist), as uploaded to R2.
    static let source = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "AssetPacks/Trappist")

    @Test func repositoryData() throws {
        let list = try JSONDecoder().decode([Trappist].self, from: Data(contentsOf: Self.source.appending(path: "trappists.json")))
        #expect(list.count == 8)
        #expect(Set(list.map(\.id)).count == list.count)
        #expect(list.allSatisfy { FileManager.default.fileExists(atPath: Self.source.appending(path: "\($0.id).png").path(percentEncoded: false)) })
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

/// TrappistData against a local folder laid out like R2 (`<server>/Trappist/…`).
struct TrappistDataTests {
    private func temp() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "trappist-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A server folder with the repository's list and logos.
    private func server() throws -> URL {
        let root = try temp()
        try FileManager.default.copyItem(at: TrappistTests.source, to: root.appending(path: "Trappist"))
        return root
    }

    @Test func downloadsListAndLogos() async throws {
        let server = try server(), cache = try temp()
        let list = try await TrappistData.load(from: server, into: cache)
        #expect(list.count == 8)
        #expect(TrappistData.cached(in: cache) == list)
        #expect(list.allSatisfy { FileManager.default.fileExists(atPath: TrappistData.iconFile($0.id, in: cache).path(percentEncoded: false)) })
    }

    @Test func usesTheCopyOffline() async throws {
        let server = try server(), cache = try temp()
        let list = try await TrappistData.load(from: server, into: cache)
        try FileManager.default.removeItem(at: server)
        // Within a day: no download at all. A day later: the download fails, the copy is used.
        #expect(try await TrappistData.load(from: server, into: cache) == list)
        #expect(try await TrappistData.load(from: server, into: cache, now: .now.addingTimeInterval(2 * TrappistData.maxAge)) == list)
    }

    @Test func noListWithoutDownload() async throws {
        let cache = try temp()
        await #expect(throws: (any Error).self) {
            try await TrappistData.load(from: try temp(), into: cache)
        }
        #expect(TrappistData.cached(in: cache).isEmpty)
    }

    @Test func picksUpANewList() async throws {
        let server = try server(), cache = try temp()
        _ = try await TrappistData.load(from: server, into: cache)
        let file = server.appending(path: "Trappist/trappists.json")
        var list = try JSONDecoder().decode([Trappist].self, from: Data(contentsOf: file))
        list.removeLast()
        try JSONEncoder().encode(list).write(to: file)
        #expect(try await TrappistData.load(from: server, into: cache).count == 8) // still within a day
        #expect(try await TrappistData.load(from: server, into: cache, now: .now.addingTimeInterval(2 * TrappistData.maxAge)).count == 7)
    }
}

struct TrappistPlanningTests {
    private let westmalle = Trappist(id: "westmalle", name: "Westmalle", abbey: "Abdij", place: "Westmalle", country: "BE",
                                     lat: 51.28472, lon: 4.65667)

    @Test func breweryAsATarget() throws {
        let target = try #require(TargetGeometry(.trappist("westmalle"), regions: nil, trappists: [westmalle]))
        #expect(target.name == "Westmalle")
        let candidates = target.candidates()
        #expect(candidates.first == westmalle.point && candidates.count == 9)
        #expect(candidates.allSatisfy(target.contains)) // the ring lies within the 200 m
        #expect(!target.contains(GeoPoint(lat: 51.28472 + 300 / 111_000.0, lon: 4.65667)))
        #expect(TargetGeometry(.trappist("unknown"), regions: nil, trappists: [westmalle]) == nil)
    }

    @Test func routeVisitsTheBrewery() async throws {
        let target = try #require(TargetGeometry(.trappist("westmalle"), regions: nil, trappists: [westmalle]))
        let start = GeoPoint(lat: 51.25, lon: 4.60)
        let route = try await RoutePlanner.planRoute(
            start: start, targets: [target], client: StraightRouter(),
            coverage: { RouteCoverage(route: $0, visitedTiles14: [], visitedMunicipalities: [],
                                      visitedPostcodes: [], regions: nil, trappists: [westmalle], visitedTrappists: []) },
            progress: { _ in })
        #expect(route.coverage.trappists == ["westmalle"] && route.coverage.newTrappists == ["westmalle"])
        #expect(route.missed.isEmpty)
    }
}
