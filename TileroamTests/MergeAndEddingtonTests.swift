import Foundation
import Testing
@testable import Tileroam

private func activity(_ id: String, start: TimeInterval, minutes: Double? = nil, km: Double = 10,
                      sport: String = "Cycling", gps: Bool = false) -> Activity {
    var a = Activity(id: id, cacheKey: "", name: id, sport: sport, startDate: Date(timeIntervalSince1970: start),
                     distance: km * 1000, trackData: gps ? Data(count: 16) : Data())
    a.elapsedTime = minutes.map { $0 * 60 }
    return a
}

struct MergeTests {
    @Test func overlappingCopiesMergeKeepingLongestDistance() {
        // Same Zwift ride: watch starts at 0, Companion 3 min later, Strava copy with 0 km.
        let merged = ActivityMerge.merge([
            activity("watch.fit", start: 0, minutes: 140, km: 0),
            activity("companion.fit", start: 180, minutes: 138, km: 38.8),
            activity("strava:1", start: 200, minutes: 132, km: 0),
        ])
        #expect(merged.map(\.id) == ["companion.fit"])
    }

    @Test func separateRidesSameDayStaySeparate() {
        let merged = ActivityMerge.merge([
            activity("to-work", start: 0, minutes: 30),
            activity("home", start: 9 * 3600, minutes: 32),
        ])
        #expect(merged.count == 2)
    }

    @Test func differentSportsNeedMoreOverlap() {
        // A walk during the last 60% of a ride: same time but not the same workout.
        let merged = ActivityMerge.merge([
            activity("ride", start: 0, minutes: 100, sport: "Cycling"),
            activity("walk", start: 60 * 60, minutes: 60, sport: "Walking"),
        ])
        #expect(merged.count == 2)
    }

    @Test func gpsCopyWins() {
        let merged = ActivityMerge.merge([
            activity("healthfit.fit", start: 0, minutes: 60, km: 30),
            activity("strava:2", start: 400, minutes: 55, km: 29, gps: true),
        ])
        #expect(merged.map(\.id) == ["strava:2"])
    }

    @Test func indexFindsOverlappingWorkout() {
        let index = ActivityMerge.Index([activity("folder.fit", start: 1000, minutes: 60)])
        #expect(index.contains(activity("strava:3", start: 1300, minutes: 58)))
        #expect(!index.contains(activity("strava:4", start: 20000, minutes: 58)))
    }
}

struct EddingtonTests {
    @Test func computesNumberAndDaysNeeded() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Amsterdam")!
        let day: TimeInterval = 24 * 3600
        // Rides of 5, 4, 4, 3, 2 km on separate days, plus a second 3 km ride on the first day (5+3 = 8).
        let acts = [5.0, 4, 4, 3, 2].enumerated().map { activity("r\($0.offset)", start: 1_700_000_000 + Double($0.offset) * day, km: $0.element) }
            + [activity("extra", start: 1_700_000_000 + 3600, km: 3), activity("run", start: 1_700_000_000, km: 50, sport: "Running")]
        let e = Eddington(activities: acts, sports: Eddington.cyclingSports, calendar: calendar)
        #expect(e.number == 3)   // days: 8, 4, 4, 3, 2 km
        #expect(e.daysTowardNext == 3)
        #expect(e.daysNeeded == 1)
    }
}
