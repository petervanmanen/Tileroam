import Foundation

struct StravaTokens: Codable, Sendable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: TimeInterval
    var athleteID: Int
    var athleteName: String
    /// Lets the app read this athlete's webhook events from the token service (see `events(since:)`).
    var eventsKey: String?

    private static let account = "stravaTokens"

    static func load() -> StravaTokens? {
        Keychain.load(account: account).flatMap { try? JSONDecoder().decode(StravaTokens.self, from: $0) }
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { Keychain.save(data, account: Self.account) }
    }

    static func delete() {
        Keychain.delete(account: account)
    }
}

/// A Strava webhook event, queued by the token service: access revoked, or an activity created
/// or deleted.
struct StravaEvent: Decodable, Sendable, Equatable {
    let type: String
    /// Unix time of the event.
    let time: Int
    /// The activity, for activity events.
    let activity: Int?
}

/// Full-resolution streams of one activity.
struct StravaStream: Sendable {
    var points: [GeoPoint]
    /// Seconds since start, per point.
    var times: [Double]
    /// Meters, per point (may be empty).
    var altitudes: [Double]
}

struct StravaSummary: Decodable, Sendable {
    struct MapInfo: Decodable, Sendable {
        let summaryPolyline: String?
    }

    let id: Int
    let name: String
    let sportType: String?
    let type: String?
    let startDate: Date?
    let distance: Double?
    let elapsedTime: Double?
    let movingTime: Double?
    /// Watts; Strava estimates it for rides without a power meter (`deviceWatts` false).
    let averageWatts: Double?
    let deviceWatts: Bool?
    let trainer: Bool?
    let map: MapInfo?
    /// Metres climbed.
    let totalElevationGain: Double?
}

enum StravaError: LocalizedError {
    /// Turns Strava's `{"message": …, "errors": [{"resource", "field", "code"}]}` into readable text.
    static func explain(_ body: String) -> String {
        struct Response: Decodable {
            struct Item: Decodable { let resource: String?; let field: String?; let code: String? }
            let message: String?
            let errors: [Item]?
        }
        guard let r = try? JSONDecoder().decode(Response.self, from: Data(body.utf8)) else { return String(body.prefix(200)) }
        let details = (r.errors ?? []).map { [$0.resource, $0.field].compactMap { $0 }.joined(separator: " ") + ": " + ($0.code ?? "") }
        return ([r.message ?? "Error"] + (details.isEmpty ? [] : ["(" + details.joined(separator: ", ") + ")"])).joined(separator: " ")
    }

    case notConnected
    case rateLimited(until: Date)
    case unauthorized
    case loginFailed(String)
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .notConnected: String(localized: "Not connected to Strava.")
        case .rateLimited(let until): String(localized: "Strava rate limit reached until \(until.formatted(date: .omitted, time: .shortened)).")
        case .unauthorized: String(localized: "Strava access was revoked. Please connect again.")
        case .loginFailed(let reason): String(localized: "Strava login failed: \(reason)")
        case .http(let code, let body): String(localized: "Strava error \(code): \(Self.explain(body))")
        }
    }
}

