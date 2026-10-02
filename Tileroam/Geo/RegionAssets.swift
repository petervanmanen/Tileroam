import BackgroundAssets
import Foundation
import System

/// Municipality and postcode boundaries are Apple-hosted asset packs, one per country
/// ("regions-NL" holds NL-municipalities.fmr and NL-postcodes.fmr). They are downloaded on
/// demand, when the user has an activity in that country. See `Tools/build_asset_packs.sh`.
enum RegionAssets {
    static func packID(_ country: String) -> String { "regions-\(country)" }

    struct Availability: Sendable {
        /// Countries whose boundaries can be read.
        var available: Set<String> = []
        /// Countries whose pack couldn't be downloaded (offline, or not published yet), with the error.
        var failed: [String: String] = [:]
    }

    /// Downloads the packs of `countries` that aren't on the device yet: one at a time, each
    /// retried once.
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
                    let pack = try await manager.assetPack(withID: packID(country))
                    if #available(iOS 26.4, *) {
                        try await manager.ensureLocalAvailability(of: pack, requireLatestVersion: false)
                    } else {
                        try await manager.ensureLocalAvailability(of: pack)
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
    static var localDirectory: URL? {
        UserDefaults.standard.string(forKey: "RegionsDir").map { URL(filePath: $0, directoryHint: .isDirectory) }
    }
    #endif
}
