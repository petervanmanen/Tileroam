import Foundation

/// A boscafé (a café or pavilion in the woods) of the Boscafé Challenge. The list is on
/// Cloudflare R2 (`<server>/Boscafes/`, see `BoscafeData`). An activity visits a boscafé by
/// passing within `TrappistMatcher.radius` of it, like the Trappist breweries.
struct Boscafe: Codable, Sendable, Identifiable, Hashable, ChallengePlace {
    let id: String
    let name: String
    let place: String
    /// Drawn on the map: 🌲 ☕ 🍺 🍽️ 🥞 🫖.
    let emoji: String
    let lat: Double
    let lon: Double
}

/// The Boscafé Challenge's list on Cloudflare R2, uploaded with Tools/upload_boscafes_r2.sh from
/// AssetPacks/Boscafes: `Boscafes/boscafes.json`. The app keeps a copy in
/// `Application Support/Boscafes`, checks for a new list at most once a day, and uses its copy when
/// offline.
enum BoscafeData {
    static var folder: URL { URL.applicationSupportDirectory.appending(path: "Boscafes", directoryHint: .isDirectory) }
    private static let listName = "boscafes.json"

    /// The list on the device (empty before the first download).
    static func cached(in folder: URL = folder) -> [Boscafe] {
        #if DEBUG
        if let localFile { return (try? JSONDecoder().decode([Boscafe].self, from: Data(contentsOf: localFile))) ?? [] }
        #endif
        return RemoteList.cached(Boscafe.self, name: listName, in: folder)
    }

    /// The list (see `RemoteList`). Throws when there's no list at all (offline on first use).
    static func load(from server: URL = RoutingData.serverURL, session: URLSession = RoutingData.tileSession,
                     into folder: URL = folder, now: Date = .now) async throws -> [Boscafe] {
        #if DEBUG
        if localFile != nil { return cached() }
        #endif
        return try await RemoteList.load(Boscafe.self, name: listName, remote: "Boscafes", into: folder,
                                         from: server, session: session, now: now)
    }

    #if DEBUG
    /// Simulator and screenshots: `-BoscafesFile <repo>/AssetPacks/Boscafes/boscafes.json`; Debug
    /// builds for the Mac use the repository's file by default.
    static var localFile: URL? {
        if let file = UserDefaults.standard.string(forKey: "BoscafesFile") { return URL(filePath: file) }
        #if targetEnvironment(macCatalyst)
        let repo = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "AssetPacks/Boscafes/boscafes.json")
        if FileManager.default.fileExists(atPath: repo.path(percentEncoded: false)) { return repo }
        #endif
        return nil
    }
    #endif
}
