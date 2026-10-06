import Foundation
import Testing
@testable import Tileroam

struct StravaExportTests {
    /// A detailed Strava activity saved without a stream keeps its route (the Mac missed 787
    /// routes when such activities were only in the library as Health exports without GPS).
    @Test func savesTheTrackItHasWithoutAStream() throws {
        // A zigzag, so simplifying the stored track keeps its points.
        let points = (0..<50).map { GeoPoint(lat: 51.84 + Double($0) * 0.001, lon: 5.86 + ($0 % 2 == 0 ? 0 : 0.001)) }
        var activity = Importer.makeActivity(points: points, id: "strava-1", cacheKey: "", name: "Ride", sport: "Cycling",
                                             startDate: Date(timeIntervalSince1970: 1_700_000_000), distance: 5_500)
        activity.elapsedTime = 1_200
        let fit = try FITDecoder.decode(StravaExport.fitData(for: activity, stream: nil))
        let stored = activity.coordinates
        try #require(stored.count > 10 && fit.points.count == stored.count)
        #expect(abs(fit.points[10].lat - stored[10].latitude) < 1e-5 && abs(fit.points[10].lon - stored[10].longitude) < 1e-5)
        #expect(fit.startTime == activity.startDate)
    }
}
