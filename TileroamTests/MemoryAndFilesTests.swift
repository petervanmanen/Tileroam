import Foundation
import MapKit
import Testing
@testable import Tileroam

struct AreaGeometryTests {
    /// A square municipality with a square hole, near Utrecht.
    private let area = Area(code: "NL:GM0344", name: "Utrecht", polygons: [Area.Polygon(rings: [
        [GeoPoint(lat: 52.0, lon: 5.0), GeoPoint(lat: 52.0, lon: 5.2), GeoPoint(lat: 52.2, lon: 5.2), GeoPoint(lat: 52.2, lon: 5.0)],
        [GeoPoint(lat: 52.05, lon: 5.05), GeoPoint(lat: 52.05, lon: 5.1), GeoPoint(lat: 52.1, lon: 5.1)],
    ])], minLat: 52.0, maxLat: 52.2, minLon: 5.0, maxLon: 5.2)

    @Test func compactPointsKeepTheOutline() throws {
        let geometry = AreaGeometry([area])
        let shape = try #require(geometry.shapes.first)
        #expect(shape.ringEnds == [4, 7])
        #expect(shape.points.count == 14)
        // Every point comes back within a hundredth of a map point (well under a centimetre).
        let all = area.polygons[0].rings.flatMap { $0 }
        for (i, p) in all.enumerated() {
            let exact = MKMapPoint(CLLocationCoordinate2D(latitude: p.lat, longitude: p.lon))
            let back = shape.point(i)
            #expect(abs(back.x - exact.x) < 0.01 && abs(back.y - exact.y) < 0.01)
        }
        #expect(MKMapRectEqualToRect(geometry.bounds, shape.bounds))
        #expect(shape.bounds.contains(MKMapPoint(CLLocationCoordinate2D(latitude: 52.1, longitude: 5.1))))
    }
}

/// `ChallengeFiles.read(known:)` reads a file again only when its date or size changed.
@Suite(.serialized)
struct ChallengeFileStampTests {
    @Test func unchangedFilesAreNotReadAgain() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "challenges-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        UserDefaults.standard.set(folder.path(percentEncoded: false), forKey: "ChallengesFolder")
        defer { UserDefaults.standard.removeObject(forKey: "ChallengesFolder") }
        let file = folder.appending(path: "beer.geojson")
        try Data("first".utf8).write(to: file)

        let first = ChallengeFiles.read().files["beer.geojson"]
        let stamp = try #require(first?.stamp)
        #expect(first?.data == Data("first".utf8))

        // Same date and size: not read.
        let again = ChallengeFiles.read(known: ["beer.geojson": stamp]).files["beer.geojson"]
        #expect(again?.data == nil && again?.stamp == stamp)

        // Changed: read again.
        try Data("second, longer".utf8).write(to: file)
        let changed = ChallengeFiles.read(known: ["beer.geojson": stamp]).files["beer.geojson"]
        #expect(changed?.data == Data("second, longer".utf8) && changed?.stamp != stamp)
    }
}
