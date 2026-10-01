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
        /// Countries whose pack couldn't be downloaded (offline, or not published yet).
        var failed: Set<String> = []
    }

    /// Downloads the packs of `countries` that aren't on the device yet.
    static func makeAvailable(_ countries: Set<String>) async -> Availability {
        #if DEBUG
        if localDirectory != nil { return Availability(available: countries) }
        #endif
        var result = Availability()
        await withTaskGroup(of: (String, Bool).self) { group in
            for country in countries {
                group.addTask {
                    let manager = AssetPackManager.shared
                    do {
                        let pack = try await manager.assetPack(withID: packID(country))
                        if #available(iOS 26.4, *) {
                            try await manager.ensureLocalAvailability(of: pack, requireLatestVersion: false)
                        } else {
                            try await manager.ensureLocalAvailability(of: pack)
                        }
                        return (country, true)
                    } catch {
                        return (country, false)
                    }
                }
            }
            for await (country, ok) in group {
                if ok { result.available.insert(country) } else { result.failed.insert(country) }
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

    #if DEBUG
    /// Development and screenshots in the simulator: read the files from a folder on the Mac
    /// instead of asset packs, e.g. `-RegionsDir /path/to/Tileroam/AssetPacks/Regions`.
    static var localDirectory: URL? {
        UserDefaults.standard.string(forKey: "RegionsDir").map { URL(filePath: $0, directoryHint: .isDirectory) }
    }
    #endif
}
