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
    /// Visited zoom 14 tiles (see `TileGrid.key`); nil in caches from before tiles. (Caches from
    /// before 1.5.9 also have zoom 17 tiles, which are ignored.)
    var tiles14: [Int64]?
    /// Visited municipalities and postcode areas, country-prefixed ("NL:GM0344", "DE:10115"),
    /// for the countries in `regionsKey`; recomputed when the switched-on countries change.
    var municipalities: [String]?
    var postalCodes: [String]?
    var regionsKey: String?
    /// Climbs ridden uphill (`Climb.id`), for the climbs in `climbsKey`; recomputed when the climbs
    /// change (see `ClimbData`).
    var climbs: [String]?
    var climbsKey: String?
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
    /// Seconds: from the start to the end, and moving (without pauses).
    var elapsedTime: Double?
    var movingTime: Double?
    /// Watts, from a power meter (FIT avg_power, Strava average_watts with device_watts).
    var averagePower: Double?
    /// Which details the import read (see `Activity.currentDetails`); older cached activities are
    /// read again to fill in moving time and power.
    var detailsVersion: Int?
    static let currentDetails = 3
    /// Metres climbed and descended (FIT total_ascent/total_descent, Strava total_elevation_gain;
    /// Strava has no descent). For badges.
    var ascent: Double?
    var descent: Double?
    /// Recorded in Zwift (FIT manufacturer 260, or a Strava name starting "Zwift"). For badges.
    var isZwift: Bool?

    // Challenge results, computed once per activity (see `ChallengeResults`). Each is valid for
    // its key: the matcher's version and a fingerprint of the list or map it was computed with;
    // a different key means it is computed again.
    /// Trappist breweries passed (`Trappist.id`).
    var trappists: [String]?
    var trappistsKey: String?
    /// Klompenpaden: for each path touched, the indexes of its checkpoints passed
    /// (`KlompenpadMatcher.checkpoints`).
    var klompenpadHits: [String: [Int]]?
    var klompenpadKey: String?
    /// Countries of the world the track passes (ISO codes, `CountryOutlines.world`), for Globetrotter.
    var countries: [String]?
    var countriesKey: String?

    /// Moving time if known, otherwise elapsed time.
    var duration: Double? { (movingTime ?? 0) > 0 ? movingTime : elapsedTime }
    /// Meters per second over the moving time.
    var averageSpeed: Double? {
        guard let duration, duration > 0, distance > 0 else { return nil }
        return distance / duration
    }
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
