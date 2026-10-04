import CoreLocation
import MapKit
import SwiftUI
import UIKit
import WidgetKit

// MARK: - Shared data

/// Reads what the app shares through the app group (see `WidgetData` in the app).
enum TilesWidgetData {
    static let appGroup = "group.nl.petervanmanen.Tileroam"

    static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    /// Zoom 14 tiles (zoom 17 was removed in 1.5.9).
    static let zoom = 14

    static var lastLocation: CLLocationCoordinate2D? {
        guard let d = defaults, d.object(forKey: "location.lat") != nil else { return nil }
        return CLLocationCoordinate2D(latitude: d.double(forKey: "location.lat"), longitude: d.double(forKey: "location.lon"))
    }

    static func visitedTiles(zoom: Int) -> Set<Int64> {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
                .appending(path: "tiles\(zoom).bin"),
              let data = try? Data(contentsOf: url) else { return [] }
        return data.withUnsafeBytes { Set($0.bindMemory(to: Int64.self)) }
    }
}

/// Web Mercator tiles, same keys as the app's `TileGrid`.
enum WidgetTiles {
    static func key(x: Int, y: Int) -> Int64 { Int64(x) << 32 | Int64(UInt32(truncatingIfNeeded: y)) }

    static func cell(_ c: CLLocationCoordinate2D, zoom: Int) -> (x: Int, y: Int) {
        let n = Double(1 << zoom)
        let φ = c.latitude * .pi / 180
        return (Int(((c.longitude + 180) / 360 * n).rounded(.down)),
                Int(((1 - log(tan(φ) + 1 / cos(φ)) / .pi) / 2 * n).rounded(.down)))
    }

    static func corner(x: Int, y: Int, zoom: Int) -> CLLocationCoordinate2D {
        let n = Double(1 << zoom)
        return CLLocationCoordinate2D(latitude: atan(sinh(.pi * (1 - 2 * Double(y) / n))) * 180 / .pi,
                                      longitude: Double(x) / n * 360 - 180)
    }
}

// MARK: - Location

/// One location fix for the widget, with a timeout; falls back to the app's last known location.
/// Runs on the main actor: CLLocationManager delivers results on the thread it was created on.
@MainActor
final class WidgetLocation: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocationCoordinate2D?, Never>?

    func current() async -> CLLocationCoordinate2D? {
        guard manager.isAuthorizedForWidgetUpdates else { return TilesWidgetData.lastLocation }
        let fix: CLLocationCoordinate2D? = await withCheckedContinuation { continuation in
            self.continuation = continuation
            manager.delegate = self
            manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
            manager.requestLocation()
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(10))
                self?.finish(nil)
            }
        }
        return fix ?? TilesWidgetData.lastLocation
    }

    private func finish(_ coordinate: CLLocationCoordinate2D?) {
        continuation?.resume(returning: coordinate)
        continuation = nil
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let coordinate = locations.last?.coordinate
        MainActor.assumeIsolated { finish(coordinate) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated { finish(nil) }
    }
}

// MARK: - Timeline

struct TilesEntry: TimelineEntry {
    let date: Date
    let image: UIImage?
    let zoom: Int
    let visited: Int
    let total: Int
    let hasLocation: Bool
}

