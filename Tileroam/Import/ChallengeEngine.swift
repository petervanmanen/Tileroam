import Foundation
import Observation

/// The challenges that check activities against a list (see `ChallengeResults`): the Trappist
/// breweries, the boscafés, the ferries, the Klompenpaden and the mountain bike routes. Holds the lists, checks
/// activities whose stored results are missing or out of date, and adds the stored results up
/// (visits, progress, countries for Globetrotter, badges). `ActivityStore` owns the activities and
/// decides when to check; this type knows how.
@MainActor
@Observable
final class ChallengeEngine {
    /// The breweries, from R2 (the copy on the device until the download is checked).
    private(set) var trappists: [Trappist] = TrappistData.cached()
    /// For each visited brewery, when (newest first).
    private(set) var trappistVisits: [String: [Date]] = [:]
    /// The boscafés, from R2 (the copy on the device until the download is checked).
    private(set) var boscafes: [Boscafe] = BoscafeData.cached()
    /// For each visited boscafé, when (newest first).
    private(set) var boscafeVisits: [String: [Date]] = [:]
    /// The ferries, from the `ferries` asset pack (empty until it's downloaded).
    private(set) var ferries: [Ferry] = FerryData.cached()
    /// For each ferry taken, when (newest first).
    private(set) var ferryCrossings: [String: [Date]] = [:]
    /// The paths, from the `klompenpaden` asset pack (empty until it's downloaded).
    private(set) var klompenpaden: [Klompenpad] = KlompenpadData.cached()
    /// For each path with progress, the share of its main route walked (0…1).
    private(set) var klompenpadProgress: [String: Double] = [:]
    /// The routes, from the `mtbroutes` asset pack (empty until it's downloaded).
    private(set) var mtbRoutes: [MTBRoute] = MTBRouteData.cached()
    /// For each route with progress, the share ridden (0…1).
    private(set) var mtbProgress: [String: Double] = [:]
    /// How often each badge was earned (see `BadgeRules`); indoor activities count too.
    private(set) var badges: [Badge: Int] = [:]
    /// The countries of the world with activities (not virtual ones), for Globetrotter.
    private(set) var worldCountries: Set<String> = []

    /// Paths walked (at least `KlompenpadMatcher.done`).
    var klompenpadenWalked: Int { klompenpadProgress.values.count { $0 >= KlompenpadMatcher.done } }
    /// Routes ridden (at least `KlompenpadMatcher.done`).
    var mtbRoutesRidden: Int { mtbProgress.values.count { $0 >= KlompenpadMatcher.done } }

    /// Called when the routes' checkpoints are ready, so the owner can check its activities.
    @ObservationIgnored var onPrepared: () -> Void = {}

    /// A check pass is running (one at a time).
    @ObservationIgnored private(set) var isChecking = false

    // MARK: Lists

    enum Change { case none, list, logos }

    /// Checks for a new list of Trappist breweries (at most once a day) and their logos.
    func updateTrappists() async -> Change {
        func logos() -> Int {
            trappists.filter { FileManager.default.fileExists(atPath: TrappistData.iconFile($0.id).path(percentEncoded: false)) }.count
        }
        let before = logos()
        guard let list = try? await TrappistData.load() else { return .none }
        if list != trappists {
            trappists = list
            return .list // a new list has a new key: every activity is checked again
        }
        return logos() != before ? .logos : .none
    }

    /// Checks for a new list of boscafés (at most once a day).
    func updateBoscafes() async -> Change {
        guard let list = try? await BoscafeData.load(), list != boscafes else { return .none }
        boscafes = list
        return .list
    }

    /// Loads the ferries (downloading their asset pack the first time).
    func updateFerries() async -> Change {
        guard let list = try? await FerryData.load(), list != ferries else { return .none }
        ferries = list
        ferriesKeyCache = nil
        return .list
    }

    /// Loads the mountain bike routes (downloading their asset pack the first time).
    func updateMTBRoutes() async -> Change {
        guard let list = try? await MTBRouteData.load(), list != mtbRoutes else { return .none }
        mtbRoutes = list
        mtbKeyCache = nil
        return .list
    }

    /// Loads the Klompenpaden (downloading their asset pack the first time).
    func updateKlompenpaden() async -> Change {
        guard let list = try? await KlompenpadData.load(), list != klompenpaden else { return .none }
        klompenpaden = list
        klompenpadKeyCache = nil
        return .list
    }

    // MARK: Keys and prepared routes

    // The lists' fingerprints, kept until the list changes: hashing the MTB routes (4 MB of JSON)
    // on every count would make the main thread stutter.
    @ObservationIgnored private var klompenpadKeyCache: String?
    @ObservationIgnored private var mtbKeyCache: String?
    @ObservationIgnored private var ferriesKeyCache: String?
    private var ferriesKey: String {
        if let ferriesKeyCache { return ferriesKeyCache }
        let key = ChallengeResults.ferriesKey(ferries)
        ferriesKeyCache = key
        return key
    }
    private var klompenpadKey: String {
        if let klompenpadKeyCache { return klompenpadKeyCache }
        let key = ChallengeResults.klompenpadKey(klompenpaden)
        klompenpadKeyCache = key
        return key
    }
    private var mtbKey: String {
        if let mtbKeyCache { return mtbKeyCache }
        let key = ChallengeResults.mtbKey(mtbRoutes)
        mtbKeyCache = key
        return key
    }

