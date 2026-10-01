import BackgroundAssets
import ExtensionFoundation
import StoreKit

/// Lets the system download Tileroam's Apple-hosted asset packs (municipality and postcode
/// boundaries per country). All packs are on demand: the app asks for a country's pack when the
/// user has an activity there, so nothing is filtered here.
@main
struct DownloaderExtension: StoreDownloaderExtension {
    func shouldDownload(_ assetPack: AssetPack) -> Bool {
        true
    }
}
