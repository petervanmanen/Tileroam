import Foundation

/// Keeps a few settings the same on all the user's devices through iCloud's key-value store.
/// UserDefaults stays the source the app reads (`@AppStorage`); changes are copied to iCloud,
/// and changes from other devices are copied back.
@MainActor
enum SettingsSync {
    static let keys = ["tileZoom", "mapStyle"]

    private static var observers: [NSObjectProtocol] = []

    static func start() {
        guard observers.isEmpty else { return }
        let cloud = NSUbiquitousKeyValueStore.default
        observers.append(NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: cloud, queue: .main
        ) { note in
            let changed = note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]
            MainActor.assumeIsolated { pull(changed ?? keys) }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: UserDefaults.standard, queue: .main
        ) { _ in
            MainActor.assumeIsolated { push() }
        })
        cloud.synchronize()
        // Settings another device already shared win; the rest is shared from this device.
        pull(keys)
        push()
    }

    private static func pull(_ changed: [String]) {
        let cloud = NSUbiquitousKeyValueStore.default, defaults = UserDefaults.standard
        for key in changed where keys.contains(key) {
            guard let value = cloud.object(forKey: key), !same(value, defaults.object(forKey: key)) else { continue }
            defaults.set(value, forKey: key)
        }
    }

    private static func push() {
        let cloud = NSUbiquitousKeyValueStore.default, defaults = UserDefaults.standard
        for key in keys {
            guard let value = defaults.object(forKey: key), !same(value, cloud.object(forKey: key)) else { continue }
            cloud.set(value, forKey: key)
        }
    }

    private static func same(_ a: Any, _ b: Any?) -> Bool {
        guard let b else { return false }
        return (a as? NSObject)?.isEqual(b) ?? false
    }
}
