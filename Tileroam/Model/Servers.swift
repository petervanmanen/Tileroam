import Foundation

/// The servers the app talks to, from `Servers.plist` (in the repository; change them there, not
/// in code).
enum Servers {
    /// Route planning map data: the public URL of the Cloudflare R2 bucket (docs/ROUTING.md).
    static let routingTiles = url("RoutingTilesURL")
    /// The Strava token service and event queue (backend/strava-auth): `/token`, `/events-key`,
    /// `/events`.
    static let stravaService = url("StravaServiceURL")

    private static let values: [String: String] = {
        guard let file = Bundle.main.url(forResource: "Servers", withExtension: "plist"),
              let dict = NSDictionary(contentsOf: file) as? [String: Any] else { return [:] }
        return dict.compactMapValues { $0 as? String }
    }()

    private static func url(_ key: String) -> URL {
        guard let text = values[key], let url = URL(string: text), url.scheme == "https" else {
            // Servers.plist is part of the app; a missing entry is a build mistake (ServersTests).
            assertionFailure("Servers.plist has no https URL for \(key)")
            return URL(string: "https://invalid.invalid")!
        }
        return url
    }
}
