import BackgroundAssets
import Foundation
import Synchronization
import System

/// Municipality and postcode boundaries are Apple-hosted asset packs, one per country
/// ("regions-NL" holds NL-municipalities.fmr and NL-postcodes.fmr). They are downloaded on
/// demand, when the user has an activity in that country. See `Tools/build_asset_packs.sh`.
enum RegionAssets {
    /// Countries whose first pack was archived in App Store Connect (October 2026, when their
    /// boundaries were dropped for a while). Archiving can't be undone: the website can't, the API
    /// answers 405, and new versions of an archived pack are refused (409). So they have a new
    /// pack ID. The tools read this table (`Tools/pack_ids.zsh`, `Tools/asset_packs.swift`).
    static let renamedPacks: [String: String] = ["FR": "regions-FR-2", "CH": "regions-CH-2", "AT": "regions-AT-2"]

    static func packID(_ country: String) -> String { renamedPacks[country] ?? "regions-\(country)" }

    struct Availability: Sendable {
        /// Countries whose boundaries can be read.
        var available: Set<String> = []
        /// Countries whose pack couldn't be downloaded (offline, or not published yet), with the error.
        var failed: [String: String] = [:]
    }

    /// How long one pack may take. The Mac app once waited for a download forever, and with it
    /// the tiles of every new activity (issue fixed in 1.8.2).
    static let timeout: Duration = .seconds(120)

    /// Downloads the packs of `countries` that aren't on the device yet: one at a time, each
    /// retried once, each within `timeout`.
    static func makeAvailable(_ countries: Set<String>) async -> Availability {
        #if DEBUG
        if localDirectory != nil { return Availability(available: countries) }
        #endif
        var result = Availability()
        let manager = AssetPackManager.shared
        for country in countries.sorted() {
            var lastError: (any Error)?
            for attempt in 0..<2 {
                if attempt > 0 { try? await Task.sleep(for: .seconds(2)) }
                do {
                    let id = packID(country)
                    try await withTimeout(timeout) {
                        let pack = try await manager.assetPack(withID: id)
                        if #available(iOS 26.4, *) {
                            try await manager.ensureLocalAvailability(of: pack, requireLatestVersion: false)
                        } else {
                            try await manager.ensureLocalAvailability(of: pack)
                        }
                    }
                    lastError = nil
                    break
                } catch {
                    lastError = error
                    if Task.isCancelled { return result }
                }
            }
            if let lastError {
                result.failed[country] = lastError.localizedDescription
            } else {
                result.available.insert(country)
            }
        }
        return result
    }

    struct TimeoutError: LocalizedError {
        var errorDescription: String? { String(localized: "The download took too long.") }
    }

    /// Runs `operation`, throwing `TimeoutError` when it takes longer than `limit`. Doesn't wait
    /// for an operation that ignores cancellation: it's cancelled and left behind.
    static func withTimeout(_ limit: Duration, _ operation: @escaping @Sendable () async throws -> Void) async throws {
        let done = Mutex(false)
        func claim() -> Bool { done.withLock { first in defer { first = true }; return !first } }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            let work = Task {
                do {
                    try await operation()
                    if claim() { continuation.resume() }
                } catch {
                    if claim() { continuation.resume(throwing: error) }
                }
            }
            Task {
                try? await Task.sleep(for: limit)
                if claim() {
                    work.cancel()
                    continuation.resume(throwing: TimeoutError())
                }
            }
        }
    }

    /// The contents of one boundary file from a downloaded pack.
    static func data(country: String, kind: AreaKind) throws -> Data {
        let name = "\(country)-\(kind.rawValue).fmr"
        #if DEBUG
        if let localDirectory { return try Data(contentsOf: localDirectory.appending(path: name)) }
        #endif
        return try AssetPackManager.shared.contents(at: FilePath(name), searchingInAssetPackWithID: packID(country))
    }

    /// Size on the device of a country's downloaded boundary files, or nil when not downloaded.
    static func downloadedBytes(country: String) -> Int? {
        let names = AreaKind.allCases.map { "\(country)-\($0.rawValue).fmr" }
        var total = 0, found = false
        for name in names {
            let url: URL?
            #if DEBUG
            if let localDirectory {
                url = localDirectory.appending(path: name)
            } else {
                url = try? AssetPackManager.shared.url(for: FilePath(name))
            }
            #else
            url = try? AssetPackManager.shared.url(for: FilePath(name))
            #endif
            if let url, let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += size
                found = true
            }
        }
        return found ? total : nil
    }

    #if DEBUG
    /// Development and screenshots in the simulator: read the files from a folder on the Mac
    /// instead of asset packs, e.g. `-RegionsDir /path/to/Tileroam/AssetPacks/Regions`.
    /// Debug builds for the Mac use the repository's folder by default: Apple-hosted packs only
    /// reach TestFlight and App Store builds.
    static var localDirectory: URL? {
        if let dir = UserDefaults.standard.string(forKey: "RegionsDir") { return URL(filePath: dir, directoryHint: .isDirectory) }
        #if targetEnvironment(macCatalyst)
        let repo = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "AssetPacks/Regions", directoryHint: .isDirectory)
        if FileManager.default.fileExists(atPath: repo.path(percentEncoded: false)) { return repo }
        #endif
        return nil
    }
    #endif
}