struct TilesProvider: TimelineProvider {
    func placeholder(in context: Context) -> TilesEntry {
        TilesEntry(date: .now, image: nil, zoom: 14, visited: 18, total: 25, hasLocation: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (TilesEntry) -> Void) {
        let size = context.displaySize, family = context.family
        nonisolated(unsafe) let completion = completion
        Task { completion(await makeEntry(size: size, family: family)) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TilesEntry>) -> Void) {
        let size = context.displaySize, family = context.family
        nonisolated(unsafe) let completion = completion
        Task {
            let entry = await makeEntry(size: size, family: family)
            // The app reloads the widget when tiles or the location change; refresh now and then too.
            completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(30 * 60))))
        }
    }

    /// Tiles shown around the location: wider in medium widgets.
    private func span(for family: WidgetFamily, zoom: Int) -> (columns: Int, rows: Int) {
        switch family {
        case .systemMedium: return (11, 5)
        case .systemLarge: return (7, 7)
        default: return (5, 5)
        }
    }

    @MainActor
    private static func location() async -> CLLocationCoordinate2D? {
        await WidgetLocation().current()
    }

    private func makeEntry(size: CGSize, family: WidgetFamily) async -> TilesEntry {
        let zoom = TilesWidgetData.zoom
        guard let location = await Self.location() else {
            return TilesEntry(date: .now, image: nil, zoom: zoom, visited: 0, total: 0, hasLocation: false)
        }
        let visited = TilesWidgetData.visitedTiles(zoom: zoom)
        let (columns, rows) = span(for: family, zoom: zoom)
        let center = WidgetTiles.cell(location, zoom: zoom)
        let x0 = center.x - columns / 2, y0 = center.y - rows / 2

        // Map rect covering exactly the tiles, matched to the widget's aspect ratio.
        let nw = MKMapPoint(WidgetTiles.corner(x: x0, y: y0, zoom: zoom))
        let se = MKMapPoint(WidgetTiles.corner(x: x0 + columns, y: y0 + rows, zoom: zoom))
        var rect = MKMapRect(x: nw.x, y: nw.y, width: se.x - nw.x, height: se.y - nw.y)
        let aspect = size.width / max(size.height, 1)
        if rect.width / rect.height < aspect {
            let w = rect.height * aspect
            rect = MKMapRect(x: rect.midX - w / 2, y: rect.minY, width: w, height: rect.height)
        } else {
            let h = rect.width / aspect
            rect = MKMapRect(x: rect.minX, y: rect.midY - h / 2, width: rect.width, height: h)
        }

        let options = MKMapSnapshotter.Options()
        options.mapRect = rect
        options.size = size
        options.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        options.pointOfInterestFilter = .excludingAll
        guard let snapshot = try? await MKMapSnapshotter(options: options).start() else {
            return TilesEntry(date: .now, image: nil, zoom: zoom, visited: 0, total: 0, hasLocation: true)
        }

        // Tiles fully or partly in view.
        let topLeft = WidgetTiles.cell(MKMapPoint(x: rect.minX, y: rect.minY).coordinate, zoom: zoom)
        let bottomRight = WidgetTiles.cell(MKMapPoint(x: rect.maxX, y: rect.maxY).coordinate, zoom: zoom)
        var visitedCount = 0, total = 0
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            snapshot.image.draw(at: .zero)
            let cg = ctx.cgContext
            for x in topLeft.x...bottomRight.x {
                for y in topLeft.y...bottomRight.y {
                    let a = snapshot.point(for: WidgetTiles.corner(x: x, y: y, zoom: zoom))
                    let b = snapshot.point(for: WidgetTiles.corner(x: x + 1, y: y + 1, zoom: zoom))
                    let tile = CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y)
                    let isVisited = visited.contains(WidgetTiles.key(x: x, y: y))
                    if (x0..<(x0 + columns)).contains(x), (y0..<(y0 + rows)).contains(y) {
                        total += 1
                        if isVisited { visitedCount += 1 }
                    }
                    if isVisited {
                        cg.setFillColor(UIColor.systemGreen.withAlphaComponent(0.45).cgColor)
                        cg.fill(tile)
                    }
                    cg.setStrokeColor(UIColor.systemGray.withAlphaComponent(0.6).cgColor)
                    cg.setLineWidth(0.6)
                    cg.stroke(tile)
                }
            }
            // You are here.
            let here = snapshot.point(for: location)
            let dot = CGRect(x: here.x - 6, y: here.y - 6, width: 12, height: 12)
            cg.setFillColor(UIColor.white.cgColor)
            cg.fillEllipse(in: dot.insetBy(dx: -2.5, dy: -2.5))
            cg.setFillColor(UIColor.systemBlue.cgColor)
            cg.fillEllipse(in: dot)
        }
        return TilesEntry(date: .now, image: image, zoom: zoom, visited: visitedCount, total: total, hasLocation: true)
    }
}

// MARK: - View

struct TilesWidgetView: View {
    let entry: TilesEntry

    var body: some View {
        if let image = entry.image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .overlay(alignment: .bottomLeading) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.grid.3x3.fill")
                        Text("\(entry.visited) / \(entry.total)")
                            .monospacedDigit()
                    }
                    .font(.caption2.bold())
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(.regularMaterial, in: Capsule())
                    .padding(8)
                }
        } else {
            VStack(spacing: 6) {
                Image(systemName: entry.hasLocation ? "map" : "location.slash")
                    .font(.title2)
                    .foregroundStyle(.green)
                Text(entry.hasLocation ? "Loading map…" : "Open Tileroam to share your location")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }
}

struct TilesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TilesWidget", provider: TilesProvider()) { entry in
            TilesWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color(.secondarySystemBackground) }
        }
        .configurationDisplayName("Tiles Around You")
        .description("A map of the tiles around your current location: visited tiles in green.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}
