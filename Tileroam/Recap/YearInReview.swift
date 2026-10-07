import Foundation

/// One year's numbers for the shareable year in review (issue #56): what was new that year
/// (tiles, areas, countries, climbs, challenge places, badges) and how the totals grew.
struct YearInReview: Sendable {
    let year: Int
    var activities = 0
    var distanceKm = 0.0
    var movingHours = 0.0
    var ascent = 0.0
    /// Tiles first visited this year, and all tiles visited before it.
    var newTiles = [Int64]()
    var earlierTiles = Set<Int64>()
    var maxSquare = (before: 0, after: 0)
    var cluster = (before: 0, after: 0)
    var newMunicipalities = 0
    var newPostcodes = 0
    var newCountries = [String]()
    var newClimbs = 0
    /// The user's challenges with something new this year: places visited, routes crossed or
    /// done for the first time.
    var challenges = [(name: String, count: Int)]()
    /// Badges earned (again) this year.
    var badges = [Badge]()
    var eddington = (before: 0, after: 0)

    /// The years with activities, newest first.
    static func years(_ activities: [Activity], calendar: Calendar = .current) -> [Int] {
        Set(activities.compactMap { $0.startDate.map { calendar.component(.year, from: $0) } }).sorted(by: >)
    }

    /// What the year in review needs of a challenge of the user.
    struct Challenge: Sendable {
        let id: String
        let name: String
        let key: String
        /// Cover routes: the share that makes a route done, and checkpoints per route.
        let coverage: Double?
        let counts: [String: Int]

        @MainActor
        init(_ challenge: CustomChallenge, store: ActivityStore) {
            id = challenge.id
            name = challenge.name
            key = challenge.key
            coverage = challenge.isCoverRoutes ? challenge.coverage : nil
            counts = challenge.isCoverRoutes ? store.challenges.routeCounts(challenge.id) : [:]
        }
    }

    init(year: Int, activities: [Activity], history: TileHistory, challenges: [Challenge] = [], calendar: Calendar = .current) {
        self.year = year
        guard let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let end = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)) else { return }
        let before = activities.filter { ($0.startDate ?? .distantPast) < start }
        let upToEnd = activities.filter { ($0.startDate ?? .distantPast) < end }
        let during = upToEnd.filter { ($0.startDate ?? .distantPast) >= start }

        self.activities = during.count
        distanceKm = during.reduce(0) { $0 + $1.distance } / 1000
        movingHours = during.reduce(0) { $0 + ($1.movingTime ?? $1.elapsedTime ?? 0) } / 3600
        ascent = during.reduce(0) { $0 + ($1.ascent ?? 0) }

        earlierTiles = Set(history.entries.prefix { $0.date < start }.map(\.key))
        newTiles = history.entries.filter { $0.date >= start && $0.date < end }.map(\.key)
        let before14 = SquareStats(visited: earlierTiles), after14 = SquareStats(visited: earlierTiles.union(newTiles))
        maxSquare = (before14.maxSquare, after14.maxSquare)
        cluster = (before14.maxCluster, after14.maxCluster)

        /// The ids in `field` of the activities during the year that no earlier activity had.
        func new(_ field: (Activity) -> [String]?) -> [String] {
            let earlier = Set(before.filter(\.isOnMap).flatMap { field($0) ?? [] })
            return Array(Set(during.filter(\.isOnMap).flatMap { field($0) ?? [] }).subtracting(earlier))
        }
        newMunicipalities = new(\.municipalities).count
        newPostcodes = new(\.postalCodes).count
        newCountries = new(\.countries).sorted()
        newClimbs = new(\.climbs).count
        for c in challenges {
            func hits(_ a: Activity) -> ChallengeHits? { a.challengeHits?[c.id].flatMap { $0.key == c.key ? $0 : nil } }
            let count: Int
            if let coverage = c.coverage {
                // Routes done by the end of the year that weren't done before it.
                func done(_ list: [Activity]) -> Set<String> {
                    let progress = RouteMatcher.progress(hits: list.filter(\.isOnMap).compactMap { hits($0)?.checkpoints }, counts: c.counts)
                    return Set(progress.filter { $0.value >= coverage }.keys)
                }
                count = done(upToEnd).subtracting(done(before)).count
            } else {
                count = new { hits($0)?.ids }.count
            }
            if count > 0 { self.challenges.append((c.name, count)) }
        }

        func countries(_ list: [Activity]) -> Int { Set(list.filter(\.isOnMap).flatMap { $0.countries ?? [] }).count }
        let badgesBefore = BadgeRules.counts(before, countries: countries(before), calendar: calendar)
        let badgesAfter = BadgeRules.counts(upToEnd, countries: countries(upToEnd), calendar: calendar)
        badges = Badge.allCases.filter { (badgesAfter[$0] ?? 0) > (badgesBefore[$0] ?? 0) }

        eddington = (Eddington(activities: before, sports: Eddington.cyclingSports, calendar: calendar).number,
                     Eddington(activities: upToEnd, sports: Eddington.cyclingSports, calendar: calendar).number)
    }
}
