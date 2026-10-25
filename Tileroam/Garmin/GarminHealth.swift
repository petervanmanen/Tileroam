import Foundation

/// Today's numbers from Garmin Connect for the widgets: last night's sleep, today's steps and
/// the current Body Battery. Shared by the app and the widget extension (which fetches them
/// itself, so the widgets stay current without opening the app).
struct GarminHealth: Codable, Sendable, Equatable {
    struct Sleep: Codable, Sendable, Equatable {
        /// The day the sleep ended, "2026-10-24" (Garmin files sleep under the wake-up day).
        var date: String
        var seconds: Int
        /// Garmin's sleep score, 0–100, when the watch gives one.
        var score: Int?
    }

    struct Steps: Codable, Sendable, Equatable {
        var date: String
        var count: Int
        var goal: Int?
    }

    struct BodyBattery: Codable, Sendable, Equatable {
        var level: Int
        /// When it was measured.
        var time: Date?
    }

    var sleep: Sleep?
    var steps: Steps?
    var bodyBattery: BodyBattery?
    var fetched: Date
}

/// Where the widgets' Garmin data lives: the key and access token in the shared Keychain group,
/// the last numbers in the app group, so each widget doesn't ask Garmin again.
enum GarminHealthStore {
    static let appGroup = "group.nl.petervanmanen.Tileroam"
    static let keyAccount = "garminPersonalApiKey"
    static let tokenAccount = "garminAccessToken"
    static let widgetKinds = ["GarminSleepWidget", "GarminStepsWidget", "GarminBodyBatteryWidget"]
    private static let cacheKey = "garmin.health"

    static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    /// Whether this build offers Garmin: Debug builds, TestFlight, and every build once
    /// `FeatureFlags.garminInAppStore` is on (the builds of `GarminSync.availability`). The widgets
    /// are only in the gallery then. Known here without the app: iOS reads the widgets' sizes
    /// when the app is installed or updated, often before it's opened, and keeps them.
    static var isOffered: Bool {
        #if DEBUG
        true
        #else
        FeatureFlags.garminInAppStore || isTestFlight
        #endif
    }

    /// TestFlight installs have a sandbox receipt. AppTransaction says the same, but only
    /// asynchronously; the deprecated receipt URL is read through key-value coding.
    private static var isTestFlight: Bool {
        (Bundle.main.value(forKey: "appStoreReceiptURL") as? URL)?.lastPathComponent == "sandboxReceipt"
    }

    static var key: String? {
        Keychain.load(account: keyAccount, accessGroup: Keychain.sharedGroup).map { String(decoding: $0, as: UTF8.self) }
    }

    static var cached: GarminHealth? {
        get { defaults?.data(forKey: cacheKey).flatMap { try? JSONDecoder().decode(GarminHealth.self, from: $0) } }
        set { defaults?.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: cacheKey) }
    }

    /// Forgets the numbers and the access token (on disconnecting).
    static func clear() {
        cached = nil
        Keychain.delete(account: tokenAccount, accessGroup: Keychain.sharedGroup)
    }

    struct SavedToken: Codable { var value: String; var expires: Date }

    /// A client with the access token kept in the shared Keychain, so the app and the widgets
    /// don't each ask for a new one.
    static func client(key: String, session: URLSession = .shared, base: URL = GarminClient.baseURL) -> GarminClient {
        let saved = Keychain.load(account: tokenAccount, accessGroup: Keychain.sharedGroup)
            .flatMap { try? JSONDecoder().decode(SavedToken.self, from: $0) }
        return GarminClient(key: key, session: session, base: base, token: saved.map { ($0.value, $0.expires) }) { value, expires in
            if let data = try? JSONEncoder().encode(SavedToken(value: value, expires: expires)) {
                Keychain.save(data, account: tokenAccount, accessGroup: Keychain.sharedGroup)
            }
        }
    }

    enum Failure: Error, Equatable { case notConnected, invalidKey, unavailable }

    /// The numbers, from the cache when they're at most `maxAge` old, else from Garmin. What
    /// Garmin doesn't answer keeps its cached value (last night's sleep stays until tonight's
    /// is there).
    static func current(maxAge: TimeInterval = 10 * 60, now: Date = .now,
                        fetch: (String, Date) async throws -> GarminHealth = { try await fetchHealth(key: $0, now: $1) }) async -> Result<GarminHealth, Failure> {
        let old = cached
        if let old, now.timeIntervalSince(old.fetched) < maxAge, old.fetched <= now { return .success(old) }
        guard let key else { return .failure(.notConnected) }
        do {
            var fresh = try await fetch(key, now)
            fresh.sleep = fresh.sleep ?? old?.sleep
            if fresh.steps == nil, old?.steps?.date == day(now) { fresh.steps = old?.steps }
            fresh.bodyBattery = fresh.bodyBattery ?? old?.bodyBattery
            cached = fresh
            return .success(fresh)
        } catch GarminError.invalidKey {
            return .failure(.invalidKey)
        } catch {
            return old.map { .success($0) } ?? .failure(.unavailable)
        }
    }

    /// Asks Garmin for today's numbers: three requests, at the same time.
    static func fetchHealth(key: String, now: Date, session: URLSession = .shared, base: URL = GarminClient.baseURL) async throws -> GarminHealth {
        let client = client(key: key, session: session, base: base)
        let today = day(now)
        // The token first, so the three requests don't each ask for one.
        _ = try await client.accessToken(now: now)
        // One that fails (no data yet) doesn't stop the others; a refused key stops all.
        @Sendable func data(_ path: String, _ query: [String: String] = [:]) async throws -> Data? {
            do { return try await client.json(path, query: query) } catch GarminError.invalidKey { throw GarminError.invalidKey } catch { return nil }
        }
        async let stepsData = data("usersummary-service/stats/steps/daily/\(today)/\(today)")
        async let batteryData = data("wellness-service/wellness/bodyBattery/reports/daily", ["startDate": today, "endDate": today])
        async let sleepData = data("sleep-service/sleep/dailySleep", ["date": today])
        var health = GarminHealth(fetched: now)
        if let data = try await stepsData, let steps = GarminHealthParser.steps(data) {
            health.steps = .init(date: today, count: steps.count, goal: steps.goal)
        }
        if let data = try await batteryData {
            health.bodyBattery = GarminHealthParser.bodyBattery(data).map { .init(level: $0.level, time: $0.time) }
        }
        if let data = try await sleepData, let sleep = GarminHealthParser.sleep(data) {
            health.sleep = .init(date: today, seconds: sleep.seconds, score: sleep.score)
        }
        return health
    }

    /// "2026-10-24" in the device's time zone, as Garmin's calendar dates.
    static func day(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
    }
}

