import CryptoKit
import Foundation
import Synchronization

/// Tileroam's own files: every activity (.fit) and planned route (.gpx) lives in the app,
/// visible in the Files app as "On My iPhone › Tileroam › Activities" and "› Routes".
///
/// With iCloud sync on (the default when iCloud Drive is available), both folders are mirrored
/// to "iCloud Drive › Tileroam › Activities" and "› Routes", so the user's other devices get them:
/// `pull` brings files from iCloud, `push` sends this device's files. Activities the user
/// deletes are remembered in iCloud's key-value store (`Deletions`), so another device removes
/// its copy instead of uploading it again. Turning sync off leaves both copies as they are.
enum Library {
    /// Settings → Activities → "Sync with iCloud"; on unless the user turns it off.
    static let syncSettingKey = "iCloudSync"

    static var isSyncOn: Bool { UserDefaults.standard.object(forKey: syncSettingKey) as? Bool ?? true }

    static var activitiesFolder: URL { folder(URL.documentsDirectory, "Activities") }
    static var routesFolder: URL { folder(URL.documentsDirectory, "Routes") }
    static var cloudActivitiesFolder: URL? { FolderAccess.iCloudFolder.map { folder($0, "Activities") } }
    static var cloudRoutesFolder: URL? { FolderAccess.iCloudFolder.map { folder($0, "Routes") } }

