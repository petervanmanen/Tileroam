import CoreLocation
import Foundation
import WidgetKit

/// Values shared with the widgets through the app group.
enum WidgetData {
    static let appGroup = "group.nl.petervanmanen.Tileroam"
    static let tilesWidgetKind = "TilesWidget"

    static func save(cycling: Eddington, running: Eddington) {
        guard let defaults = UserDefaults(suiteName: appGroup) else { return }
        let old = defaults.integer(forKey: "eddington.cycling")
        let oldNeeded = defaults.integer(forKey: "eddington.cycling.needed")
        defaults.set(cycling.number, forKey: "eddington.cycling")
        defaults.set(cycling.daysNeeded, forKey: "eddington.cycling.needed")
        defaults.set(running.number, forKey: "eddington.running")
        defaults.set(running.daysNeeded, forKey: "eddington.running.needed")
        defaults.set(Date.now, forKey: "eddington.updated")
        if old != cycling.number || oldNeeded != cycling.daysNeeded {
            WidgetCenter.shared.reloadTimelines(ofKind: "EddingtonWidget")
        }
    }

    // MARK: Tiles widget

    private static var container: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }

    /// Writes the visited tiles (as little-endian Int64 keys) for the tiles widget, if they changed.
    static func saveTiles(_ tiles14: Set<Int64>, _ tiles17: Set<Int64>) async {
        guard let container else { return }
        let changed = await Task.detached(priority: .utility) {
            var changed = false
            for (name, tiles) in [("tiles14.bin", tiles14), ("tiles17.bin", tiles17)] {
                let url = container.appending(path: name)
                let data = tiles.sorted().withUnsafeBufferPointer { Data(buffer: $0) }
                if (try? Data(contentsOf: url)) != data {
                    try? data.write(to: url, options: .atomic)
                    changed = true
                }
            }
            return changed
        }.value
        if changed { WidgetCenter.shared.reloadTimelines(ofKind: tilesWidgetKind) }
    }

    /// The tile zoom level chosen in the app, for the tiles widget.
    static func saveTileZoom(_ zoom: Int) {
        guard let defaults = UserDefaults(suiteName: appGroup), defaults.integer(forKey: "tileZoom") != zoom else { return }
        defaults.set(zoom, forKey: "tileZoom")
        WidgetCenter.shared.reloadTimelines(ofKind: tilesWidgetKind)
    }

    /// Last known location, used by the tiles widget when it can't get one itself.
    static func saveLocation(_ coordinate: CLLocationCoordinate2D) {
        guard let defaults = UserDefaults(suiteName: appGroup) else { return }
        let old = CLLocation(latitude: defaults.double(forKey: "location.lat"), longitude: defaults.double(forKey: "location.lon"))
        let new = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard new.distance(from: old) > 200 else { return } // only meaningful moves
        defaults.set(coordinate.latitude, forKey: "location.lat")
        defaults.set(coordinate.longitude, forKey: "location.lon")
        WidgetCenter.shared.reloadTimelines(ofKind: tilesWidgetKind)
    }
}
