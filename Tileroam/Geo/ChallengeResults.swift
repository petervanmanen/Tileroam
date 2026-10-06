import CryptoKit
import Foundation

/// The slower challenge checks (Trappist breweries, boscafés, Klompenpaden, countries for Globetrotter) are
/// done once per activity and stored with it (`Activity.trappists`, `.klompenpadHits`,
/// `.countries`), like its tiles and climbs. `ActivityStore` adds the stored results up for the
/// activities there are, so deleted activities simply drop out.
///
/// Each result carries a key: the matcher's version and a fingerprint of the list or map it was
/// computed with. Raise a matcher's `version` when its rules change; a new brewery list,
/// Klompenpaden list or world map changes the fingerprint. Either way the stored results no longer
/// match, and every activity is checked again. (The badge rules aren't stored: they run on the
/// activities each time; only the countries they use are.)
enum ChallengeResults {
    static func trappistsKey(_ list: [Trappist]) -> String { "t\(TrappistMatcher.version)-\(fingerprint(list))" }
    static func boscafesKey(_ list: [Boscafe]) -> String { "b\(TrappistMatcher.version)-\(fingerprint(list))" }
    static func ferriesKey(_ list: [Ferry]) -> String { "f\(FerryMatcher.version)-\(fingerprint(list))" }
    static func klompenpadKey(_ list: [Klompenpad]) -> String { "k\(KlompenpadMatcher.version)-\(fingerprint(list))" }
    static func mtbKey(_ list: [MTBRoute]) -> String { "m\(KlompenpadMatcher.version)-\(fingerprint(list))" }
    /// The bundled world map can only change with an app update: hashed once.
    static let countriesKey: String = {
        let data = Bundle.main.url(forResource: "world", withExtension: "fmr").flatMap { try? Data(contentsOf: $0) } ?? Data()
        return "c\(CountryOutlines.worldVersion)-\(hash(data))"
    }()

    /// A short hash of the list as JSON (sorted keys, so the same list gives the same fingerprint).
    static func fingerprint<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return hash((try? encoder.encode(value)) ?? Data())
    }

    private static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).prefix(6).map { String(format: "%02x", $0) }.joined()
    }

    struct Result: Sendable {
        var trappists: [String]?
        var boscafes: [String]?
        var ferries: [String]?
        var klompenpadHits: [String: [Int]]?
        var mtbHits: [String: [Int]]?
        var countries: [String]?
    }

    /// The keys of the current lists, and the routes' prepared checkpoints.
    struct Current: Sendable {
        let trappists: [Trappist]
        let trappistsKey: String
        let boscafes: [Boscafe]
        let boscafesKey: String
        let ferries: [Ferry]
        let ferriesKey: String
        let paths: KlompenpadMatcher.Prepared
        let klompenpadKey: String
        let mtb: KlompenpadMatcher.Prepared
        let mtbKey: String
    }

    /// The results one activity is missing: only the parts whose key differs are computed.
    static func compute(_ activity: Activity, _ current: Current) -> Result {
        let track = activity.coordinates.map { GeoPoint(lat: $0.latitude, lon: $0.longitude) }
        var result = Result()
        if activity.trappistsKey != current.trappistsKey {
            result.trappists = TrappistMatcher.visited(by: track, among: current.trappists)
        }
        if activity.boscafesKey != current.boscafesKey {
            result.boscafes = TrappistMatcher.visited(by: track, among: current.boscafes)
        }
        if activity.ferriesKey != current.ferriesKey {
            result.ferries = FerryMatcher.crossed(by: track, among: current.ferries)
        }
        if activity.klompenpadKey != current.klompenpadKey { result.klompenpadHits = KlompenpadMatcher.hits(track, paths: current.paths) }
        if activity.mtbKey != current.mtbKey {
            result.mtbHits = MTBRoute.counts(activity) ? KlompenpadMatcher.hits(track, paths: current.mtb) : [:]
        }
        if activity.countriesKey != countriesKey {
            result.countries = (CountryOutlines.world?.countries(visitedBy: [track]) ?? []).sorted()
        }
        return result
    }

    /// Whether an activity still needs checking.
    static func isPending(_ a: Activity, _ current: Current) -> Bool {
        a.isOnMap && (a.trappistsKey != current.trappistsKey || a.boscafesKey != current.boscafesKey || a.ferriesKey != current.ferriesKey || a.klompenpadKey != current.klompenpadKey
                      || a.mtbKey != current.mtbKey || a.countriesKey != countriesKey)
    }
}