    private static func folder(_ base: URL, _ name: String) -> URL {
        let url = base.appending(path: name, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: Adding

    /// The name a file from elsewhere gets in the library. Files Tileroam saved from Strava keep
    /// their name ("…-Strava-123.fit", one per Strava activity); others get a short content hash
    /// ("Morning Ride-1a2b3c4d.fit"), so the same file imported twice has the same name, and two
    /// different files with the same name don't overwrite each other.
    static func libraryName(original: String, data: Data) -> String {
        if StravaExport.isOwnFile(original) { return original }
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>\n\r\t")
        var stem = (original as NSString).deletingPathExtension.components(separatedBy: invalid).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        if stem.isEmpty { stem = "Activity" }
        let hash = SHA256.hash(data: data).prefix(4).map { String(format: "%02x", $0) }.joined()
        if stem.hasSuffix("-\(hash)") { return stem + ".fit" } // already a library name
        return "\(stem.prefix(60))-\(hash).fit"
    }

    /// Adds a .fit file to the library (keeping one that's already there) and returns its name.
    /// Adding a file again undoes an earlier deletion of that name.
    @discardableResult
    static func add(_ data: Data, originalName: String) throws -> String {
        let name = libraryName(original: originalName, data: data)
        let url = activitiesFolder.appending(path: name)
        if !FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            try data.write(to: url, options: .atomic)
        }
        Deletions.forget(name: name)
        return name
    }

    /// Copies the .fit files of `urls` (files, or folders with .fit files at any depth) into the
    /// library once; the originals aren't watched afterwards. Returns the names added and the
    /// files that couldn't be read.
    static func importOnce(_ urls: [URL]) -> (added: [String], failed: [String]) {
        var added = [String](), failed = [String]()
        for url in urls {
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            let isFolder = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let files = isFolder ? FolderAccess.fitFiles(in: url).map(\.url) : [url]
            for file in files where file.pathExtension.lowercased() == "fit" {
                do {
                    added.append(try add(FolderAccess.read(file), originalName: file.lastPathComponent))
                } catch {
                    failed.append(String(localized: "Could not read “\(file.lastPathComponent)”: \(error.localizedDescription)"))
                }
            }
        }
        return (added, failed)
    }

    /// Saves a planned route.
    static func saveRoute(_ data: Data, name: String) throws {
        try data.write(to: routesFolder.appending(path: name), options: .atomic)
    }

    // MARK: Deleting

    /// Deletes activity files from this device and from iCloud, and remembers them as deleted
    /// so the user's other devices delete their copies too.
    static func delete(names: [String]) {
        guard !names.isEmpty else { return }
        Deletions.add(names: names)
        for name in names {
            try? FileManager.default.removeItem(at: activitiesFolder.appending(path: name))
            if isSyncOn, let cloud = cloudActivitiesFolder { coordinatedRemove(cloud.appending(path: name)) }
        }
    }

    // MARK: iCloud

    /// Brings activities and routes from iCloud that this device doesn't have, and applies
    /// deletions made on other devices. Returns the number of files that arrived.
    @discardableResult
    static func pull(progress: @escaping @Sendable (Int, Int) -> Void = { _, _ in }) -> Int {
        guard isSyncOn, let cloud = cloudActivitiesFolder, let cloudRoutes = cloudRoutesFolder else { return 0 }
        let deleted = Deletions.names()
        applyDeletions(deleted, local: activitiesFolder, cloud: cloud)
        return copyMissing(from: cloud, to: activitiesFolder, ext: "fit", skipping: deleted, coordinated: false, progress: progress)
            + copyMissing(from: cloudRoutes, to: routesFolder, ext: "gpx", skipping: [], coordinated: false)
    }

    /// Sends this device's activities and routes that iCloud doesn't have. Returns the number sent.
    @discardableResult
    static func push() -> Int {
        guard isSyncOn, let cloud = cloudActivitiesFolder, let cloudRoutes = cloudRoutesFolder else { return 0 }
        let deleted = Deletions.names()
        return copyMissing(from: activitiesFolder, to: cloud, ext: "fit", skipping: deleted, coordinated: true)
            + copyMissing(from: routesFolder, to: cloudRoutes, ext: "gpx", skipping: [], coordinated: true)
    }

    /// Removes deleted files from both folders.
    static func applyDeletions(_ deleted: Set<String>, local: URL, cloud: URL) {
        let inCloud = names(in: cloud, ext: "fit")
        for name in deleted {
            try? FileManager.default.removeItem(at: local.appending(path: name))
            if inCloud.contains(name) { coordinatedRemove(cloud.appending(path: name)) }
        }
    }

    /// Copies the files of `source` that `target` doesn't have (by name), except `skipping`.
    /// Reading waits for iCloud downloads; writing into iCloud is coordinated.
    ///
    /// Fast on a new device with many activities: iCloud is asked for all missing files at once
    /// (it downloads several in parallel), and `parallel` files are read and written at the same
    /// time. One at a time, every file waited for its own download (about a second each).
    static func copyMissing(from source: URL, to target: URL, ext: String, skipping: Set<String>, coordinated: Bool,
                            parallel: Int = 8, progress: @escaping @Sendable (Int, Int) -> Void = { _, _ in }) -> Int {
        let missing = names(in: source, ext: ext).subtracting(names(in: target, ext: ext)).subtracting(skipping).sorted()
        guard !missing.isEmpty else { return 0 }
        for name in missing { try? FileManager.default.startDownloadingUbiquitousItem(at: source.appending(path: name)) }
        let state = Mutex((done: 0, copied: 0))
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = parallel
        queue.qualityOfService = .userInitiated
        for name in missing {
            queue.addOperation {
                var written = false
                if let data = readWithin(downloadTimeout, source.appending(path: name)) {
                    let url = target.appending(path: name)
                    written = coordinated ? (try? coordinatedWrite(data, to: url)) != nil : (try? data.write(to: url, options: .atomic)) != nil
                }
                let done = state.withLock { s in
                    s.done += 1
                    if written { s.copied += 1 }
                    return s.done
                }
                progress(done, missing.count)
            }
        }
        queue.waitUntilAllOperationsAreFinished()
        return state.withLock { $0.copied }
    }

    /// How long one iCloud file may take to download before it's left for the next refresh.
    static let downloadTimeout: TimeInterval = 120

    /// Reads a file, waiting for iCloud to download it, but at most `timeout` seconds: a download
    /// that stalls would otherwise block the refresh forever (the coordinated read waits for it).
    static func readWithin(_ timeout: TimeInterval, _ url: URL) -> Data? {
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        nonisolated(unsafe) let coordinator = NSFileCoordinator()
        let stop = DispatchWorkItem { coordinator.cancel() } // the read then returns with an error
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: stop)
        defer { stop.cancel() }
        var coordinationError: NSError?
        var data: Data?
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { readURL in
            data = try? Data(contentsOf: readURL)
        }
        return coordinationError == nil ? data : nil
    }

