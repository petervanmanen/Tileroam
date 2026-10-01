import Foundation

/// Stores parsed activities so only new or changed files are parsed on the next launch.
enum TrackCache {

    private struct Payload: Codable {
        var version: Int
        var folder: String
        var activities: [Activity]
    }

    /// Separate cache files per source.
    enum Source: String {
        case folder = "activities.cache"
        case strava = "strava.cache"

        /// Bump when parsing or derived data (tiles, gemeenten, durations) changes.
        var version: Int {
            switch self {
            case .folder: 3
            case .strava: 1
            }
        }
    }

    private static func url(_ source: Source) -> URL {
        URL.applicationSupportDirectory.appending(path: source.rawValue)
    }

    static func load(_ source: Source = .folder, folder: String?) -> [Activity] {
        guard let data = try? Data(contentsOf: url(source)),
              let payload = try? PropertyListDecoder().decode(Payload.self, from: data),
              payload.version == source.version, payload.folder == folder else { return [] }
        return payload.activities
    }

    static func save(_ activities: [Activity], _ source: Source = .folder, folder: String?) {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        guard let data = try? encoder.encode(Payload(version: source.version, folder: folder ?? "", activities: activities)) else { return }
        try? FileManager.default.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
        try? data.write(to: url(source), options: .atomic)
    }

    static func clear(_ source: Source = .folder) {
        try? FileManager.default.removeItem(at: url(source))
    }
}
