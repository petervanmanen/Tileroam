import CryptoKit
import Foundation

/// The slower challenge checks (Trappist breweries, Klompenpaden, countries for Globetrotter) are
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
    static func klompenpadKey(_ list: [Klompenpad]) -> String { "k\(KlompenpadMatcher.version)-\(fingerprint(list))" }
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
        var klompenpadHits: [String: [Int]]?
        var countries: [String]?
    }

    /// The results one activity is missing: only the parts whose key differs are computed.
    static func compute(_ activity: Activity, trappists: [Trappist], trappistsKey: String,
                        paths: KlompenpadMatcher.Prepared, klompenpadKey: String) -> Result {
        let track = activity.coordinates.map { GeoPoint(lat: $0.latitude, lon: $0.longitude) }
        var result = Result()
        if activity.trappistsKey != trappistsKey { result.trappists = TrappistMatcher.visited(by: track, among: trappists) }
        if activity.klompenpadKey != klompenpadKey { result.klompenpadHits = KlompenpadMatcher.hits(track, paths: paths) }
        if activity.countriesKey != countriesKey {
            result.countries = (CountryOutlines.world?.countries(visitedBy: [track]) ?? []).sorted()
        }
        return result
    }

    /// Whether an activity still needs checking.
    static func isPending(_ a: Activity, trappistsKey: String, klompenpadKey: String) -> Bool {
        a.isOnMap && (a.trappistsKey != trappistsKey || a.klompenpadKey != klompenpadKey || a.countriesKey != countriesKey)
    }
}
