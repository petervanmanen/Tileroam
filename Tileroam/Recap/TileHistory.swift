import Foundation
import MapKit

/// When each tile was first visited: for the tile history video (issue #59) and the year in
/// review (issue #56).
struct TileHistory: Sendable {
    struct Entry: Sendable {
        let key: Int64
        let date: Date
    }

    /// Every visited tile once, in the order it was first visited: activity by activity, and
    /// within an activity in the order its track reaches them, so the video draws the route.
    let entries: [Entry]

    init(activities: [Activity]) {
        var seen = Set<Int64>()
        var entries = [Entry]()
        let dated = activities.filter(\.isOnMap).sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
        for a in dated {
            for key in Self.alongTrack(a) where seen.insert(key).inserted {
                entries.append(Entry(key: key, date: a.startDate ?? .distantPast))
            }
        }
        self.entries = entries
    }

    /// An activity's tiles in the order its track reaches them (`tiles14` is sorted by key, which
    /// would fill a ride in row by row from the side); tiles the walk misses come last.
    static func alongTrack(_ activity: Activity) -> [Int64] {
        let tiles = activity.tiles14 ?? []
        guard !tiles.isEmpty else { return [] }
        let wanted = Set(tiles)
        var ordered = [Int64](), found = Set<Int64>()
        let points = activity.coordinates.map { GeoPoint(lat: $0.latitude, lon: $0.longitude) }
        // Every gap filled (a sparse Strava summary line too): only the activity's own tiles count.
        for p in Geo.densified(points, spacing: TileZoom.explorer.trackSpacing, maxGap: .infinity) {
            if let key = TileGrid.key(lat: p.lat, lon: p.lon, zoom: .explorer), wanted.contains(key), found.insert(key).inserted {
                ordered.append(key)
            }
        }
        return ordered + tiles.filter { !found.contains($0) }
    }

    var keys: Set<Int64> { Set(entries.map(\.key)) }

    /// The tiles first visited before `date`.
    func tiles(before date: Date) -> Set<Int64> {
        Set(entries.prefix { $0.date < date }.map(\.key))
    }

    /// The area to show: the tiles in the country with the largest cluster (the tiles' home
    /// country), else all of them, with a margin and stretched to `aspect` (width / height).
    func focusRegion(aspect: Double) -> (region: MKCoordinateRegion, country: String?)? {
        let all = keys
        guard !all.isEmpty else { return nil }
        let stats = SquareStats(visited: all)
        var country: String?
        var shown = all
        if let center = stats.maxClusterCenter, let world = CountryOutlines.world {
            let point = TileGrid.coordinate(x: center.x, y: center.y, zoom: .explorer)
            if let code = world.country(at: point) {
                country = code
                let inCountry = all.filter { key in
                    let c = TileGrid.cell(of: key)
                    return world.country(at: TileGrid.coordinate(x: Double(c.x) + 0.5, y: Double(c.y) + 0.5, zoom: .explorer)) == code
                }
                if !inCountry.isEmpty { shown = inCountry }
            }
        }
        return (Self.region(around: shown, aspect: aspect), country)
    }

    /// A region showing all `tiles`, with 6% margin, as wide as `aspect` (width / height) asks.
    static func region(around tiles: some Collection<Int64>, aspect: Double) -> MKCoordinateRegion {
        var minX = Int.max, maxX = Int.min, minY = Int.max, maxY = Int.min
        for key in tiles {
            let c = TileGrid.cell(of: key)
            minX = min(minX, c.x); maxX = max(maxX, c.x); minY = min(minY, c.y); maxY = max(maxY, c.y)
        }
        // In map points (Web Mercator, like MapKit), so the aspect ratio is right on screen.
        let nw = MKMapPoint(TileGrid.corner(x: minX, y: minY, zoom: .explorer).coordinate)
        let se = MKMapPoint(TileGrid.corner(x: maxX + 1, y: maxY + 1, zoom: .explorer).coordinate)
        var rect = MKMapRect(x: nw.x, y: nw.y, width: se.x - nw.x, height: se.y - nw.y)
        rect = rect.insetBy(dx: -rect.width * 0.06, dy: -rect.height * 0.06)
        if rect.width / max(rect.height, 1) < aspect {
            let width = rect.height * aspect
            rect = rect.insetBy(dx: -(width - rect.width) / 2, dy: 0)
        } else {
            let height = rect.width / aspect
            rect = rect.insetBy(dx: 0, dy: -(height - rect.height) / 2)
        }
        return MKCoordinateRegion(rect)
    }
}

extension GeoPoint {
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
}

/// A map picture (Apple Maps snapshot) to draw tiles on.
struct TileMapImage: @unchecked Sendable {
    let snapshot: MKMapSnapshotter.Snapshot
    let size: CGSize
    /// The snapshot, muted and faded towards white, so the tiles stand out (green tiles on the
    /// map's green woods and fields were hard to see).
    let base: UIImage

    // Colours with enough contrast on that map.
    /// Tiles visited before: strong blue, with a darker edge.
    static let tileFill = UIColor(red: 0.12, green: 0.36, blue: 0.86, alpha: 0.6)
    static let tileEdge = UIColor(red: 0.04, green: 0.18, blue: 0.52, alpha: 0.7)
    /// New tiles: bright orange.
    static let newFill = UIColor(red: 1.0, green: 0.45, blue: 0.0, alpha: 0.85)
    static let newEdge = UIColor(red: 0.75, green: 0.25, blue: 0.0, alpha: 1)
    /// The max square's outline.
    static let squareStroke = UIColor(red: 0.86, green: 0.04, blue: 0.24, alpha: 1)

    /// A snapshot of `region` at `size` pixels (scale 1): standard map, muted colours, light.
    static func make(region: MKCoordinateRegion, size: CGSize) async throws -> TileMapImage {
        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = size
        options.scale = 1
        options.pointOfInterestFilter = .excludingAll
        options.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        options.traitCollection = UITraitCollection(userInterfaceStyle: .light)
        let snapshot = try await MKMapSnapshotter(options: options).start()
        let base = UIGraphicsImageRenderer(size: size, format: .init(for: .init(displayScale: 1))).image { context in
            snapshot.image.draw(at: .zero)
            UIColor.white.withAlphaComponent(0.3).setFill()
            context.fill(CGRect(origin: .zero, size: size), blendMode: .normal) // plain fill() copies over the map
        }
        return TileMapImage(snapshot: snapshot, size: size, base: base)
    }

    /// Fills a tile and outlines it.
    func draw(_ key: Int64, in context: CGContext, fill: UIColor, edge: UIColor) {
        let rect = rect(key).insetBy(dx: 0.5, dy: 0.5)
        context.setFillColor(fill.cgColor)
        context.fill(rect)
        context.setStrokeColor(edge.cgColor)
        context.setLineWidth(1)
        context.stroke(rect)
    }

    /// A tile's rectangle in the picture (origin top left).
    func rect(_ key: Int64) -> CGRect {
        let c = TileGrid.cell(of: key)
        let a = snapshot.point(for: TileGrid.corner(x: c.x, y: c.y, zoom: .explorer).coordinate)
        let b = snapshot.point(for: TileGrid.corner(x: c.x + 1, y: c.y + 1, zoom: .explorer).coordinate)
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }
}
