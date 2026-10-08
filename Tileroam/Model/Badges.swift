import Foundation

/// Badges for feats in the user's activities (AssetPacks/Badges/badges.md; icons rendered with
/// Tools/render_badges.swift to Resources/Badges/badge-<id>.png). Indoor and virtual activities
/// count too. Each badge can be earned more than once: `Badge.count` says how often.
enum Badge: String, CaseIterable, Identifiable, Sendable {
    case hundred = "100", century, hollander, everester, pretzel, nosleep
    case everyDayImHustling = "every-day-im-hustling", working9To5 = "working-9-to-5", tripleJump = "triple-jump"
    case triathlete, eddyTheEagle = "eddy-the-eagle", marathon, halfMarathon = "half-marathon"
    case silentNight = "silent-night", giantLeap = "giant-leap", festive500 = "festive-500", globetrotter, taylor

    var id: String { rawValue }
    var imageName: String { "badge-\(rawValue)" }

    var title: String {
        switch self {
        case .hundred: String(localized: "100!")
        case .century: String(localized: "Century")
        case .hollander: String(localized: "Hollander")
        case .everester: String(localized: "Everester")
        case .pretzel: String(localized: "Pretzel")
        case .nosleep: String(localized: "Nosleep")
        case .everyDayImHustling: String(localized: "Every day I'm hustling")
        case .working9To5: String(localized: "Working 9 to 5")
        case .tripleJump: String(localized: "Triple jump")
        case .triathlete: String(localized: "Triathlete")
        case .eddyTheEagle: String(localized: "Eddy the Eagle")
        case .marathon: String(localized: "Marathon")
        case .halfMarathon: String(localized: "Half Marathon")
        case .silentNight: String(localized: "Silent night")
        case .giantLeap: String(localized: "Giant leap")
        case .festive500: String(localized: "Christmas 500")
        case .globetrotter: String(localized: "Globetrotter")
        case .taylor: String(localized: "Taylor")
        }
    }

    var goal: String {
        switch self {
        case .hundred: String(localized: "Cycle 100 km in one activity")
        case .century: String(localized: "Cycle 100 miles in one activity")
        case .hollander: String(localized: "Cycle 100 km with less than 100 m of elevation")
        case .everester: String(localized: "Cycle more than 8,848 m of elevation within 24 hours")
        case .pretzel: String(localized: "Ride Zwift's Uber Pretzel: at least 128 km and 2,300 m of climbing")
        case .nosleep: String(localized: "Complete an activity that took more than 24 hours")
        case .everyDayImHustling: String(localized: "Complete an activity every day of the week")
        case .working9To5: String(localized: "An activity every working day, none in the weekend before or after")
        case .tripleJump: String(localized: "Activity, 1 rest day, activity, 2 rest days, activity")
        case .triathlete: String(localized: "Swim, bike and run on the same day, in that order")
        case .eddyTheEagle: String(localized: "Descend more than 1,000 m in one day skiing or snowboarding")
        case .marathon: String(localized: "Run a marathon distance")
        case .halfMarathon: String(localized: "Run a half-marathon distance")
        case .silentNight: String(localized: "Complete an activity on Christmas Eve")
        case .giantLeap: String(localized: "Complete an activity on 29 February")
        case .festive500: String(localized: "500 km of activities from 24 to 31 December")
        case .globetrotter: String(localized: "Complete activities in 50 countries")
        case .taylor: String(localized: "Complete 100 Zwift activities")
        }
    }
}

/// Works out how often each badge was earned.
enum BadgeRules {
    static let marathon = 42_195.0
    /// GPS distances come out a little short: 1% less still counts.
    static let tolerance = 0.99

    /// Zwift's Uber Pretzel: the name says so ("Uber" or "Über", any case), and it was really
    /// ridden: at least 128 km and 2,300 m of climbing.
    static func isUberPretzel(_ a: Activity) -> Bool {
        let name = a.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return name.contains("uber pretzel") && a.distance >= 128_000 && (a.ascent ?? 0) >= 2_300
    }

