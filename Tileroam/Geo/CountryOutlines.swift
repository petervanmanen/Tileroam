import Foundation

/// Simplified outlines of the supported countries (`countries.fmr`, about 0.5 MB, bundled; made by
/// `Tools/build_country_outlines.py`). They tell which countries an activity was in, so only those
/// countries' boundaries are downloaded. Borders are accurate to about 200 m; a country found
/// that way without a visited municipality is dropped again after the count.
struct CountryOutlines: Sendable {
    private struct Piece: Sendable {
        let country: String
        let ring: [GeoPoint]
        let minLat, maxLat, minLon, maxLon: Double
    }

    /// The outlines are cut into 1° × 1° pieces; each piece is indexed by its cell.
    private let cells: [Int: [Piece]]

    static let bundled: CountryOutlines? = load("countries")

    /// All countries of the world, coarser (Natural Earth 1:50m: borders and coasts about 1 km off;
    /// `world.fmr`, made by `Tools/build_world_countries.py`): for counting countries (the
    /// Globetrotter badge), where a ride well into a country is what counts.
    static let world: CountryOutlines? = load("world")

    private static func load(_ name: String) -> CountryOutlines? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "fmr"),
              let data = try? Data(contentsOf: url),
              let areas = try? RegionFile.decode(data) else { return nil }
        return CountryOutlines(areas: areas)
    }

    init(areas: [Area]) {
        var cells = [Int: [Piece]]()
        for area in areas {
            for polygon in area.polygons {
                guard let ring = polygon.rings.first, ring.count >= 3 else { continue }
                let lats = ring.map(\.lat), lons = ring.map(\.lon)
                let piece = Piece(country: area.country, ring: ring, minLat: lats.min()!, maxLat: lats.max()!,
                                  minLon: lons.min()!, maxLon: lons.max()!)
                let key = Self.key(lat: (piece.minLat + piece.maxLat) / 2, lon: (piece.minLon + piece.maxLon) / 2)
                cells[key, default: []].append(piece)
            }
        }
        self.cells = cells
    }

    private static func key(lat: Double, lon: Double) -> Int {
        Int(lon.rounded(.down)) &* 1000 &+ Int(lat.rounded(.down))
    }

    /// The country containing `p`, if it is one of the supported countries.
    func country(at p: GeoPoint) -> String? {
        cells[Self.key(lat: p.lat, lon: p.lon)]?.first {
            p.lat >= $0.minLat && p.lat <= $0.maxLat && p.lon >= $0.minLon && p.lon <= $0.maxLon
                && Area.ringContains($0.ring, p)
        }?.country
    }

    /// Countries that any of the tracks passes through, checking up to `samples` points per track.
    func countries(visitedBy tracks: [[GeoPoint]], samples: Int = 60) -> Set<String> {
        var found = Set<String>()
        for track in tracks where !track.isEmpty {
            let step = max(1, track.count / samples)
            for i in Swift.stride(from: 0, to: track.count, by: step) {
                if let c = country(at: track[i]) { found.insert(c) }
            }
            if let c = country(at: track[track.count - 1]) { found.insert(c) }
        }
        return found
    }
}

/// Which countries' boundaries to keep loaded.
enum CountrySelection {
    /// After a count: the countries with a visited municipality, plus those whose download failed
    /// (without their boundaries we can't tell). Nil when nothing would change, or when nothing
    /// would be left (no visits yet: keep the current choice).
    static func pruned(enabled: Set<String>, visitedMunicipalities: Set<String>, failed: Set<String>) -> Set<String>? {
        let visited = Set(visitedMunicipalities.map { String($0.prefix { $0 != ":" }) })
        let keep = enabled.filter { visited.contains($0) || failed.contains($0) }
        guard !keep.isEmpty, keep != enabled else { return nil }
        return keep
    }
}
