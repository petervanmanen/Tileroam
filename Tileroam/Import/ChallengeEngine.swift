import CryptoKit
import Foundation
import Observation

/// The user's challenges (`CustomChallenge`, read from the Challenges folder by `ChallengeFiles`):
/// holds them, checks activities whose stored results are missing or out of date, and adds the
/// stored results up (progress per challenge, countries for Globetrotter, badges). `ActivityStore`
/// owns the activities and decides when to check; this type knows how.
@MainActor
@Observable
final class ChallengeEngine {
    /// The challenges, in the order of their names.
    private(set) var challenges: [CustomChallenge] = []
    /// Files that couldn't be read, or only partly.
    private(set) var problems: [Problem] = []
    /// Per challenge id.
    private(set) var progress: [String: ChallengeProgress] = [:]
    /// How often each badge was earned (see `BadgeRules`); indoor activities count too.
    private(set) var badges: [Badge: Int] = [:]
    /// The countries of the world with activities (not virtual ones), for Globetrotter.
    private(set) var worldCountries: Set<String> = []

    struct Problem: Identifiable, Sendable, Equatable {
        let fileName: String
        let message: String
        /// The challenge is used anyway (some features were skipped).
        let isWarning: Bool
        var id: String { fileName }
    }

    func challenge(_ id: String) -> CustomChallenge? { challenges.first { $0.id == id } }
    func progress(of id: String) -> ChallengeProgress { progress[id] ?? ChallengeProgress() }

    /// Checkpoints per route of a cover-route challenge, once prepared.
    func routeCounts(_ id: String) -> [String: Int] { prepared[id]?.counts ?? [:] }

    /// Called when the routes' checkpoints are ready, so the owner can check its activities.
    @ObservationIgnored var onPrepared: () -> Void = {}

    /// A check pass is running (one at a time).
    @ObservationIgnored private(set) var isChecking = false

    // MARK: Files

    /// The files read before, by name: reading a file again is quick, parsing a big one isn't.
    @ObservationIgnored private var parsed: [String: Parsed] = [:]

    private struct Parsed: Sendable {
        let digest: String
        let challenge: CustomChallenge?
        let problem: Problem?
    }

