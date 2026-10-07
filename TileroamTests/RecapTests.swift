import Foundation
import Testing
@testable import Tileroam

struct RecapTests {
    private func ride(_ id: String, _ date: String, tiles: [Int64], municipalities: [String] = [], distance: Double = 10_000) -> Activity {
        var a = Importer.makeActivity(points: [GeoPoint(lat: 52.09, lon: 5.12), GeoPoint(lat: 52.10, lon: 5.13)],
                                      id: id, cacheKey: "", name: "Ride", sport: "Cycling",
                                      startDate: ISO8601DateFormatter().date(from: date + "T10:00:00Z"), distance: distance)
        a.tiles14 = tiles
        a.municipalities = municipalities
        return a
    }

    @Test func historyKeepsTheFirstVisit() {
        let history = TileHistory(activities: [ride("b", "2025-03-01", tiles: [2, 3]), ride("a", "2024-12-01", tiles: [1, 2])])
        #expect(history.entries.map(\.key) == [1, 2, 3])
        #expect(history.tiles(before: ISO8601DateFormatter().date(from: "2025-01-01T00:00:00Z")!) == [1, 2])
    }

    @Test func tilesComeInTheOrderTheTrackReachesThem() {
        // A ride from east to west: the tiles must come east first, not sorted by key.
        let points = (0...20).map { GeoPoint(lat: 52.09, lon: 5.30 - Double($0) * 0.01) }
        var a = Importer.makeActivity(points: points, id: "w", cacheKey: "", name: "Ride", sport: "Cycling",
                                      startDate: .now, distance: 15_000)
        a.tiles14 = Array(TileGrid.tiles(for: points, zoom: .explorer)).sorted()
        let ordered = TileHistory.alongTrack(a)
        #expect(Set(ordered) == Set(a.tiles14!))
        let xs = ordered.map { TileGrid.cell(of: $0).x }
        #expect(xs == xs.sorted(by: >)) // east (larger x) to west
    }

    @Test func yearCountsWhatWasNew() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let activities = [ride("a", "2024-12-01", tiles: [1, 2], municipalities: ["NL:GM0344"]),
                          ride("b", "2025-03-01", tiles: [2, 3, 4], municipalities: ["NL:GM0344", "NL:GM0307"], distance: 50_000),
                          ride("c", "2025-07-01", tiles: [4, 5], municipalities: ["NL:GM0307"], distance: 30_000)]
        let review = YearInReview(year: 2025, activities: activities, history: TileHistory(activities: activities), calendar: calendar)
        #expect(review.activities == 2)
        #expect(review.distanceKm == 80)
        #expect(Set(review.newTiles) == [3, 4, 5])
        #expect(review.earlierTiles == [1, 2])
        #expect(review.newMunicipalities == 1)
        #expect(YearInReview.years(activities, calendar: calendar) == [2025, 2024])
    }

    @Test func regionFitsTheAspect() {
        let keys = [TileGrid.key(x: 8400, y: 5400), TileGrid.key(x: 8410, y: 5402)]
        let region = TileHistory.region(around: keys, aspect: 1080.0 / 1920)
        let rect = MKMapRectForRegion(region)
        #expect(abs(rect.width / rect.height - 1080.0 / 1920) < 0.02)
    }
}

import MapKit

private func MKMapRectForRegion(_ region: MKCoordinateRegion) -> MKMapRect {
    let a = MKMapPoint(CLLocationCoordinate2D(latitude: region.center.latitude + region.span.latitudeDelta / 2,
                                              longitude: region.center.longitude - region.span.longitudeDelta / 2))
    let b = MKMapPoint(CLLocationCoordinate2D(latitude: region.center.latitude - region.span.latitudeDelta / 2,
                                              longitude: region.center.longitude + region.span.longitudeDelta / 2))
    return MKMapRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
}
