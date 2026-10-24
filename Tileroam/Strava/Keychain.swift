import Foundation
import Security

/// Small secrets in the Keychain. `accessGroup` nil keeps an item to the app; the app group
/// (`sharedGroup`) shares it with the widgets.
enum Keychain {
    private static let service = "nl.petervanmanen.Tileroam"
    /// The app group, which is also a Keychain access group of the app and the widget extension.
    static let sharedGroup = "group.nl.petervanmanen.Tileroam"

    static func save(_ data: Data, account: String, accessGroup: String? = nil) {
        delete(account: account, accessGroup: accessGroup)
        var query = base(account, accessGroup)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        query[kSecValueData as String] = data
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load(account: String, accessGroup: String? = nil) -> Data? {
        var query = base(account, accessGroup)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    static func delete(account: String, accessGroup: String? = nil) {
        SecItemDelete(base(account, accessGroup) as CFDictionary)
    }

    private static func base(_ account: String, _ accessGroup: String?) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        return query
    }
}