/// Talks to the Strava API directly from the app (no server).
actor StravaClient {
    let config: StravaConfig
    private var tokens: StravaTokens?
    /// Requests are not sent before this date (rate limit).
    private(set) var pausedUntil: Date?

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init(config: StravaConfig) {
        self.config = config
        self.tokens = StravaTokens.load()
    }

    // MARK: Authentication

    /// Handles the `tileroam://localhost?code=…` callback of the OAuth flow.
    /// Random value sent with the login request and checked on return (protects against forged callbacks).
    private var pendingState: String?

    func beginLogin() -> String {
        let state = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        pendingState = state
        return state
    }

    func completeLogin(callback: URL) async throws -> StravaTokens {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard let expected = pendingState, items.first(where: { $0.name == "state" })?.value == expected else {
            throw StravaError.loginFailed(String(localized: "The login request expired. Please try again."))
        }
        pendingState = nil
        if let error = items.first(where: { $0.name == "error" })?.value { throw StravaError.loginFailed(error) }
        guard let code = items.first(where: { $0.name == "code" })?.value else { throw StravaError.loginFailed("no code") }
        let scope = items.first(where: { $0.name == "scope" })?.value ?? ""
        guard scope.contains("activity:read") else {
            throw StravaError.loginFailed(String(localized: "Please allow access to your activities."))
        }
        let response = try await tokenRequest(["code": code, "grant_type": "authorization_code"])
        let name = [response.athlete?.firstname, response.athlete?.lastname].compactMap { $0 }.joined(separator: " ")
        let t = StravaTokens(accessToken: response.accessToken, refreshToken: response.refreshToken,
                             expiresAt: response.expiresAt, athleteID: response.athlete?.id ?? 0, athleteName: name,
                             eventsKey: response.tileroamEventsKey)
        t.save()
        tokens = t
        return t
    }

    func disconnect() async {
        if let token = tokens?.accessToken {
            var request = URLRequest(url: URL(string: "https://www.strava.com/oauth/deauthorize")!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            _ = try? await URLSession.shared.data(for: request)
        }
        StravaTokens.delete()
        tokens = nil
    }

    private struct TokenResponse: Decodable {
        struct Athlete: Decodable {
            let id: Int
            let firstname: String?
            let lastname: String?
        }

        let accessToken: String
        let refreshToken: String
        let expiresAt: TimeInterval
        let athlete: Athlete?
        let tileroamEventsKey: String?
    }

    /// Exchanges a code or refresh token through the token service, which adds the Client Secret.
    private func tokenRequest(_ params: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: config.tokenServiceURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: params)
        let (data, _) = try await send(request)
        return try decoder.decode(TokenResponse.self, from: data)
    }

    private func accessToken() async throws -> String {
        guard var t = tokens else { throw StravaError.notConnected }
        if t.expiresAt - 300 > Date.now.timeIntervalSince1970 { return t.accessToken }
        let response = try await tokenRequest(["refresh_token": t.refreshToken, "grant_type": "refresh_token"])
        t.accessToken = response.accessToken
        t.refreshToken = response.refreshToken
        t.expiresAt = response.expiresAt
        t.save()
        tokens = t
        return t.accessToken
    }

    // MARK: Webhook events

    /// The athlete's webhook events after `since` (Unix time), oldest first. Empty when the token
    /// service doesn't keep events (an older Worker).
    func events(since: Int) async throws -> [StravaEvent] {
        guard var t = tokens else { throw StravaError.notConnected }
        let base = config.tokenServiceURL.deletingLastPathComponent()
        if t.eventsKey == nil {
            // Logged in before the token service handed out events keys: ask for one.
            struct KeyResponse: Decodable { let key: String }
            var request = URLRequest(url: base.appending(path: "events-key"))
            request.httpMethod = "POST"
            request.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
            guard let (data, _) = try? await send(request),
                  let key = try? decoder.decode(KeyResponse.self, from: data).key else { return [] }
            t = tokens ?? t
            t.eventsKey = key
            t.save()
            tokens = t
        }
        var c = URLComponents(url: base.appending(path: "events"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "athlete", value: String(t.athleteID)),
                        URLQueryItem(name: "key", value: t.eventsKey),
                        URLQueryItem(name: "since", value: String(since))]
        struct EventsResponse: Decodable { let events: [StravaEvent] }
        guard let (data, _) = try? await send(URLRequest(url: c.url!)) else { return [] }
        return try decoder.decode(EventsResponse.self, from: data).events
    }

    // MARK: API

    /// One page (max 200) of activities, oldest first when `after` is given.
    func activities(page: Int, after: Date?) async throws -> [StravaSummary] {
        var query = [URLQueryItem(name: "per_page", value: "200"), URLQueryItem(name: "page", value: String(page))]
        if let after { query.append(URLQueryItem(name: "after", value: String(Int(after.timeIntervalSince1970)))) }
        return try decoder.decode([StravaSummary].self, from: try await get("athlete/activities", query))
    }

    /// Full-resolution GPS, time and altitude streams, or nil when the activity has no GPS.
    func stream(activityID: Int) async throws -> StravaStream? {
        struct Streams: Decodable {
            struct Pairs: Decodable { let data: [[Double]] }
            struct Values: Decodable { let data: [Double] }
            let latlng: Pairs?
            let time: Values?
            let altitude: Values?
        }
        do {
            let data = try await get("activities/\(activityID)/streams",
                                     [URLQueryItem(name: "keys", value: "latlng,time,altitude"),
                                      URLQueryItem(name: "key_by_type", value: "true")])
            let streams = try decoder.decode(Streams.self, from: data)
            guard let latlng = streams.latlng?.data, !latlng.isEmpty else { return nil }
            var stream = StravaStream(points: [], times: [], altitudes: [])
            let times = streams.time?.data ?? []
            let altitudes = streams.altitude?.data ?? []
            for (i, pair) in latlng.enumerated() where pair.count == 2 {
                stream.points.append(GeoPoint(lat: pair[0], lon: pair[1]))
                stream.times.append(i < times.count ? times[i] : Double(i))
                if altitudes.count == latlng.count { stream.altitudes.append(altitudes[i]) }
            }
            return stream
        } catch StravaError.http(404, _) {
            return nil
        }
    }

    private func get(_ path: String, _ query: [URLQueryItem]) async throws -> Data {
        var c = URLComponents(string: "https://www.strava.com/api/v3/\(path)")!
        c.queryItems = query
        var request = URLRequest(url: c.url!)
        request.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
        do {
            return try await send(request).0
        } catch StravaError.http(401, _) {
            throw StravaError.unauthorized
        }
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if let pausedUntil, pausedUntil > .now { throw StravaError.rateLimited(until: pausedUntil) }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw StravaError.http(0, "no response") }

        if let until = Self.pauseDate(headers: http.allHeaderFields, status: http.statusCode, now: .now) {
            pausedUntil = max(pausedUntil ?? until, until)
        }
        if http.statusCode == 429 { throw StravaError.rateLimited(until: pausedUntil ?? .now.addingTimeInterval(900)) }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(decoding: data, as: UTF8.self)
            Self.logError(request: request, response: http, body: body)
            throw StravaError.http(http.statusCode, body)
        }
        return (data, http)
    }

    /// Keeps the last failed request for diagnosis (no tokens or secrets); development builds only.
    private static func logError(request: URLRequest, response: HTTPURLResponse, body: String) {
        #if DEBUG
        var url = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
        url.queryItems = url.queryItems?.filter { !["code", "refresh_token", "key"].contains($0.name) }
        let headers = response.allHeaderFields.map { "\($0.key): \($0.value)" }.sorted().joined(separator: "\n")
        let text = "\(Date.now)\n\(request.httpMethod ?? "GET") \(url.string ?? "")\nstatus \(response.statusCode)\n\n\(headers)\n\n\(body)\n"
        try? FileManager.default.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
        try? text.write(to: URL.applicationSupportDirectory.appending(path: "strava-last-error.txt"), atomically: true, encoding: .utf8)
        #endif
    }

    /// When to stop sending requests, based on Strava's rate limit headers:
    /// `X-(Read)RateLimit-Limit: 100,1000` and `X-(Read)RateLimit-Usage: 12,340` (15 minutes, daily).
    static func pauseDate(headers: [AnyHashable: Any], status: Int, now: Date) -> Date? {
        func values(_ name: String) -> [Int]? {
            let key = headers.keys.first { ($0 as? String)?.caseInsensitiveCompare(name) == .orderedSame }
            guard let key, let raw = headers[key] as? String else { return nil }
            let v = raw.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            return v.count == 2 ? v : nil
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let nextDay = calendar.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime)!
            .addingTimeInterval(60)
        let nextQuarter = Date(timeIntervalSince1970: (now.timeIntervalSince1970 / 900).rounded(.up) * 900 + 30)

        var result: Date?
        for prefix in ["X-ReadRateLimit", "X-RateLimit"] {
            guard let limit = values("\(prefix)-Limit"), let usage = values("\(prefix)-Usage") else { continue }
            if usage[1] >= limit[1] - 1 {
                result = max(result ?? nextDay, nextDay)
            } else if usage[0] >= limit[0] - 1 {
                result = max(result ?? nextQuarter, nextQuarter)
            }
        }
        if status == 429, result == nil { result = nextQuarter }
        return result
    }
}
