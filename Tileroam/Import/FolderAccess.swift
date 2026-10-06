import Foundation
import os

/// The app's own folders (on the device and in iCloud Drive) and the .fit files in a folder.
enum FolderAccess {
    // MARK: Internal storage

    /// "On My iPhone" / "On My iPad", as the Files app names the device's own storage.
    static var onMyDevice: String {
        isPad ? String(localized: "On My iPad") : String(localized: "On My iPhone")
    }

    /// Location of the internal storage as the Files app shows it.
    static var internalLocation: String { "\(onMyDevice) › Tileroam" }

    private static let isPad: Bool = {
        var info = utsname()
        uname(&info)
        let machine = withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        let model = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? machine
        return model.hasPrefix("iPad")
    }()

    /// The app's own storage, visible in the Files app as "On My iPhone › Tileroam".
    static var internalFolder: URL { URL.documentsDirectory }

    /// Always-present import folder inside the app ("On My iPhone › Tileroam › Import").
    static var internalImportFolder: URL {
        let url = internalFolder.appending(path: "Import", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: Sample rides

    /// Bundled example rides, copied here on request so new users (and App Review) can try the
    /// app without their own files. Kept on the device only, never in iCloud.
    static var sampleRidesFolder: URL {
        internalImportFolder.appending(path: "Sample Rides", directoryHint: .isDirectory)
    }

    static var bundledSampleRides: [URL] {
        (Bundle.main.urls(forResourcesWithExtension: "fit", subdirectory: nil) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("Sample-Ride-") }
    }

    static var hasSampleRides: Bool {
        FileManager.default.fileExists(atPath: sampleRidesFolder.path(percentEncoded: false))
    }

    // MARK: iCloud Drive

    static let iCloudContainerID = "iCloud.nl.petervanmanen.Tileroam"
    private static let iCloudURL = OSAllocatedUnfairLock<URL?>(initialState: nil)

    /// The app's own folder in iCloud Drive ("iCloud Drive › Tileroam"); nil when the user is
    /// not signed in to iCloud or iCloud Drive is off for Tileroam. Set by `updateICloudFolder()`.
    static var iCloudFolder: URL? { iCloudURL.withLock { $0 } }

    /// Location of the iCloud folder as the Files app shows it.
    static var iCloudLocation: String { "iCloud Drive › Tileroam" }

    /// Looks up the iCloud folder. The first lookup can take a while: call it off the main thread.
    @discardableResult
    static func updateICloudFolder() -> URL? {
        let url: URL? = if FileManager.default.ubiquityIdentityToken != nil,
                           let container = FileManager.default.url(forUbiquityContainerIdentifier: iCloudContainerID) {
            container.appending(path: "Documents", directoryHint: .isDirectory)
        } else {
            nil
        }
        if let url { try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        iCloudURL.withLock { $0 = url }
        return url
    }

    /// Human readable location, e.g. "iCloud Drive › Sport › FIT".
    static func displayLocation(_ url: URL) -> String {
        let path = url.standardizedFileURL.path(percentEncoded: false)
        let components = path.split(separator: "/").map(String.init)
        if let i = components.firstIndex(of: "com~apple~CloudDocs") {
            return (["iCloud Drive"] + components[(i + 1)...]).joined(separator: " › ")
        }
        if let i = components.firstIndex(of: "Mobile Documents"), i + 1 < components.count {
            // An app's container, e.g. "iCloud~nl~petervanmanen~Tileroam/Documents/Strava"
            let app = components[i + 1].split(separator: "~").last.map(String.init) ?? ""
            let rest = components.dropFirst(i + 2).drop { $0 == "Documents" }
            return (["iCloud Drive", app] + rest).joined(separator: " › ")
        }
        if path.hasPrefix(URL.documentsDirectory.standardizedFileURL.path(percentEncoded: false)) {
            return internalLocation
        }
        if let i = components.firstIndex(of: "File Provider Storage") {
            return ([onMyDevice] + components[(i + 1)...]).joined(separator: " › ")
        }
        return components.suffix(3).joined(separator: " › ")
    }

    struct FitFile: Sendable {
        let url: URL
        let relativePath: String
        let cacheKey: String
    }

    /// Recursively lists .fit files, including iCloud placeholders that are not downloaded yet.
    static func fitFiles(in folder: URL) -> [FitFile] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys,
                                                              options: [.skipsPackageDescendants]) else { return [] }
        let basePath = folder.standardizedFileURL.path(percentEncoded: false)
        var files = [FitFile]()

        for case let url as URL in enumerator {
            var name = url.lastPathComponent
            var realURL = url
            if name.hasPrefix("."), name.hasSuffix(".icloud") {
                // Legacy placeholder: ".Name.fit.icloud"
                name = String(name.dropFirst().dropLast(".icloud".count))
                realURL = url.deletingLastPathComponent().appending(path: name)
            } else if name.hasPrefix(".") {
                continue
            }
            guard name.lowercased().hasSuffix(".fit") else { continue }

            let values = (try? realURL.resourceValues(forKeys: Set(keys))) ?? (try? url.resourceValues(forKeys: Set(keys)))
            let modified = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
            var relative = realURL.standardizedFileURL.path(percentEncoded: false)
            if relative.hasPrefix(basePath) { relative.removeFirst(basePath.count) }
            if relative.hasPrefix("/") { relative.removeFirst() }
            files.append(FitFile(url: realURL, relativePath: relative, cacheKey: String(Int(modified))))
        }
        return files.sorted { $0.relativePath < $1.relativePath }
    }

    /// Reads a file through NSFileCoordinator, which waits for iCloud to download it if needed.
    static func read(_ url: URL) throws -> Data {
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        var coordinationError: NSError?
        var result: Result<Data, Error> = .failure(CocoaError(.fileReadUnknown))
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readURL in
            result = Result { try Data(contentsOf: readURL) }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }
}
