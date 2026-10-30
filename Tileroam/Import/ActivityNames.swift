import Foundation

/// Names from an activity's source that replace the one in its file name: a Garmin activity is
/// saved once as "2026-10-20 Morning Ride Garmin 123456-ab12cd34.fit", and renamed later on Garmin
/// Connect. Per library file the current name, kept in iCloud's key-value store (like `Deletions`)
/// so every device shows it, also one without the Garmin connection.
enum ActivityNames {
    private static let key = "activityNames"
    /// iCloud's key-value store holds at most 1 MB (shared with `Deletions`): about 100 bytes a name.
    static let limit = 4_000

    /// Per library file name, its name.
    static func all(local: KeyValueStore = UserDefaults.standard,
                    cloud: KeyValueStore = NSUbiquitousKeyValueStore.default) -> [String: String] {
        let a = local.object(forKey: key) as? [String: String] ?? [:]
        let b = cloud.object(forKey: key) as? [String: String] ?? [:]
        // Another device's change wins: it renamed later, or it's the same name.
        let all = a.merging(b) { _, theirs in theirs }
        if all != a { local.set(all, forKey: key) }
        if all != b { cloud.set(all, forKey: key) }
        return all
    }

    /// Stores names (per library file name); returns whether anything changed.
    @discardableResult
    static func set(_ names: [String: String], local: KeyValueStore = UserDefaults.standard,
                    cloud: KeyValueStore = NSUbiquitousKeyValueStore.default) -> Bool {
        var all = self.all(local: local, cloud: cloud)
        let before = all
        all.merge(names) { _, new in new }
        if all.count > limit {
            for file in all.keys.sorted().prefix(all.count - limit) where names[file] == nil { all[file] = nil }
        }
        guard all != before else { return false }
        local.set(all, forKey: key)
        cloud.set(all, forKey: key)
        return true
    }

    /// The activity with its source's name, if there is one: also for what the name tells
    /// (a virtual ride, a Zwift ride, the Pretzel badge).
    static func apply(_ names: [String: String], to activity: Activity, prefix: String) -> Activity {
        guard activity.id.hasPrefix(prefix), let name = names[String(activity.id.dropFirst(prefix.count))],
              !name.isEmpty, name != activity.name else { return activity }
        var a = activity
        a.name = name
        if Activity.looksVirtual(name: name) { a.isVirtual = true }
        if name.lowercased().hasPrefix("zwift") { a.isZwift = true }
        return a
    }
}
