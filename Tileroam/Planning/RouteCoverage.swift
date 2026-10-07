import Foundation

/// Which not-yet-visited tiles, municipalities and postcodes a route passes through.
struct RouteCoverage: Sendable, Equatable {
    var newTiles14 = Set<Int64>()
    var newMunicipalities = Set<String>()
    var newPostcodes = Set<String>()
    /// Climbs the route rides uphill, and those of them not climbed before.
    var climbs = Set<String>()
    var newClimbs = Set<String>()
    /// Per location challenge (`CustomChallenge.id`): the places the route passes, and those of
    /// them not visited before.
    var places = [String: Set<String>]()
    var newPlaces = [String: Set<String>]()
    /// The location challenges' names, for the summary.
    var challengeNames = [String: String]()

    func newTiles(_ zoom: TileZoom) -> Set<Int64> {
        newTiles14
    }

    init() {}

    init(route: [GeoPoint], visitedTiles14: Set<Int64>, visitedMunicipalities: Set<String>,
         visitedPostcodes: Set<String>, regions: RegionData?, climbs knownClimbs: [Climb] = [], climbed: Set<String> = [],
         challenges: [(challenge: CustomChallenge, visited: Set<String>)] = []) {
        let dense = Geo.densified(route, spacing: 20, maxGap: 5_000)
        newTiles14 = TileGrid.tiles(for: dense, zoom: .explorer).subtracting(visitedTiles14)
        newMunicipalities = (regions?.municipalities.visited(by: dense) ?? []).subtracting(visitedMunicipalities)
        newPostcodes = (regions?.postcodes.visited(by: dense) ?? []).subtracting(visitedPostcodes)
        let ride = Activity(id: "route", cacheKey: "", name: "", sport: "Cycling", startDate: nil, distance: 0,
                            trackData: Activity.encodeTrack(route))
        climbs = Set(ClimbMatcher.match([ride], climbs: knownClimbs)["route"] ?? [])
        newClimbs = climbs.subtracting(climbed)
        for (challenge, visited) in challenges where challenge.isPlanningTarget {
            let passed = Set(PlaceMatcher.visited(by: route, among: challenge.items, radius: challenge.radius))
            guard !passed.isEmpty else { continue }
            places[challenge.id] = passed
            newPlaces[challenge.id] = passed.subtracting(visited)
            challengeNames[challenge.id] = challenge.name
        }
    }

    func contains(_ target: PlanTarget) -> Bool {
        switch target {
        case .tile(let z, let k): newTiles(z).contains(k)
        case .municipality(let c): newMunicipalities.contains(c)
        case .postcode(let c): newPostcodes.contains(c)
        case .climb(let id): climbs.contains(id)
        case .place(let challenge, let id): places[challenge]?.contains(id) ?? false
        }
    }

    /// Counts for the tile zoom level shown in the app, plus municipalities and postcodes.
    func summary(_ zoom: TileZoom) -> String {
        var parts = [String]()
        let tiles = newTiles(zoom).count
        if tiles > 0 { parts.append(zoom.countLabel(tiles)) }
        if !newMunicipalities.isEmpty { parts.append(String(localized: "\(newMunicipalities.count) municipalities")) }
        if !newPostcodes.isEmpty { parts.append(String(localized: "\(newPostcodes.count) postcodes")) }
        if !newClimbs.isEmpty { parts.append(String(localized: "\(newClimbs.count) climbs")) }
        for (id, new) in newPlaces.sorted(by: { $0.key < $1.key }) where !new.isEmpty {
            parts.append(String(localized: "\(challengeNames[id] ?? id): \(new.count)"))
        }
        return parts.isEmpty ? String(localized: "nothing new") : parts.joined(separator: " · ")
    }
}
