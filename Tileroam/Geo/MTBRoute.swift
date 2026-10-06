import BackgroundAssets
import Foundation
import System

/// A signposted mountain bike route from OpenStreetMap (© OpenStreetMap contributors, ODbL), in the
/// routing countries: Tools/build_mtb_routes.py, the `mtbroutes` asset pack (see `MTBRouteData`).
/// Ridden when the user's rides cover it (`KlompenpadMatcher`, checkpoints every 100 m).
struct MTBRoute: Codable, Sendable, Identifiable, Hashable, ChallengeRoute {
    /// "osm-<relation id>".
    let id: String
    let name: String
    let ref: String?
    /// OpenStreetMap network: lcn (local), rcn (regional), ncn (national), icn (international), mtb.
    let network: String
    /// ISO code of the country whose extract it came from.
    let country: String
    /// Metres.
    let length: Double
    /// The relation on openstreetmap.org.
    let url: String
    /// The route's own website, if tagged.
    let website: String?
    let lat: Double
    let lon: Double
    /// Encoded polylines (precision 5).
    let lines: [String]

    var pieces: [[GeoPoint]] { lines.map(StravaImport.decodePolyline) }
    var link: URL? { URL(string: url) }
    var websiteLink: URL? { website.flatMap(URL.init(string:)) }

    var networkTitle: String {
        switch network {
        case "lcn": String(localized: "Local route")
        case "rcn": String(localized: "Regional route")
        case "ncn": String(localized: "National route")
        case "icn": String(localized: "International route")
        default: String(localized: "MTB route")
        }
    }

    /// Checkpoints every 100 m: the routes are long (some over 100 km).
    static let spacing = 100.0
    /// Only rides count, not walks or hikes along the trail.
    static func counts(_ activity: Activity) -> Bool { Sport.isCycling(activity.sport) || activity.sport == "E-biking" }
}

/// The mountain bike routes: an Apple-hosted asset pack, `mtbroutes` (mtb-routes.json, built by
/// Tools/build_mtb_routes.py, packaged by Tools/build_asset_packs.sh mtbroutes; uploaded with
/// Tools/upload_asset_packs.sh mtbroutes, or by the Asset packs workflow when it changes on main).
enum MTBRouteData {
    static let packID = "mtbroutes"
    private static let fileName = "mtb-routes.json"

    /// The list, if the pack is on the device already (empty otherwise).
    static func cached() -> [MTBRoute] {
        (try? data()).flatMap { try? JSONDecoder().decode([MTBRoute].self, from: $0) } ?? []
    }

    /// The list, downloading the pack when it isn't on the device yet (retried once).
    static func load() async throws -> [MTBRoute] {
        #if DEBUG
        if localFile != nil { return cached() }
        #endif
        let manager = AssetPackManager.shared
        var lastError: (any Error)?
        for attempt in 0..<2 {
            if attempt > 0 { try await Task.sleep(for: .seconds(2)) }
            do {
                let pack = try await manager.assetPack(withID: packID)
                if #available(iOS 26.4, *) {
                    try await manager.ensureLocalAvailability(of: pack, requireLatestVersion: false)
                } else {
                    try await manager.ensureLocalAvailability(of: pack)
                }
                return try JSONDecoder().decode([MTBRoute].self, from: try data())
            } catch {
                lastError = error
            }
        }
        throw lastError!
    }

    private static func data() throws -> Data {
        #if DEBUG
        if let localFile { return try Data(contentsOf: localFile) }
        #endif
        return try AssetPackManager.shared.contents(at: FilePath(fileName), searchingInAssetPackWithID: packID)
    }

    #if DEBUG
    /// Simulator and screenshots: `-MTBRoutesFile <repo>/AssetPacks/MTB/mtb-routes.json`; Debug
    /// builds for the Mac use the repository's file by default.
    static var localFile: URL? {
        if let file = UserDefaults.standard.string(forKey: "MTBRoutesFile") { return URL(filePath: file) }
        #if targetEnvironment(macCatalyst)
        let repo = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "AssetPacks/MTB/mtb-routes.json")
        if FileManager.default.fileExists(atPath: repo.path(percentEncoded: false)) { return repo }
        #endif
        return nil
    }
    #endif
}