    /// The Klompenpaden's and MTB routes' checkpoints, for the current lists.
    @ObservationIgnored private var preparedPaths: (key: String, paths: KlompenpadMatcher.Prepared)?
    @ObservationIgnored private var preparedMTB: (key: String, paths: KlompenpadMatcher.Prepared)?
    @ObservationIgnored private var preparingRoutes: Task<Void, Never>?

    /// The current lists with their keys and the routes' checkpoints; nil while the checkpoints are
    /// being prepared (`onPrepared` is called when they're ready).
    var current: ChallengeResults.Current? {
        let kKey = klompenpadKey, mKey = mtbKey
        guard let paths = preparedPaths, paths.key == kKey, let mtb = preparedMTB, mtb.key == mKey else {
            prepareRoutes()
            return nil
        }
        return ChallengeResults.Current(trappists: trappists, trappistsKey: ChallengeResults.trappistsKey(trappists),
                                        boscafes: boscafes, boscafesKey: ChallengeResults.boscafesKey(boscafes),
                                        ferries: ferries, ferriesKey: ferriesKey,
                                        paths: paths.paths, klompenpadKey: kKey, mtb: mtb.paths, mtbKey: mKey)
    }

    /// Prepares the checkpoints of the Klompenpaden and MTB routes in the background (seconds for
    /// the 4,700 MTB routes on an iPad: on the main thread it froze the app).
    private func prepareRoutes() {
        guard preparingRoutes == nil else { return }
        let kKey = klompenpadKey, mKey = mtbKey, paths = klompenpaden, routes = mtbRoutes
        let needPaths = preparedPaths?.key != kKey, needRoutes = preparedMTB?.key != mKey
        preparingRoutes = Task {
            let (p, m) = await Task.detached(priority: .utility) {
                (needPaths ? KlompenpadMatcher.Prepared(paths) : nil,
                 needRoutes ? KlompenpadMatcher.Prepared(routes, spacing: MTBRoute.spacing) : nil)
            }.value
            if let p { preparedPaths = (kKey, p) }
            if let m { preparedMTB = (mKey, m) }
            preparingRoutes = nil
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

    /// Stores a result with its activity, under the keys it was computed with.
    nonisolated static func store(_ r: ChallengeResults.Result, _ current: ChallengeResults.Current, in a: inout Activity) {
        if let t = r.trappists { a.trappists = t; a.trappistsKey = current.trappistsKey }
        if let b = r.boscafes { a.boscafes = b; a.boscafesKey = current.boscafesKey }
        if let f = r.ferries { a.ferries = f; a.ferriesKey = current.ferriesKey }
        if let h = r.klompenpadHits { a.klompenpadHits = h; a.klompenpadKey = current.klompenpadKey }
        if let h = r.mtbHits { a.mtbHits = h; a.mtbKey = current.mtbKey }
        if let c = r.countries { a.countries = c; a.countriesKey = ChallengeResults.countriesKey }
    }

    /// Adds up the stored results of the activities there are (so deleted ones drop out): visited
    /// breweries and boscafés, Klompenpaden and MTB route progress, countries, and the badges.
    /// Results computed with an older key don't count until they're checked again. Returns whether
    /// anything changed.
    func aggregate(_ activities: [Activity], _ current: ChallengeResults.Current) -> Bool {
        let cKey = ChallengeResults.countriesKey
        var visits = [String: [Date]](), cafes = [String: [Date]](), crossings = [String: [Date]]()
        var paths = [[String: [Int]]](), mtb = [[String: [Int]]]()
        var countries = Set<String>()
        for a in activities where a.isOnMap {
            if a.trappistsKey == current.trappistsKey {
                for id in a.trappists ?? [] { visits[id, default: []].append(a.startDate ?? .distantPast) }
            }
            if a.boscafesKey == current.boscafesKey {
                for id in a.boscafes ?? [] { cafes[id, default: []].append(a.startDate ?? .distantPast) }
            }
            if a.ferriesKey == current.ferriesKey {
                for id in a.ferries ?? [] { crossings[id, default: []].append(a.startDate ?? .distantPast) }
            }
            if a.klompenpadKey == current.klompenpadKey, let h = a.klompenpadHits { paths.append(h) }
            if a.mtbKey == current.mtbKey, let h = a.mtbHits { mtb.append(h) }
            if a.countriesKey == cKey { countries.formUnion(a.countries ?? []) }
        }
        let progress = KlompenpadMatcher.progress(hits: paths, counts: current.paths.counts)
        let mtbProgress = KlompenpadMatcher.progress(hits: mtb, counts: current.mtb.counts)
        let counts = BadgeRules.counts(activities, countries: countries.count)
        let sortedVisits = visits.mapValues { $0.sorted(by: >) }, cafeVisits = cafes.mapValues { $0.sorted(by: >) }
        let ferryCrossings = crossings.mapValues { $0.sorted(by: >) }
        guard sortedVisits != trappistVisits || cafeVisits != boscafeVisits || ferryCrossings != self.ferryCrossings
                || progress != klompenpadProgress
                || mtbProgress != self.mtbProgress || countries != worldCountries || counts != badges else { return false }
        trappistVisits = sortedVisits
        boscafeVisits = cafeVisits
        self.ferryCrossings = ferryCrossings
        klompenpadProgress = progress
        self.mtbProgress = mtbProgress
        worldCountries = countries
        badges = counts
        return true
    }
}
