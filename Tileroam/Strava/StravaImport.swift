import Foundation

/// Turns Strava API data into `Activity` values.
enum StravaImport {
    static func id(for stravaID: Int) -> String { "strava:\(stravaID)" }

    static func stravaID(of activity: Activity) -> Int? {
        stravaID(fromID: activity.id)
    }

    static func stravaID(fromID id: String) -> Int? {
        id.hasPrefix("strava:") ? Int(id.dropFirst("strava:".count)) : nil
    }

    /// Zwift, Rouvy and other virtual or trainer activities: no real places.
    static func isVirtual(_ s: StravaSummary) -> Bool {
        (s.sportType ?? s.type ?? "").hasPrefix("Virtual") || s.trainer == true || Activity.looksVirtual(name: s.name)
    }

    static func activity(from s: StravaSummary) -> Activity {
        let virtual = isVirtual(s)
        let polyline = virtual ? nil : s.map?.summaryPolyline
        let points = polyline.map(decodePolyline) ?? []
        var a = Importer.makeActivity(points: points, id: id(for: s.id), cacheKey: "", name: s.name,
                                      sport: sportName(s.sportType ?? s.type), startDate: s.startDate,
                                      distance: s.distance, isSummary: !points.isEmpty)
        applyDetails(s, to: &a)
        a.isVirtual = virtual
        return a
    }

    /// Times and power from Strava's summary (power only from a power meter: without one,
    /// Strava's `average_watts` is an estimate).
    static func applyDetails(_ s: StravaSummary, to a: inout Activity) {
        a.elapsedTime = s.elapsedTime
        a.movingTime = s.movingTime
        a.averagePower = s.deviceWatts == true ? s.averageWatts : nil
        a.ascent = s.totalElevationGain
        a.isZwift = s.name.lowercased().hasPrefix("zwift")
        a.detailsVersion = Activity.currentDetails
    }

    /// Replaces the summary track with full-resolution GPS points.
    static func detailed(_ activity: Activity, points: [GeoPoint]?) -> Activity {
        guard let points, points.count >= 2 else {
            var a = activity
            a.isSummary = false // nothing better available
            return a
        }
        var a = Importer.makeActivity(points: points, id: activity.id, cacheKey: activity.cacheKey, name: activity.name,
                                      sport: activity.sport, startDate: activity.startDate,
                                      distance: activity.distance, isSummary: false)
        a.elapsedTime = activity.elapsedTime
        a.movingTime = activity.movingTime
        a.averagePower = activity.averagePower
        a.ascent = activity.ascent
        a.descent = activity.descent
        a.isZwift = activity.isZwift
        a.detailsVersion = activity.detailsVersion
        a.exportedFile = activity.exportedFile
        a.isVirtual = activity.isVirtual
        return a
    }

    static func sportName(_ type: String?) -> String {
        switch type {
        case "Ride", "MountainBikeRide", "GravelRide", "VirtualRide", "Handcycle", "Velomobile": "Cycling"
        case "EBikeRide", "EMountainBikeRide": "E-biking"
        case "Run", "TrailRun", "VirtualRun": "Running"
        case "Walk": "Walking"
        case "Hike": "Hiking"
        case "Swim": "Swimming"
        case "AlpineSki", "BackcountrySki", "NordicSki", "Snowboard": "Skiing"
        case "Rowing", "VirtualRow": "Rowing"
        case "InlineSkate": "Inline skating"
        default: "Activity"
        }
    }

    /// Decodes a Google encoded polyline (precision 5), as used in Strava's `summary_polyline`.
    static func decodePolyline(_ encoded: String) -> [GeoPoint] {
        var points = [GeoPoint]()
        let bytes = Array(encoded.utf8)
        var index = 0
        var lat = 0
        var lon = 0

        func next() -> Int? {
            var result = 0
            var shift = 0
            while index < bytes.count {
                let b = Int(bytes[index]) - 63
                index += 1
                result |= (b & 0x1F) << shift
                shift += 5
                if b < 0x20 { return (result & 1) != 0 ? ~(result >> 1) : result >> 1 }
            }
            return nil
        }

        while index < bytes.count {
            guard let dLat = next(), let dLon = next() else { break }
            lat += dLat
            lon += dLon
            points.append(GeoPoint(lat: Double(lat) / 1e5, lon: Double(lon) / 1e5))
        }
        return points
    }
}

/// What a batch of Strava webhook events asks for.
struct StravaEventChanges: Equatable {
    /// The athlete revoked Tileroam's access.
    var revoked = false
    /// Activities deleted on Strava: their copies must go. (Private activities stay: Tileroam has
    /// the athlete's permission to read them.)
    var removedActivities = Set<Int>()

    init(_ events: [StravaEvent]) {
        for event in events {
            switch event.type {
            case "deauthorized": revoked = true
            case "deleted": if let id = event.activity { removedActivities.insert(id) }
            default: break // "created": the regular sync fetches it
            }
        }
    }
}
