import Foundation

/// Combines activities from several sources (folder .fit files, Strava) and removes duplicates.
///
/// The same workout often exists several times: recorded by a watch and Zwift, uploaded to
/// Strava twice, and exported again by HealthFit. Copies can start minutes apart, so two
/// activities are considered the same when they overlap in time.
enum ActivityMerge {
    /// Activities starting within this many seconds of each other are always the same.
    static let tolerance: TimeInterval = 120

    static func merge(_ activities: [Activity]) -> [Activity] {
        var undated = [Activity]()
        var dated = [(start: Date, activity: Activity)]()
        for a in activities {
            if let date = a.startDate { dated.append((date, a)) } else { undated.append(a) }
        }
        dated.sort { $0.start != $1.start ? $0.start < $1.start : $0.activity.id < $1.activity.id }

        var clusters = [(members: [Activity], end: Date)]()
        // Clusters that can still overlap with activities starting from now on.
        var open = [Int]()
        for (start, a) in dated {
            open.removeAll { clusters[$0].end < start.addingTimeInterval(-tolerance) }
            let end = start.addingTimeInterval(a.elapsedTime ?? 0)
            if let i = open.first(where: { i in clusters[i].members.contains { isSameWorkout($0, a) } }) {
                clusters[i].members.append(a)
                clusters[i].end = max(clusters[i].end, end)
            } else {
                clusters.append(([a], end))
                open.append(clusters.count - 1)
            }
        }
        return clusters.map { best(of: $0.members) } + undated
    }

    /// Best GPS first, then the longest distance (some copies of indoor rides have 0 km).
    static func best(of members: [Activity]) -> Activity {
        var best = members.max { ($0.quality, $0.distance) < ($1.quality, $1.distance) }!
        // One copy known to be virtual (Strava VirtualRide, Zwift .fit) makes the workout virtual.
        if members.contains(where: { $0.isVirtual == true }) { best.isVirtual = true }
        // Details another copy may have (a Strava summary has no power; a watch file has).
        best.averagePower = best.averagePower ?? members.lazy.compactMap(\.averagePower).first
        best.movingTime = best.movingTime ?? members.lazy.compactMap(\.movingTime).first
        best.elapsedTime = best.elapsedTime ?? members.lazy.compactMap(\.elapsedTime).first
        return best
    }

    static func isSameWorkout(_ a: Activity, _ b: Activity) -> Bool {
        guard let s1 = a.startDate, let s2 = b.startDate else { return false }
        if abs(s1.timeIntervalSince(s2)) <= tolerance { return true }
        guard let d1 = a.elapsedTime, let d2 = b.elapsedTime, d1 > 0, d2 > 0 else { return false }
        let overlap = min(s1 + d1, s2 + d2).timeIntervalSince(max(s1, s2))
        guard overlap > 0 else { return false }
        let ratio = overlap / min(d1, d2)
        let c1 = category(a.sport), c2 = category(b.sport)
        return ratio >= 0.8 || (ratio >= 0.5 && (c1 == c2 || c1 == "other" || c2 == "other"))
    }

    /// Fast "is this workout already in that list" lookups.
    struct Index {
        private let sorted: [Activity]

        init(_ activities: [Activity]) {
            sorted = activities.filter { $0.startDate != nil }.sorted { $0.startDate! < $1.startDate! }
        }

        func contains(_ a: Activity) -> Bool {
            guard let start = a.startDate else { return false }
            // Candidates start at most a day before and before this one ends.
            let from = start.addingTimeInterval(-24 * 3600)
            let to = start.addingTimeInterval((a.elapsedTime ?? 0) + ActivityMerge.tolerance)
            var low = 0, high = sorted.count
            while low < high {
                let mid = (low + high) / 2
                if sorted[mid].startDate! < from { low = mid + 1 } else { high = mid }
            }
            var i = low
            while i < sorted.count, sorted[i].startDate! <= to {
                if ActivityMerge.isSameWorkout(sorted[i], a) { return true }
                i += 1
            }
            return false
        }
    }

    private static func category(_ sport: String) -> String {
        switch sport {
        case "Cycling", "E-biking": "bike"
        case "Running": "run"
        case "Walking", "Hiking": "foot"
        default: "other"
        }
    }
}
