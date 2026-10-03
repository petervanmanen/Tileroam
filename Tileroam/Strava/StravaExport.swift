import Foundation

/// Saves Strava activities as .fit files in the library (`Library.activitiesFolder`), named
/// "<start>-<name>-Strava-<id>.fit".
enum StravaExport {
    static func fileName(for activity: Activity) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let date = activity.startDate.map(formatter.string(from:)) ?? "undated"
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>\n\r\t")
        let name = activity.name.components(separatedBy: invalid).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        let id = StravaImport.stravaID(of: activity).map(String.init) ?? "x"
        return "\(date)-\(name.prefix(60))-Strava-\(id).fit"
    }

    static func fitData(for activity: Activity, stream: StravaStream?) -> Data {
        let start = activity.startDate ?? .now
        var encoder = FITEncoder(startDate: start,
                                 elapsedTime: activity.elapsedTime ?? stream?.times.last ?? 0,
                                 movingTime: activity.movingTime ?? 0,
                                 distance: activity.distance,
                                 sport: FITEncoder.sport(forName: activity.sport))
        // Keeps virtual rides recognizable when another device imports the file.
        if activity.isVirtual == true { encoder.subSport = 58 }
        if let stream {
            encoder.samples = stream.points.indices.map { i in
                FITEncoder.Sample(date: start.addingTimeInterval(i < stream.times.count ? stream.times[i] : Double(i)),
                                  point: stream.points[i],
                                  altitude: i < stream.altitudes.count ? stream.altitudes[i] : nil)
            }
        }
        return encoder.encode()
    }

    /// Files this app wrote (HealthFit's own exports end in "-Strava.fit" without an id).
    static func isOwnFile(_ name: String) -> Bool {
        name.range(of: #"-Strava-\d+\.fit$"#, options: .regularExpression) != nil
    }

    /// Files in the library that Tileroam saved from Strava.
    static func ownFiles() -> [String] {
        Library.names(in: Library.activitiesFolder, ext: "fit").filter(isOwnFile).sorted()
    }

    /// The files of the given Strava activities.
    static func ownFiles(of stravaIDs: Set<Int>) -> [String] {
        ownFiles().filter { name in stravaIDs.contains { name.hasSuffix("-Strava-\($0).fit") } }
    }

    /// Writes the file into the library and returns its name.
    static func write(_ activity: Activity, stream: StravaStream?) throws -> String {
        let name = fileName(for: activity)
        try fitData(for: activity, stream: stream).write(to: Library.activitiesFolder.appending(path: name), options: .atomic)
        Deletions.forget(name: name)
        return name
    }
}
