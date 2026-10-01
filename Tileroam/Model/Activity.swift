import CoreLocation
import Foundation

/// A parsed activity as kept in memory and in the on-disk cache.
struct Activity: Codable, Sendable, Identifiable {
    /// Path relative to the selected folder.
    var id: String
    /// Changes when the source file changes; used to decide whether to re-parse.
    var cacheKey: String
    var name: String
    var sport: String
    var startDate: Date?
    /// Meters.
    var distance: Double
    /// Simplified track, interleaved latitude/longitude as Float32.
    var trackData: Data
    /// Visited zoom 14 / zoom 17 tiles (see `TileGrid.key`); nil in caches from before tiles.
    var tiles14: [Int64]?
    var tiles17: [Int64]?
    /// Visited municipalities and postcode areas, country-prefixed ("NL:GM0344", "DE:10115"),
    /// for the countries in `regionsKey`; recomputed when the switched-on countries change.
    var municipalities: [String]?
    var postalCodes: [String]?
    var regionsKey: String?
    /// True while the track is only Strava's simplified summary polyline.
    var isSummary: Bool?
    /// Indoor or virtual ride/run (Zwift, Rouvy, …): counts in statistics, but its GPS track
    /// is not a real place, so it is kept off the map, tiles, municipalities and postcodes.
    var isVirtual: Bool?

    /// Shown on the map and counted for tiles, municipalities and postcodes.
    var isOnMap: Bool { isVirtual != true && !trackData.isEmpty }

    /// Names used by virtual platforms and indoor exports (e.g. HealthFit "Indoor Cycling-Companion").
    static func looksVirtual(name: String) -> Bool {
        let n = name.lowercased()
        return ["zwift", "rouvy", "mywhoosh", "bkool", "fulgaz", "trainerroad", "wahoo systm", "kinomap",
                "virtual", "indoor"].contains { n.contains($0) }
    }
    /// Seconds (Strava only, used when exporting).
    var elapsedTime: Double?
    var movingTime: Double?
    /// File name in the folder's "Strava" subfolder once exported.
    var exportedFile: String?

    /// Used to pick the best copy when the same activity comes from several sources.
    var quality: Int {
        if trackData.isEmpty { return 0 }
        return isSummary == true ? 1 : 2
    }

    var coordinates: [CLLocationCoordinate2D] {
        trackData.withUnsafeBytes { raw in
            let floats = raw.bindMemory(to: Float32.self)
            return stride(from: 0, to: floats.count - 1, by: 2).map {
                CLLocationCoordinate2D(latitude: Double(floats[$0]), longitude: Double(floats[$0 + 1]))
            }
        }
    }

    static func encodeTrack(_ points: [GeoPoint]) -> Data {
        var floats = [Float32]()
        floats.reserveCapacity(points.count * 2)
        for p in points {
            floats.append(Float32(p.lat))
            floats.append(Float32(p.lon))
        }
        return floats.withUnsafeBufferPointer { Data(buffer: $0) }
    }
}

struct GeoPoint: Sendable, Equatable {
    var lat: Double
    var lon: Double
}
