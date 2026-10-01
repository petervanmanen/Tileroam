import Foundation

/// Settings of the Strava API application.
///
/// `StravaConfig.plist` (not in version control; see `StravaConfig.example.plist`) holds the
/// Client ID, which is not secret, and the URL of the token service (`backend/strava-auth`),
/// which keeps the Client Secret on the server. During development, a `ClientSecret` in
/// `StravaSecrets.plist` is used instead when no token service is configured; that file is
/// left out of Release builds.
struct StravaConfig: Sendable {
    let clientID: String
    /// Token exchange through the Worker (preferred).
    let tokenServiceURL: URL?
    /// Direct token exchange with Strava (development builds only).
    let clientSecret: String?

    static let callbackScheme = "tileroam"
    static let redirectURI = "tileroam://localhost"
    private static let scope = "read,activity:read_all"

    static let bundled: StravaConfig? = {
        guard FeatureFlags.strava else { return nil }
        let config = plist("StravaConfig")
        let secrets = plist("StravaSecrets")
        let id = string(config["ClientID"]) ?? string(secrets["ClientID"]) ?? ""
        let service = string(config["TokenServiceURL"]).flatMap(URL.init(string:))
        #if DEBUG
        let secret = string(secrets["ClientSecret"])
        #else
        let secret: String? = nil
        #endif
        guard Int(id) != nil, service != nil || secret != nil else { return nil }
        return StravaConfig(clientID: id, tokenServiceURL: service, clientSecret: service == nil ? secret : nil)
    }()

    private static func plist(_ name: String) -> [String: Any] {
        guard let url = Bundle.main.url(forResource: name, withExtension: "plist"),
              let dict = NSDictionary(contentsOf: url) as? [String: Any] else { return [:] }
        return dict
    }

    private static func string(_ value: Any?) -> String? {
        guard let s = (value as? String)?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        return s
    }

    private func authorizeURL(_ base: String, state: String) -> URL {
        var c = URLComponents(string: base)!
        c.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "approval_prompt", value: "auto"),
            URLQueryItem(name: "scope", value: Self.scope),
            URLQueryItem(name: "state", value: state),
        ]
        return c.url!
    }

    /// Opens the Strava app's own "Authorize" screen.
    func appAuthorizeURL(state: String) -> URL {
        authorizeURL("strava://oauth/mobile/authorize", state: state)
    }

    /// Strava's mobile web login, used when the Strava app is not installed.
    func webAuthorizeURL(state: String) -> URL {
        authorizeURL("https://www.strava.com/oauth/mobile/authorize", state: state)
    }
}
