import Foundation

/// An activity in Garmin Connect's activity list (the fields Tileroam uses).
struct GarminActivity: Decodable, Sendable, Equatable {
    let activityId: Int64
    let activityName: String?
    /// "2026-10-20 07:12:33", local time of the activity.
    let startTimeLocal: String?
}

enum GarminError: LocalizedError, Equatable {
    /// The token service refused the key: wrong, revoked or expired.
    case invalidKey
    /// Too many requests (429); `retryAfter` is how long Garmin asks to wait, when it says.
    case rateLimited(retryAfter: TimeInterval?)
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .invalidKey: String(localized: "Garmin didn't accept the key. It may have expired: create a new one on Garmin Connect and connect again.")
        case .rateLimited: String(localized: "Garmin asks to slow down. Tileroam continues later.")
        case .http(let code): String(localized: "Garmin error \(code).")
        }
    }
}

/// Garmin Connect's Personal API (developer.garmin.com/gc-developer-program/personal): the user's
/// own personal API key, made on Garmin Connect, gives access tokens valid for 24 hours (no
/// refresh tokens: the key gives a new one). Read only: the activity list and each activity's
/// original file. The same calls as Garmin's own client, garmin/connect-personal-api-python.
actor GarminClient {
    static let baseURL = URL(string: "https://personal.connectapi.garmin.com")!
    /// Where the user makes a key (Garmin Connect → Settings → Personal API).
    static let keyPage = URL(string: "https://connect.garmin.com/app/settings/personalApiToken")!

    private let key: String
    private let session: URLSession
    private let base: URL
    private var token: (value: String, expires: Date)?
    /// Called with each new access token, to keep it for the next client (the widgets run in
    /// their own process, a few times an hour).
    private let tokenChanged: @Sendable (String, Date) -> Void

    init(key: String, session: URLSession = .shared, base: URL = GarminClient.baseURL,
         token: (value: String, expires: Date)? = nil, tokenChanged: @escaping @Sendable (String, Date) -> Void = { _, _ in }) {
        self.key = key
        self.session = session
        self.base = base
        self.token = token
        self.tokenChanged = tokenChanged
    }

    /// A valid access token: the cached one until an hour before it expires, else a new one.
    func accessToken(now: Date = .now) async throws -> String {
        if let token, token.expires.timeIntervalSince(now) > 3600 { return token.value }
        var request = URLRequest(url: base.appending(path: "personalapitoken-service/personal-api/personal-api-key/token"))
        request.httpMethod = "POST"
        request.setValue("ApiKey \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 || status == 403 { throw GarminError.invalidKey }
        if status == 429 { throw GarminError.rateLimited(retryAfter: Self.retryAfter(response)) }
        guard (200..<300).contains(status) else { throw GarminError.http(status) }
        let value = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw GarminError.invalidKey }
        let expires = Self.expiry(ofJWT: value) ?? now.addingTimeInterval(23 * 3600)
        token = (value, expires)
        tokenChanged(value, expires)
        return value
    }

    /// The `exp` claim of a JWT (the access token is one), if it can be read.
    static func expiry(ofJWT token: String) -> Date? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = (json["exp"] as? NSNumber)?.doubleValue else { return nil }
        return Date(timeIntervalSince1970: exp)
    }

    /// One page of the activity list, newest first.
    func activities(start: Int, limit: Int) async throws -> [GarminActivity] {
        var c = URLComponents(url: base.appending(path: "activitylist-service/activities/search/activities"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "start", value: String(start)), URLQueryItem(name: "limit", value: String(limit))]
        let data = try await get(c.url!, accept: "application/json")
        return try JSONDecoder().decode([GarminActivity].self, from: data)
    }

    /// The activity's original file as Garmin delivers it: a ZIP (with the .fit file inside).
    func originalFile(_ id: Int64) async throws -> Data {
        try await get(base.appending(path: "download-service/files/activity/\(id)"),
                      accept: "application/zip, application/x-zip-compressed, application/octet-stream")
    }

    /// A JSON resource, e.g. "usersummary-service/stats/steps/daily/2026-10-24/2026-10-24".
    func json(_ path: String, query: [String: String] = [:]) async throws -> Data {
        var c = URLComponents(url: base.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { c.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } }
        return try await get(c.url!, accept: "application/json")
    }

    private func get(_ url: URL, accept: String, retried: Bool = false) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401, !retried {
            token = nil // expired early: once more with a new token
            return try await get(url, accept: accept, retried: true)
        }
        if status == 401 || status == 403 { throw GarminError.invalidKey }
        if status == 429 { throw GarminError.rateLimited(retryAfter: Self.retryAfter(response)) }
        guard (200..<300).contains(status) else { throw GarminError.http(status) }
        return data
    }

    /// The Retry-After header of a 429: seconds ("120") or an HTTP date.
    static func retryAfter(_ response: URLResponse, now: Date = .now) -> TimeInterval? {
        guard let value = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After")?
                .trimmingCharacters(in: .whitespaces) else { return nil }
        if let seconds = TimeInterval(value) { return max(0, seconds) }
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = .gmt
        format.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return format.date(from: value).map { max(0, $0.timeIntervalSince(now)) }
    }
}