    /// Whether iCloud has activities (also files not downloaded yet), for a new device.
    static var cloudHasActivities: Bool {
        guard let cloud = cloudActivitiesFolder else { return false }
        return !names(in: cloud, ext: "fit").isEmpty
    }

    /// File names with this extension in `folder`, including iCloud placeholders (".name.icloud").
    static func names(in folder: URL, ext: String) -> Set<String> {
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
        return Set(entries.compactMap { entry in
            let name = entry.hasPrefix(".") && entry.hasSuffix(".icloud") ? String(entry.dropFirst().dropLast(7)) : entry
            return !name.hasPrefix(".") && name.lowercased().hasSuffix(".\(ext)") ? name : nil
        })
    }

    static func coordinatedWrite(_ data: Data, to url: URL) throws {
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { url in
            do { try data.write(to: url, options: .atomic) } catch { writeError = error }
        }
        if let error = coordinationError ?? writeError { throw error }
    }

    static func coordinatedRemove(_ url: URL) {
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &coordinationError) { url in
            try? FileManager.default.removeItem(at: url)
        }
    }
}

/// Activities the user deleted, shared by their devices through iCloud's key-value store (and
/// kept in UserDefaults too, for when iCloud is off): file names in the library, and Strava
/// activity IDs, so the Strava sync doesn't bring them back.
///
/// Each entry records when it changed: a positive time when it was deleted, a negative one when
/// it was added again (`forget`). Merging two lists keeps the most recent change per entry, so
/// a re-import on one device also reaches devices that still remember the deletion.
enum Deletions {
    private static let namesKey = "deletedActivityFiles"
    private static let stravaKey = "deletedStravaActivities"
    /// iCloud's key-value store holds at most 1 MB; the oldest entries are dropped past this.
    static let limit = 5_000

    static func names(local: KeyValueStore = UserDefaults.standard,
                      cloud: KeyValueStore = NSUbiquitousKeyValueStore.default) -> Set<String> {
        Set(merged(namesKey, local: local, cloud: cloud).filter { $0.value > 0 }.keys)
    }

    static func stravaIDs(local: KeyValueStore = UserDefaults.standard,
                          cloud: KeyValueStore = NSUbiquitousKeyValueStore.default) -> Set<Int> {
        Set(merged(stravaKey, local: local, cloud: cloud).filter { $0.value > 0 }.keys.compactMap { Int($0) })
    }

    static func add(names: [String], local: KeyValueStore = UserDefaults.standard,
                    cloud: KeyValueStore = NSUbiquitousKeyValueStore.default, now: Date = .now) {
        change(names, to: now.timeIntervalSince1970, key: namesKey, local: local, cloud: cloud)
    }

    static func add(stravaIDs: [Int], local: KeyValueStore = UserDefaults.standard,
                    cloud: KeyValueStore = NSUbiquitousKeyValueStore.default, now: Date = .now) {
        change(stravaIDs.map(String.init), to: now.timeIntervalSince1970, key: stravaKey, local: local, cloud: cloud)
    }

    /// A file added again (imported or saved from Strava once more) is no longer deleted.
    static func forget(name: String, local: KeyValueStore = UserDefaults.standard,
                       cloud: KeyValueStore = NSUbiquitousKeyValueStore.default, now: Date = .now) {
        guard (merged(namesKey, local: local, cloud: cloud)[name] ?? 0) > 0 else { return }
        change([name], to: -now.timeIntervalSince1970, key: namesKey, local: local, cloud: cloud)
    }