    /// How often each badge was earned (badges never earned are left out). `countries` is the
    /// number of countries with activities, for Globetrotter.
    static func counts(_ activities: [Activity], countries: Int, calendar: Calendar = .current) -> [Badge: Int] {
        var result = [Badge: Int]()
        func add(_ badge: Badge, _ n: Int) { if n > 0 { result[badge, default: 0] += n } }

        let dated = activities.filter { $0.startDate != nil }.sorted { $0.startDate! < $1.startDate! }
        let cycling = dated.filter { Sport.isCycling($0.sport) }
        let running = dated.filter { $0.sport == "Running" }

        // One activity.
        add(.hundred, cycling.count { $0.distance >= 100_000 })
        add(.century, cycling.count { $0.distance >= 160_934 })
        add(.hollander, cycling.count { $0.distance >= 100_000 && ($0.ascent.map { $0 < 100 } ?? false) })
        add(.marathon, running.count { $0.distance >= marathon * tolerance })
        add(.halfMarathon, running.count { $0.distance >= marathon / 2 * tolerance })
        add(.nosleep, dated.count { ($0.elapsedTime ?? 0) > 24 * 3600 })
        add(.pretzel, dated.count(where: isUberPretzel))
        add(.taylor, dated.count { $0.isZwift == true } / 100)
        add(.globetrotter, countries >= 50 ? 1 : 0)

        // Everester: 8,848 m of cycling within 24 hours; each 24-hour stretch counts once.
        var i = 0
        while i < cycling.count {
            let end = cycling[i].startDate!.addingTimeInterval(24 * 3600)
            let window = cycling[i...].prefix { $0.startDate! < end }
            if window.reduce(0, { $0 + ($1.ascent ?? 0) }) > 8_848 {
                add(.everester, 1)
                i += window.count
            } else {
                i += 1
            }
        }

        // Days.
        let byDay = Dictionary(grouping: dated) { calendar.startOfDay(for: $0.startDate!) }
        let days = Set(byDay.keys)
        func active(_ day: Date, _ offset: Int) -> Bool {
            calendar.date(byAdding: .day, value: offset, to: day).map(days.contains) ?? false
        }
        add(.tripleJump, days.count { d in
            !active(d, 1) && active(d, 2) && !active(d, 3) && !active(d, 4) && active(d, 5)
        })
        add(.triathlete, byDay.values.count { list in
            // Swim, then bike, then run (others may come in between).
            var step = 0
            for a in list where step < 3 {
                if step == 0, a.sport == "Swimming" { step = 1 }
                else if step == 1, Sport.isCycling(a.sport) { step = 2 }
                else if step == 2, a.sport == "Running" { step = 3 }
            }
            return step == 3
        })
        add(.eddyTheEagle, byDay.values.count { list in
            list.filter { ["Skiing", "Snowboarding"].contains($0.sport) }.reduce(0) { $0 + ($1.descent ?? 0) } > 1_000
        })
        add(.silentNight, Set(days.filter { calendar.component(.month, from: $0) == 12 && calendar.component(.day, from: $0) == 24 }
            .map { calendar.component(.year, from: $0) }).count)
        add(.giantLeap, Set(days.filter { calendar.component(.month, from: $0) == 2 && calendar.component(.day, from: $0) == 29 }
            .map { calendar.component(.year, from: $0) }).count)

        // Christmas 500 (called Festive 500 until 1.15; the id stays): per year, 24–31 December.
        let festive = Dictionary(grouping: dated.filter {
            calendar.component(.month, from: $0.startDate!) == 12 && calendar.component(.day, from: $0.startDate!) >= 24
        }) { calendar.component(.year, from: $0.startDate!) }
        add(.festive500, festive.values.count { $0.reduce(0) { $0 + $1.distance } >= 500_000 })

        // Weeks, Monday to Sunday.
        var weeks = Calendar(identifier: .iso8601)
        weeks.timeZone = calendar.timeZone
        let mondays = Set(days.compactMap { weeks.dateInterval(of: .weekOfYear, for: $0)?.start })
        add(.everyDayImHustling, mondays.count { monday in (0..<7).allSatisfy { active(monday, $0) } })
        add(.working9To5, mondays.count { monday in
            (0..<5).allSatisfy { active(monday, $0) } && ![-2, -1, 5, 6].contains { active(monday, $0) }
        })
        return result
    }
}
