import BackgroundAssets
import Foundation
import System

/// The on-device routing data: Valhalla tiles for the supported countries, built from
/// OpenStreetMap by `Tools/build_routing_tiles.sh` and delivered as an Apple-hosted asset pack.
/// See docs/ROUTING.md for adding countries.
enum RoutingData {
    /// Countries the routing data covers. Built together, so routes cross their borders.
    static let countries: Set<String> = ["NL", "BE", "LU"]
    static let packID = "routing-benelux"
    static let fileName = "routing-benelux.tar"

    /// Whether `p` lies in a country the routing data covers.
    static func covers(_ p: GeoPoint) -> Bool {
        guard let country = CountryOutlines.bundled?.country(at: p) else { return false }
        return countries.contains(country)
    }

    /// The tile extract on the device, downloading the asset pack first when needed.
    static func tileExtract() async throws -> URL {
        #if DEBUG
        // Simulator: -RoutingTar /path/to/routing-benelux.tar (made by Tools/build_routing_tiles.sh).
        if let path = UserDefaults.standard.string(forKey: "RoutingTar") { return URL(filePath: path) }
        #endif
        let manager = AssetPackManager.shared
        do {
            let pack = try await manager.assetPack(withID: packID)
            if #available(iOS 26.4, *) {
                try await manager.ensureLocalAvailability(of: pack, requireLatestVersion: false)
            } else {
                try await manager.ensureLocalAvailability(of: pack)
            }
            return try manager.url(for: FilePath(fileName))
        } catch {
            throw RoutingError.dataUnavailable(error.localizedDescription)
        }
    }

    /// Valhalla's configuration (`Resources/valhalla.json`, made with the same Valhalla version as
    /// the tiles) pointing at `tileExtract`, written to Application Support.
    static func writeConfig(tileExtract: URL) throws -> URL {
        guard let template = Bundle.main.url(forResource: "valhalla", withExtension: "json"),
              let data = try? Data(contentsOf: template),
              var config = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var mjolnir = config["mjolnir"] as? [String: Any] else {
            throw RoutingError.dataUnavailable("valhalla.json")
        }
        mjolnir["tile_extract"] = tileExtract.path(percentEncoded: false)
        mjolnir["tile_dir"] = ""
        config["mjolnir"] = mjolnir
        let folder = URL.applicationSupportDirectory.appending(path: "Routing", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "valhalla.json")
        try JSONSerialization.data(withJSONObject: config).write(to: url, options: .atomic)
        return url
    }
}
