import Foundation

/// Credentials of the user's own Strava API application, read from `StravaSecrets.plist`
/// (not in version control; see `StravaSecrets.example.plist` in the project root).
struct StravaConfig: Sendable {
    let clientID: String
    let clientSecret: String

    static let callbackScheme = "tileroam"
    static let redirectURI = "tileroam://localhost"

    static let bundled: StravaConfig? = {
        guard FeatureFlags.strava,
              let url = Bundle.main.url(forResource: "StravaSecrets", withExtension: "plist"),
              let dict = NSDictionary(contentsOf: url) as? [String: Any] else { return nil }
        let id = "\(dict["ClientID"] ?? "")".trimmingCharacters(in: .whitespaces)
        let secret = "\(dict["ClientSecret"] ?? "")".trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty, !secret.isEmpty, Int(id) != nil else { return nil }
        return StravaConfig(clientID: id, clientSecret: secret)
    }()

    var authorizeURL: URL {
        var c = URLComponents(string: "https://www.strava.com/oauth/authorize")!
        c.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "approval_prompt", value: "auto"),
            URLQueryItem(name: "scope", value: "read,activity:read_all"),
        ]
        return c.url!
    }
}
