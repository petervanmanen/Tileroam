import Foundation

/// Eddington number: the largest E such that you did at least E km on at least E different days.
struct Eddington: Sendable, Equatable, Codable {
    var number = 0
    /// Days with at least number + 1 km so far.
    var daysTowardNext = 0

    /// Days still needed with at least number + 1 km to reach the next Eddington number.
    var daysNeeded: Int { number + 1 - daysTowardNext }

    init() {}

    /// Distances are summed per local calendar day.
    init(activities: [Activity], sports: Set<String>, calendar: Calendar = .current) {
        var perDay = [DateComponents: Double]()
        for a in activities where sports.contains(a.sport) {
            guard let date = a.startDate else { continue }
            perDay[calendar.dateComponents([.year, .month, .day], from: date), default: 0] += a.distance / 1000
        }
        let km = perDay.values.map { Int($0.rounded(.down)) }.sorted(by: >)
        var e = 0
        while e < km.count, km[e] >= e + 1 { e += 1 }
        number = e
        daysTowardNext = km.count { $0 >= e + 1 }
    }

    static let cyclingSports: Set<String> = ["Cycling", "E-biking"]
    static let runningSports: Set<String> = ["Running"]
}
