import Foundation
import Testing
import UIKit
@testable import Tileroam

struct BadgeTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Amsterdam")!
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    /// An activity without GPS (indoor activities count for badges).
    private func activity(_ sport: String = "Cycling", _ km: Double = 20, on day: Date, name: String = "Ride",
                          ascent: Double? = nil, descent: Double? = nil, hours: Double = 1, zwift: Bool = false) -> Activity {
        var a = Importer.makeActivity(points: [], id: UUID().uuidString, cacheKey: "", name: name, sport: sport,
                                      startDate: day, distance: km * 1000)
        a.ascent = ascent
        a.descent = descent
        a.elapsedTime = hours * 3600
        a.isZwift = zwift
        return a
    }

    private func counts(_ activities: [Activity], countries: Int = 1) -> [Badge: Int] {
        BadgeRules.counts(activities, countries: countries, calendar: calendar)
    }

    @Test func everyBadgeHasAnIcon() {
        #expect(Badge.allCases.count == 18)
        #expect(Badge.allCases.allSatisfy { UIImage(named: $0.imageName) != nil })
    }

    @Test func distanceBadges() {
        let c = counts([
            activity("Cycling", 101, on: date(2026, 5, 1), ascent: 80),
            activity("Cycling", 165, on: date(2026, 5, 3), ascent: 900),
            activity("Running", 42.0, on: date(2026, 5, 5)),
            activity("Running", 21.2, on: date(2026, 5, 7)),
            activity("E-biking", 120, on: date(2026, 5, 9)),
        ])
        #expect(c[.hundred] == 2)     // e-bike rides don't count
        #expect(c[.century] == 1)
        #expect(c[.hollander] == 1)   // under 100 m of climbing
        #expect(c[.marathon] == 1)    // 42.0 km is within 1% of 42.195
        #expect(c[.halfMarathon] == 2)
    }

    @Test func everesterWithin24Hours() {
        let c = counts([
            activity(on: date(2026, 6, 1, 6), ascent: 5_000),
            activity(on: date(2026, 6, 1, 20), ascent: 4_000),
            activity(on: date(2026, 6, 3, 6), ascent: 5_000),
            activity(on: date(2026, 6, 4, 8), ascent: 4_000), // more than 24 h later
        ])
        #expect(c[.everester] == 1)
    }

    @Test func daysAndWeeks() {
        // Monday 6 July 2026 to Sunday 12 July: every day.
        let week = (6...12).map { activity(on: date(2026, 7, $0)) }
        // Monday 20 to Friday 24 July, free weekends around it.
        let workWeek = (20...24).map { activity(on: date(2026, 7, $0)) }
        let c = counts(week + workWeek)
        #expect(c[.everyDayImHustling] == 1)
        #expect(c[.working9To5] == 1)
    }

    @Test func tripleJump() {
        // Activity, rest, activity, rest, rest, activity.
        let c = counts([1, 3, 6].map { activity(on: date(2026, 8, $0)) })
        #expect(c[.tripleJump] == 1)
        #expect(counts([1, 2, 3, 6].map { activity(on: date(2026, 8, $0)) })[.tripleJump] == nil)
    }

    @Test func triathleteInOrder() {
        let day = [activity("Swimming", 2, on: date(2026, 8, 9, 7)),
                   activity("Running", 5, on: date(2026, 8, 9, 8)), // too early, a run comes later too
                   activity(on: date(2026, 8, 9, 9)),
                   activity("Running", 10, on: date(2026, 8, 9, 12))]
        #expect(counts(day)[.triathlete] == 1)
        let wrongOrder = [activity("Running", 10, on: date(2026, 8, 10, 7)), activity(on: date(2026, 8, 10, 9)),
                          activity("Swimming", 2, on: date(2026, 8, 10, 12))]
        #expect(counts(wrongOrder)[.triathlete] == nil)
    }

    @Test func calendarBadges() {
        let c = counts([
            activity(on: date(2025, 12, 24)), activity(on: date(2026, 12, 24)),
            activity(on: date(2028, 2, 29)),
            activity("Cycling", 300, on: date(2026, 12, 26)), activity("Cycling", 220, on: date(2026, 12, 30)),
        ])
        #expect(c[.silentNight] == 2)
        #expect(c[.giantLeap] == 1)
        #expect(c[.festive500] == 1) // 20 + 300 + 220 km in 2026
    }

    @Test func otherBadges() {
        var list = (0..<205).map { activity(on: date(2026, 1, 1).addingTimeInterval(Double($0) * 3600), zwift: true) }
        list.append(activity(on: date(2026, 3, 1), name: "Zwift - Uber Pretzel in Watopia", zwift: true))
        list.append(activity("Running", 160, on: date(2026, 3, 10), hours: 26))
        list.append(activity("Skiing", 30, on: date(2026, 2, 2, 9), descent: 700))
        list.append(activity("Snowboarding", 20, on: date(2026, 2, 2, 14), descent: 600))
        let c = counts(list, countries: 50)
        #expect(c[.taylor] == 2)
        #expect(c[.pretzel] == 1)
        #expect(c[.nosleep] == 1)
        #expect(c[.eddyTheEagle] == 1)
        #expect(c[.globetrotter] == 1)
        #expect(counts(list, countries: 7)[.globetrotter] == nil)
    }
}