/// Reads the numbers from Garmin's JSON. Garmin doesn't document these responses for the
/// Personal API, so the parser looks for the fields wherever they are (the same names as on
/// Garmin Connect's website) instead of decoding one fixed shape.
enum GarminHealthParser {
    static func steps(_ data: Data) -> (count: Int, goal: Int?)? {
        guard let json = try? JSONSerialization.jsonObject(with: data),
              let day = dictionaries(in: json).first(where: { $0["totalSteps"] != nil }),
              let count = int(day["totalSteps"]) else { return nil }
        return (count, int(day["stepGoal"]) ?? int(day["dailyStepGoal"]))
    }

    /// The last measured level of the day. The values array has a descriptor list that says
    /// which column is which ("timestamp", "bodyBatteryLevel", …).
    static func bodyBattery(_ data: Data) -> (level: Int, time: Date?)? {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        for report in dictionaries(in: json).reversed() {
            if let values = report["bodyBatteryValuesArray"] as? [[Any]] {
                let descriptors = (report["bodyBatteryValueDescriptorDTOList"] as? [[String: Any]]) ?? []
                func column(_ key: String) -> Int? {
                    descriptors.first { $0["bodyBatteryValueDescriptorKey"] as? String == key }
                        .flatMap { int($0["bodyBatteryValueDescriptorIndex"]) }
                }
                let timeColumn = column("timestamp") ?? 0
                for row in values.reversed() {
                    let levelColumn = column("bodyBatteryLevel") ?? (row.count >= 3 ? 2 : 1)
                    guard levelColumn < row.count, let level = int(row[levelColumn]) else { continue }
                    let time = timeColumn < row.count ? int(row[timeColumn]).map { Date(timeIntervalSince1970: Double($0) / 1000) } : nil
                    return (level, time)
                }
            }
            if let level = int(report["bodyBatteryMostRecentValue"]) { return (level, nil) }
        }
        return nil
    }

    static func sleep(_ data: Data) -> (seconds: Int, score: Int?)? {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        let all = dictionaries(in: json)
        guard let seconds = all.lazy.compactMap({ int($0["sleepTimeSeconds"]) }).first, seconds > 0 else { return nil }
        let score = all.lazy.compactMap { d -> Int? in
            if let scores = d["sleepScores"] as? [String: Any],
               let overall = scores["overall"] as? [String: Any], let value = int(overall["value"]) { return value }
            if let overall = d["overallSleepScore"] { return int((overall as? [String: Any])?["value"]) ?? int(overall) }
            return int(d["sleepScore"])
        }.first
        return (seconds, score)
    }

    /// Every dictionary in the JSON, outer ones first.
    static func dictionaries(in json: Any) -> [[String: Any]] {
        var result: [[String: Any]] = [], queue = [json]
        while !queue.isEmpty {
            let next = queue.removeFirst()
            if let d = next as? [String: Any] {
                result.append(d)
                queue += d.keys.sorted().compactMap { d[$0] }
            } else if let a = next as? [Any] {
                queue += a
            }
        }
        return result
    }

    static func int(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return number.intValue
    }
}
