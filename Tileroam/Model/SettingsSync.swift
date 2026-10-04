import Foundation

/// A key-value store: UserDefaults or iCloud's NSUbiquitousKeyValueStore (and, in tests, two
/// separate UserDefaults).
protocol KeyValueStore: AnyObject {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
}

extension UserDefaults: KeyValueStore {}
extension NSUbiquitousKeyValueStore: KeyValueStore {}

/// Keeps a few settings the same on all the user's devices through iCloud's key-value store.
/// UserDefaults stays the source the app reads (`@AppStorage`); changes are copied to iCloud,
/// and changes from other devices are copied back.
@MainActor
enum SettingsSync {
    static let keys = ["mapStyle", Challenges.key]

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

    /// Copies changed synced keys from iCloud to this device. Returns the keys that changed here.
    @discardableResult
    static func pull(_ changed: [String], from cloud: KeyValueStore = NSUbiquitousKeyValueStore.default,
                     to local: KeyValueStore = UserDefaults.standard) -> [String] {
        var applied = [String]()
        for key in changed where keys.contains(key) {
            guard let value = cloud.object(forKey: key), !same(value, local.object(forKey: key)) else { continue }
            local.set(value, forKey: key)
            applied.append(key)
        }
        return applied
    }

    /// Copies this device's synced settings to iCloud when they differ. Returns the keys written.
    @discardableResult
    static func push(from local: KeyValueStore = UserDefaults.standard,
                     to cloud: KeyValueStore = NSUbiquitousKeyValueStore.default) -> [String] {
        var written = [String]()
        for key in keys {
            guard let value = local.object(forKey: key), !same(value, cloud.object(forKey: key)) else { continue }
            cloud.set(value, forKey: key)
            written.append(key)
        }
        return written
    }

    private static func same(_ a: Any, _ b: Any?) -> Bool {
        guard let b else { return false }
        return (a as? NSObject)?.isEqual(b) ?? false
    }
}
