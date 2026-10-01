import Foundation

/// Persists access to user-selected (iCloud Drive) folders and lists their .fit files.
enum FolderAccess {
    enum Slot {
        /// Folder with .fit files to import (read only).
        case source
        /// The app's own folder where downloaded activities are saved.
        case export

        fileprivate var bookmarkKey: String { self == .source ? "folderBookmark" : "exportFolderBookmark" }
        fileprivate var nameKey: String { self == .source ? "folderName" : "exportFolderName" }
    }

    static func savedFolderName(_ slot: Slot = .source) -> String? {
        UserDefaults.standard.string(forKey: slot.nameKey)
    }

    static func save(_ url: URL, as slot: Slot = .source) throws {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(bookmark, forKey: slot.bookmarkKey)
        UserDefaults.standard.set(url.lastPathComponent, forKey: slot.nameKey)
    }

    static func resolve(_ slot: Slot = .source) -> URL? {
        #if DEBUG
        // Lets the simulator point at a folder on the host: -FitFolder /path/to/folder
        if slot == .source, let path = UserDefaults.standard.string(forKey: "FitFolder") {
            return URL(filePath: path, directoryHint: .isDirectory)
        }
        #endif
        guard let data = UserDefaults.standard.data(forKey: slot.bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else {
            return nil
        }
        if stale { try? save(url, as: slot) }
        return url
    }

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

    /// Where downloaded activities and planned routes are saved: the chosen save folder,
    /// or the app's internal storage when none is chosen.
    static func saveFolder() -> URL {
        resolve(.export) ?? internalFolder
    }

    static var hasChosenSaveFolder: Bool { resolve(.export) != nil }

    /// Go back to saving in the app's internal storage.
    static func clearSaveFolder() {
        UserDefaults.standard.removeObject(forKey: Slot.export.bookmarkKey)
        UserDefaults.standard.removeObject(forKey: Slot.export.nameKey)
    }

    // MARK: Import folders

    /// A folder with .fit files to import. Activities from the first (legacy) folder keep their
    /// plain relative path as id; others are prefixed with "<id>|" so file names can't collide.
    struct ImportFolder: Codable, Identifiable, Sendable, Equatable {
        var id: String
        var name: String
        var bookmark: Data

        static let legacyID = "main"
        static let internalID = "internal"

        /// The import folder inside the app's own storage.
        static let internalFolder = ImportFolder(id: internalID, name: "Tileroam", bookmark: Data())

        var isInternal: Bool { id == Self.internalID }

        func activityID(for relativePath: String) -> String {
            id == Self.legacyID ? relativePath : "\(id)|\(relativePath)"
        }

        func owns(_ activityID: String) -> Bool {
            id == Self.legacyID ? !activityID.contains("|") : activityID.hasPrefix("\(id)|")
        }
    }

    private static let importFoldersKey = "importFolders"

    static func importFolders() -> [ImportFolder] {
        #if DEBUG
        if let path = UserDefaults.standard.string(forKey: "FitFolder") {
            return [ImportFolder(id: ImportFolder.legacyID, name: URL(filePath: path).lastPathComponent, bookmark: Data())]
        }
        #endif
        if let data = UserDefaults.standard.data(forKey: importFoldersKey),
           let folders = try? JSONDecoder().decode([ImportFolder].self, from: data) {
            return folders
        }
        // Migrate the single folder of earlier versions.
        if let bookmark = UserDefaults.standard.data(forKey: Slot.source.bookmarkKey) {
            let folder = ImportFolder(id: ImportFolder.legacyID, name: savedFolderName(.source) ?? "", bookmark: bookmark)
            saveImportFolders([folder])
            return [folder]
        }
        return []
    }

    private static func saveImportFolders(_ folders: [ImportFolder]) {
        if let data = try? JSONEncoder().encode(folders) { UserDefaults.standard.set(data, forKey: importFoldersKey) }
    }

    /// Adds a folder (ignoring one that is already in the list) and returns it.
    @discardableResult
    static func addImportFolder(_ url: URL) throws -> ImportFolder {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        var folders = importFolders()
        let path = url.standardizedFileURL.path(percentEncoded: false)
        if let existing = folders.first(where: { resolve($0)?.standardizedFileURL.path(percentEncoded: false) == path }) {
            return existing
        }
        let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        let folder = ImportFolder(id: folders.isEmpty ? ImportFolder.legacyID : UUID().uuidString,
                                  name: url.lastPathComponent, bookmark: bookmark)
        folders.append(folder)
        saveImportFolders(folders)
        return folder
    }

    static func removeImportFolder(id: String) {
        saveImportFolders(importFolders().filter { $0.id != id })
        if id == ImportFolder.legacyID {
            UserDefaults.standard.removeObject(forKey: Slot.source.bookmarkKey)
            UserDefaults.standard.removeObject(forKey: Slot.source.nameKey)
        }
    }

    static func resolve(_ folder: ImportFolder) -> URL? {
        if folder.isInternal { return internalImportFolder }
        #if DEBUG
        if let path = UserDefaults.standard.string(forKey: "FitFolder") {
            return URL(filePath: path, directoryHint: .isDirectory)
        }
        #endif
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: folder.bookmark, options: [], relativeTo: nil,
                                 bookmarkDataIsStale: &stale) else { return nil }
        if stale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            var folders = importFolders()
            if let i = folders.firstIndex(where: { $0.id == folder.id }) {
                folders[i].bookmark = fresh
                saveImportFolders(folders)
            }
        }
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
            return (["iCloud Drive"] + components[(i + 2)...]).joined(separator: " › ")
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