    /// Reads the Challenges folder again. Returns whether the challenges changed.
    func reload() async -> Bool {
        let previous = parsed
        let (list, problems, cache) = await Task.detached(priority: .utility) {
            let (files, unreadable) = ChallengeFiles.read()
            var cache = [String: Parsed](), list = [CustomChallenge](), problems = [Problem]()
            for (name, data) in files.sorted(by: { $0.key < $1.key }) {
                let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                let entry = previous[name].flatMap { $0.digest == digest ? $0 : nil } ?? Self.parse(data, name: name, digest: digest)
                cache[name] = entry
                if let p = entry.problem { problems.append(p) }
                guard let c = entry.challenge else { continue }
                if let other = list.first(where: { $0.id == c.id }) {
                    problems.append(Problem(fileName: name, message: String(localized: "Same id as \(other.fileName): \"\(c.id)\"."), isWarning: false))
                } else {
                    list.append(c)
                }
            }
            problems += unreadable.map { Problem(fileName: $0, message: String(localized: "Not downloaded from iCloud yet."), isWarning: false) }
            return (list.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }, problems, cache)
        }.value
        parsed = cache
        if problems != self.problems { self.problems = problems }
        guard list.map(\.key) != challenges.map(\.key) || list.map(\.fileName) != challenges.map(\.fileName) else { return false }
        challenges = list
        progress = progress.filter { id, _ in list.contains { $0.id == id } }
        return true
    }

    nonisolated private static func parse(_ data: Data, name: String, digest: String) -> Parsed {
        do {
            let (challenge, skipped) = try CustomChallenge.parse(data, fileName: name)
            let warning = skipped > 0
                ? Problem(fileName: name, message: String(localized: "\(skipped) features skipped: no id or name, or not a Point or line."), isWarning: true)
                : nil
            return Parsed(digest: digest, challenge: challenge, problem: warning)
        } catch {
            return Parsed(digest: digest, challenge: nil,
                          problem: Problem(fileName: name, message: error.localizedDescription, isWarning: false))
        }
    }

    /// Deletes a challenge's file (on all devices, with iCloud).
    func remove(_ challenge: CustomChallenge) async {
        let name = challenge.fileName
        await Task.detached(priority: .userInitiated) { ChallengeFiles.remove(name) }.value
        _ = await reload()
    }

    // MARK: Prepared routes

    /// The cover routes' checkpoints, per challenge id, with the key they were made for.
    @ObservationIgnored private var prepared: [String: RouteMatcher.Prepared] = [:]
    @ObservationIgnored private var preparedKeys: [String: String] = [:]
    @ObservationIgnored private var preparing: Task<Void, Never>?

    /// The challenges with their routes' checkpoints; nil while the checkpoints are being
    /// prepared (`onPrepared` is called when they're ready).
    var current: ChallengeResults.Current? {
        let routes = challenges.filter(\.isCoverRoutes)
        guard routes.allSatisfy({ preparedKeys[$0.id] == $0.key }) else {
            prepareRoutes(routes)
            return nil
        }
        return ChallengeResults.Current(challenges: challenges, prepared: prepared.filter { id, _ in routes.contains { $0.id == id } })
    }

    /// Prepares the checkpoints of the cover routes in the background (seconds for thousands of
    /// routes on an iPad: on the main thread it froze the app).
    private func prepareRoutes(_ routes: [CustomChallenge]) {
        guard preparing == nil else { return }
        let needed = routes.filter { preparedKeys[$0.id] != $0.key }
        preparing = Task {
            let made = await Task.detached(priority: .utility) {
                needed.map { ($0.id, $0.key, RouteMatcher.Prepared($0.items, spacing: $0.spacing)) }
            }.value
            for (id, key, p) in made {
                prepared[id] = p
                preparedKeys[id] = key
            }
            preparing = nil
            onPrepared()
        }
    }

    // MARK: Checking and adding up

    /// Checks the activities whose results are missing or out of date for `current`, in the
    /// background. Nil when a pass is already running or nothing is pending.
    func check(_ activities: [Activity], _ current: ChallengeResults.Current) async -> [String: ChallengeResults.Result]? {
        guard !isChecking else { return nil }
        let pending = activities.filter { ChallengeResults.isPending($0, current) }
        guard !pending.isEmpty else { return nil }
        isChecking = true
        defer { isChecking = false }
        return await Task.detached(priority: .utility) {
            Dictionary(pending.map { a in (a.id, ChallengeResults.compute(a, current)) }, uniquingKeysWith: { a, _ in a })
        }.value
    }

    /// Adds up the stored results of the activities there are (so deleted ones drop out): places
    /// visited, routes crossed or covered, countries, and the badges. Results computed with an
    /// older key don't count until they're checked again. Returns whether anything changed.
    func aggregate(_ activities: [Activity], _ current: ChallengeResults.Current) -> Bool {
        let cKey = ChallengeResults.countriesKey
        var visits = [String: [String: [Date]]](), hits = [String: [[String: [Int]]]]()
        var countries = Set<String>()
        for a in activities where a.isOnMap {
            if let stored = a.challengeHits {
                for c in current.challenges {
                    guard let h = stored[c.id], h.key == c.key else { continue }
                    for id in h.ids ?? [] { visits[c.id, default: [:]][id, default: []].append(a.startDate ?? .distantPast) }
                    if let cp = h.checkpoints, !cp.isEmpty { hits[c.id, default: []].append(cp) }
                }
            }
            if a.countriesKey == cKey { countries.formUnion(a.countries ?? []) }
        }
        var progress = [String: ChallengeProgress]()
        for c in current.challenges {
            let coverage = c.isCoverRoutes
                ? RouteMatcher.progress(hits: hits[c.id] ?? [], counts: current.prepared[c.id]?.counts ?? [:]) : [:]
            progress[c.id] = ChallengeProgress(visits: (visits[c.id] ?? [:]).mapValues { $0.sorted(by: >) }, coverage: coverage)
        }
        let counts = BadgeRules.counts(activities, countries: countries.count)
        guard progress != self.progress || countries != worldCountries || counts != badges else { return false }
        self.progress = progress
        worldCountries = countries
        badges = counts
        return true
    }
}
