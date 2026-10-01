import Foundation
import MapKit

/// Where the map opens: the biggest cluster of what the current view shows.
enum MapFocus {
    /// Apple Park, used when there is nothing to show yet.
    static let appleHQ = GeoPoint(lat: 37.3349, lon: -122.0090)
    /// Zoom level whose tile height fills the screen height when the map opens.
    static let tileZoom = 10

    /// Center of the zoom-10 tile area holding the most points (averaged over those points).
    static func densestCenter(_ points: [GeoPoint]) -> GeoPoint? {
        guard !points.isEmpty else { return nil }
        let n = Double(1 << tileZoom)
        var buckets = [Int64: (count: Int, lat: Double, lon: Double)]()
        for p in points {
            guard abs(p.lat) < 85 else { continue }
            let φ = p.lat * .pi / 180
            let x = Int64(((p.lon + 180) / 360 * n).rounded(.down))
            let y = Int64(((1 - log(tan(φ) + 1 / cos(φ)) / .pi) / 2 * n).rounded(.down))
            let key = x << 32 | y
            let b = buckets[key] ?? (0, 0, 0)
            buckets[key] = (b.count + 1, b.lat + p.lat, b.lon + p.lon)
        }
        guard let best = buckets.values.max(by: { $0.count < $1.count }) else { return nil }
        return GeoPoint(lat: best.lat / Double(best.count), lon: best.lon / Double(best.count))
    }

    /// Visible map rect centered on `center` whose height is one zoom-10 tile.
    static func rect(center: GeoPoint, aspectRatio: Double) -> MKMapRect {
        let height = MKMapSize.world.height / Double(1 << tileZoom)
        let width = height * max(aspectRatio, 0.1)
        let c = MKMapPoint(CLLocationCoordinate2D(latitude: center.lat, longitude: center.lon))
        return MKMapRect(x: c.x - width / 2, y: c.y - height / 2, width: width, height: height)
    }
}
