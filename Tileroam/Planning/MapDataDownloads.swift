import Foundation
import Network

/// Large map downloads (route planning areas) wait for Wi-Fi unless the user allows mobile data,
/// in Settings or with "Download Anyway". Apple's Background Assets has no mobile-data policy of its
/// own: an on-demand pack downloads on any network as soon as the app asks for it.
enum MapDataDownloads {
    /// Downloads above this many bytes wait for Wi-Fi.
    static let wifiThreshold = 25_000_000
    /// Settings → Storage: "Download Map Data over Mobile Data".
    static let allowMobileDataKey = "allowMobileDataMapDownloads"

    /// Whether a download of `bytes` may start now.
    static func mayDownload(bytes: Int, allowedOnce: Bool = false) -> Bool {
        mayDownload(bytes: bytes, isExpensive: NetworkMonitor.shared.isExpensive,
                    isConstrained: NetworkMonitor.shared.isConstrained,
                    allowMobileData: allowedOnce || UserDefaults.standard.bool(forKey: allowMobileDataKey))
    }

    /// The rule itself: small downloads always; large ones on Wi-Fi (not expensive, not in Low Data
    /// Mode) or when the user allows mobile data.
    static func mayDownload(bytes: Int, isExpensive: Bool, isConstrained: Bool, allowMobileData: Bool) -> Bool {
        bytes <= wifiThreshold || allowMobileData || (!isExpensive && !isConstrained)
    }

    /// "73 MB"; one decimal below 10 MB ("0.4 MB"), and at least 0.1 MB for anything not empty.
    static func format(_ bytes: Int) -> String {
        let mb = bytes > 0 ? max(Double(bytes) / 1_000_000, 0.1) : 0
        return Measurement(value: mb, unit: UnitInformationStorage.megabytes)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided,
                                    numberFormatStyle: .number.precision(.fractionLength(mb < 10 ? 0...1 : 0...0))))
    }
}

/// The current network: mobile data and personal hotspots are "expensive", Low Data Mode is
/// "constrained".
final class NetworkMonitor: @unchecked Sendable {
    static let shared = NetworkMonitor()
    private let monitor = NWPathMonitor()

    private init() {
        monitor.start(queue: DispatchQueue(label: "Tileroam.NetworkMonitor"))
    }

    var isExpensive: Bool { monitor.currentPath.isExpensive }
    var isConstrained: Bool { monitor.currentPath.isConstrained }
}
