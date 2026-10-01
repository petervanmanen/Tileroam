import Foundation

/// Which not-yet-visited tiles, municipalities and postcodes a route passes through.
struct RouteCoverage: Sendable, Equatable {
    var newTiles14 = Set<Int64>()
    var newTiles17 = Set<Int64>()
    var newMunicipalities = Set<String>()
    var newPostcodes = Set<String>()

    func newTiles(_ zoom: TileZoom) -> Set<Int64> {
        zoom == .explorer ? newTiles14 : newTiles17
    }

    init() {}

    init(route: [GeoPoint], visitedTiles14: Set<Int64>, visitedTiles17: Set<Int64>, visitedMunicipalities: Set<String>,
         visitedPostcodes: Set<String>, regions: RegionData?) {
        let dense = Geo.densified(route, spacing: 20, maxGap: 5_000)
        newTiles14 = TileGrid.tiles(for: dense, zoom: .explorer).subtracting(visitedTiles14)
        newTiles17 = TileGrid.tiles(for: dense, zoom: .squadratinho).subtracting(visitedTiles17)
        newMunicipalities = (regions?.municipalities.visited(by: dense) ?? []).subtracting(visitedMunicipalities)
        newPostcodes = (regions?.postcodes.visited(by: dense) ?? []).subtracting(visitedPostcodes)
    }

    func contains(_ target: PlanTarget) -> Bool {
        switch target {
        case .tile(let z, let k): newTiles(z).contains(k)
        case .municipality(let c): newMunicipalities.contains(c)
        case .postcode(let c): newPostcodes.contains(c)
        }
    }

    /// Counts for the tile zoom level shown in the app, plus municipalities and postcodes.
    func summary(_ zoom: TileZoom) -> String {
        var parts = [String]()
        let tiles = newTiles(zoom).count
        if tiles > 0 { parts.append(zoom.countLabel(tiles)) }
        if !newMunicipalities.isEmpty { parts.append(String(localized: "\(newMunicipalities.count) municipalities")) }
        if !newPostcodes.isEmpty { parts.append(String(localized: "\(newPostcodes.count) postcodes")) }
        return parts.isEmpty ? String(localized: "nothing new") : parts.joined(separator: " · ")
    }
}