    /// Both stores together, the most recent change per entry, written back where it differs.
    private static func merged(_ key: String, local: KeyValueStore, cloud: KeyValueStore) -> [String: Double] {
        let a = local.object(forKey: key) as? [String: Double] ?? [:]
        let b = cloud.object(forKey: key) as? [String: Double] ?? [:]
        let all = a.merging(b) { abs($0) >= abs($1) ? $0 : $1 }
        if all != a { local.set(all, forKey: key) }
        if all != b { cloud.set(all, forKey: key) }
        return all
    }

    private static func change(_ entries: [String], to time: Double, key: String, local: KeyValueStore, cloud: KeyValueStore) {
        guard !entries.isEmpty else { return }
        var all = merged(key, local: local, cloud: cloud)
        for entry in entries { all[entry] = time }
        if all.count > limit {
            for (entry, _) in all.sorted(by: { abs($0.value) < abs($1.value) }).prefix(all.count - limit) { all[entry] = nil }
        }
        local.set(all, forKey: key)
        cloud.set(all, forKey: key)
    }
}

// MARK: Migration from earlier versions

extension Library {
    static let migratedKey = "libraryMigrated"

    static var isMigrated: Bool { UserDefaults.standard.bool(forKey: migratedKey) }

    /// Copies every .fit file and planned route that earlier versions read or saved into the
    /// library, once per device, so nothing has to be downloaded from Strava again:
    /// - the folders the user chose to import (which are no longer watched afterwards);
    /// - the app's own storage ("On My iPhone › Tileroam": Import, Strava; not the sample rides);
    /// - Tileroam's iCloud folder ("iCloud Drive › Tileroam": Import, Strava and anything else);
    /// - the chosen save folder ("Strava" and "Routes").
    /// The originals stay where they are (older versions on other devices still use them).
    /// Duplicates are removed afterwards like any others (`ActivityStore.refresh`).
    static func migrate(importFolders: [URL], saveFolder: URL?,
                        progress: @Sendable (Int, Int) -> Void = { _, _ in }) -> (files: Int, failed: [String]) {
        var sources = importFolders.map { ($0, "") }
        // The app's own storage and its iCloud folder, all of it (earlier versions read every .fit
        // file there), except the library itself.
        sources.append((URL.documentsDirectory, ""))
        if let cloud = FolderAccess.iCloudFolder { sources.append((cloud, "")) }
        if let saveFolder { sources.append((saveFolder, "Strava")) }

        // Every .fit file first, so the progress has a total. Not the library itself or the
        // sample rides (by their exact location: a user's own folder may well be called "Activities").
        let skip = ([activitiesFolder, FolderAccess.sampleRidesFolder] + [cloudActivitiesFolder].compactMap { $0 })
            .map { $0.standardizedFileURL.path(percentEncoded: false) }
        var files = [URL]()
        var opened = [URL]()
        for (folder, sub) in sources {
            if folder.startAccessingSecurityScopedResource() { opened.append(folder) }
            let dir = sub.isEmpty ? folder : folder.appending(path: sub, directoryHint: .isDirectory)
            files += FolderAccess.fitFiles(in: dir).map(\.url).filter { url in
                let path = url.standardizedFileURL.path(percentEncoded: false)
                return !skip.contains { path.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") }
            }
        }
        defer { opened.forEach { $0.stopAccessingSecurityScopedResource() } }

        var copied = 0, failed = [String]()
        for (n, file) in files.enumerated() {
            progress(n, files.count)
            do {
                try add(FolderAccess.read(file), originalName: file.lastPathComponent)
                copied += 1
            } catch {
                failed.append(String(localized: "Could not read “\(file.lastPathComponent)”: \(error.localizedDescription)"))
            }
        }
        // Planned routes from a chosen save folder ("iCloud Drive › Tileroam › Routes" and the
        // app's own Routes folder already are the library's).
        if let saveFolder {
            let routes = saveFolder.appending(path: "Routes", directoryHint: .isDirectory)
            for name in names(in: routes, ext: "gpx") where !FileManager.default.fileExists(atPath: routesFolder.appending(path: name).path(percentEncoded: false)) {
                if let data = try? FolderAccess.read(routes.appending(path: name)) { try? saveRoute(data, name: name) }
            }
        }
        return (copied, failed)
    }
}
