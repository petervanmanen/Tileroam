import Foundation

/// Which not-yet-visited tiles, municipalities and postcodes a route passes through.
struct RouteCoverage: Sendable, Equatable {
    var newTiles14 = Set<Int64>()
    var newTiles17 = Set<Int64>()
    var newMunicipalities = Set<String>()
    var newPostcodes = Set<String>()
    /// Climbs the route rides uphill, and those of them not climbed before.
    var climbs = Set<String>()
    var newClimbs = Set<String>()
    /// Trappist breweries the route passes, and those of them not visited before.
    var trappists = Set<String>()
    var newTrappists = Set<String>()

    func newTiles(_ zoom: TileZoom) -> Set<Int64> {
        zoom == .explorer ? newTiles14 : newTiles17
    }

    init() {}

    init(route: [GeoPoint], visitedTiles14: Set<Int64>, visitedTiles17: Set<Int64>, visitedMunicipalities: Set<String>,
         visitedPostcodes: Set<String>, regions: RegionData?, climbs knownClimbs: [Climb] = [], climbed: Set<String> = [],
         trappists knownTrappists: [Trappist] = [], visitedTrappists: Set<String> = []) {
        let dense = Geo.densified(route, spacing: 20, maxGap: 5_000)
        newTiles14 = TileGrid.tiles(for: dense, zoom: .explorer).subtracting(visitedTiles14)
        newTiles17 = TileGrid.tiles(for: dense, zoom: .squadratinho).subtracting(visitedTiles17)
        newMunicipalities = (regions?.municipalities.visited(by: dense) ?? []).subtracting(visitedMunicipalities)
        newPostcodes = (regions?.postcodes.visited(by: dense) ?? []).subtracting(visitedPostcodes)
        let ride = Activity(id: "route", cacheKey: "", name: "", sport: "Cycling", startDate: nil, distance: 0,
                            trackData: Activity.encodeTrack(route))
        climbs = Set(ClimbMatcher.match([ride], climbs: knownClimbs)["route"] ?? [])
        newClimbs = climbs.subtracting(climbed)
        trappists = Set(TrappistMatcher.visited(by: route, among: knownTrappists))
        newTrappists = trappists.subtracting(visitedTrappists)
    }

    func contains(_ target: PlanTarget) -> Bool {
        switch target {
        case .tile(let z, let k): newTiles(z).contains(k)
        case .municipality(let c): newMunicipalities.contains(c)
        case .postcode(let c): newPostcodes.contains(c)
        case .climb(let id): climbs.contains(id)
        case .trappist(let id): trappists.contains(id)
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
        if !newTrappists.isEmpty { parts.append(String(localized: "\(newTrappists.count) Trappist breweries")) }
        return parts.isEmpty ? String(localized: "nothing new") : parts.joined(separator: " · ")
    }
}
