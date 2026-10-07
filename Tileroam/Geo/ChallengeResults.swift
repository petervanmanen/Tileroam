import CryptoKit
import Foundation

/// The challenge checks (the user's challenges, countries for Globetrotter) are done once per
/// activity and stored with it (`Activity.challengeHits`, `.countries`), like its tiles and
/// climbs. `ActivityStore` adds the stored results up for the activities there are, so deleted
/// activities simply drop out.
///
/// Each result carries a key: the matchers' `version` and a fingerprint of the challenge file
/// (`CustomChallenge.key`) or world map. Raise `version` when the matching rules change; a changed
/// file changes its fingerprint. Either way the stored results no longer match, and every activity
/// is checked again. (The badge rules aren't stored: they run on the activities each time; only
/// the countries they use are.)
enum ChallengeResults {
    /// Raise when the matching rules change (`PlaceMatcher`, `CrossingMatcher`, `RouteMatcher`).
    static let version = 1

    /// The bundled world map can only change with an app update: hashed once.
    static let countriesKey: String = {
        let data = Bundle.main.url(forResource: "world", withExtension: "fmr").flatMap { try? Data(contentsOf: $0) } ?? Data()
        return "c\(CountryOutlines.worldVersion)-\(hash(data))"
    }()

    private static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).prefix(6).map { String(format: "%02x", $0) }.joined()
    }

    struct Result: Sendable {
        /// Per challenge id, the results that were missing.
        var hits = [String: ChallengeHits]()
        var countries: [String]?
    }

    /// The challenges, and the checkpoints of their cover routes.
    struct Current: Sendable {
        let challenges: [CustomChallenge]
        /// Per cover-route challenge id.
        let prepared: [String: RouteMatcher.Prepared]
    }

    /// One challenge's result for one activity.
    static func hits(_ track: [GeoPoint], _ activity: Activity, _ challenge: CustomChallenge,
                     prepared: RouteMatcher.Prepared?) -> ChallengeHits {
        var hits = ChallengeHits(key: challenge.key)
        guard challenge.counts(activity) else { return hits } // stored empty, so it isn't checked again
        switch (challenge.kind, challenge.completion) {
        case (.locations, _): hits.ids = PlaceMatcher.visited(by: track, among: challenge.items, radius: challenge.radius)
        case (.routes, .cross): hits.ids = CrossingMatcher.crossed(by: track, among: challenge.items)
        case (.routes, .cover): hits.checkpoints = prepared.map { RouteMatcher.hits(track, paths: $0) } ?? [:]
        }
        return hits
    }

    /// The results one activity is missing: only the challenges whose key differs are checked.
    static func compute(_ activity: Activity, _ current: Current) -> Result {
        let track = activity.coordinates.map { GeoPoint(lat: $0.latitude, lon: $0.longitude) }
        var result = Result()
        for c in current.challenges where activity.challengeHits?[c.id]?.key != c.key {
            result.hits[c.id] = hits(track, activity, c, prepared: current.prepared[c.id])
        }
        if activity.countriesKey != countriesKey {
            result.countries = (CountryOutlines.world?.countries(visitedBy: [track]) ?? []).sorted()
        }
        return result
    }

    /// Whether an activity still needs checking.
    static func isPending(_ a: Activity, _ current: Current) -> Bool {
        a.isOnMap && (a.countriesKey != countriesKey || current.challenges.contains { a.challengeHits?[$0.id]?.key != $0.key })
    }

    /// Stores a result with its activity. Results of challenges that are gone are dropped.
    static func store(_ r: Result, _ current: Current, in a: inout Activity) {
        let ids = Set(current.challenges.map(\.id))
        var hits = (a.challengeHits ?? [:]).filter { ids.contains($0.key) }
        hits.merge(r.hits) { _, new in new }
        a.challengeHits = hits.isEmpty ? nil : hits
        if let c = r.countries { a.countries = c; a.countriesKey = countriesKey }
    }
}

/// What one activity did in one challenge, valid for `key` (`CustomChallenge.key`).
struct ChallengeHits: Codable, Sendable, Equatable {
    var key: String
    /// Locations visited, or routes crossed.
    var ids: [String]?
    /// Cover routes: per route touched, the indexes of its checkpoints passed
    /// (`RouteMatcher.checkpoints`).
    var checkpoints: [String: [Int]]?
}

/// A challenge's progress over all activities.
struct ChallengeProgress: Sendable, Equatable {
    /// Locations and crossings: for each one done, when (newest first).
    var visits = [String: [Date]]()
    /// Cover routes: for each route with progress, the share covered (0…1).
    var coverage = [String: Double]()

    func isDone(_ id: String, in challenge: CustomChallenge) -> Bool {
        challenge.isCoverRoutes ? (coverage[id] ?? 0) >= challenge.coverage : visits[id] != nil
    }

    /// Items done.
    func done(in challenge: CustomChallenge) -> Int {
        challenge.isCoverRoutes ? coverage.values.count { $0 >= challenge.coverage } : visits.count
    }
}

extension CustomChallenge {
    /// Routes done by covering them (not crossings).
    var isCoverRoutes: Bool { kind == .routes && completion == .cover }
}
