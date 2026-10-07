import BackgroundAssets
import Foundation

/// Where the user's challenge files live: a Challenges folder next to Activities and Routes. With
/// iCloud sync on that's "iCloud Drive › Tileroam › Challenges", so every device has the same
/// challenges; a file put in the device's own folder ("On My iPhone › Tileroam › Challenges") is
/// moved there. Without iCloud the device's folder is used.
///
/// The app keeps a copy of each file it read (`mirrorFolder`), for when iCloud can't deliver a
/// file in time; a challenge whose file was removed is forgotten.
enum ChallengeFiles {
    static let folderName = "Challenges"
    /// The format, documented on GitHub.
    static let formatURL = URL(string: "https://github.com/petervanmanen/Tileroam/blob/main/challenges/README.md")!
    /// The file extensions read as challenges.
    static let extensions = ["geojson", "json"]

    static var localFolder: URL { folder(URL.documentsDirectory) }
    static var cloudFolder: URL? {
        guard Library.isSyncOn, let cloud = FolderAccess.iCloudFolder else { return nil }
        return folder(cloud)
    }
    static var mirrorFolder: URL { folder(URL.applicationSupportDirectory) }

    /// Where to put challenge files, as the Files app shows it.
    static var location: String {
        if cloudFolder != nil { return "\(FolderAccess.iCloudLocation) › \(folderName)" }
        #if targetEnvironment(macCatalyst)
        return String(localized: "On My Mac › Tileroam › \(folderName)")
        #else
        return String(localized: "On My iPhone › Tileroam › \(folderName)")
        #endif
    }

    private static func folder(_ base: URL) -> URL {
        let url = base.appending(path: folderName, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func names(in folder: URL) -> Set<String> {
        extensions.reduce(into: Set<String>()) { $0.formUnion(Library.names(in: folder, ext: $1)) }
    }

    /// The challenge files by name, and the names that couldn't be read at all. Moves files from
    /// the device's folder into iCloud first. Blocks while iCloud downloads: call it off the main
    /// thread.
    static func read() -> (files: [String: Data], unreadable: [String]) {
        #if DEBUG
        if let debugFolder {
            let files = names(in: debugFolder).reduce(into: [String: Data]()) { $0[$1] = try? Data(contentsOf: debugFolder.appending(path: $1)) }
            return (files, [])
        }
        #endif
        let local = localFolder, mirror = mirrorFolder
        var localNames = names(in: local)
        var cloudNames = Set<String>()
        if let cloud = cloudFolder {
            cloudNames = names(in: cloud)
            for name in localNames {
                let source = local.appending(path: name)
                // Already in iCloud, or copied there now: iCloud's copy is the one.
                if cloudNames.contains(name) || (try? Data(contentsOf: source)).map({ (try? Library.coordinatedWrite($0, to: cloud.appending(path: name))) != nil }) == true {
                    try? FileManager.default.removeItem(at: source)
                    cloudNames.insert(name)
                    localNames.remove(name)
                }
            }
        }
        var files = [String: Data](), unreadable = [String]()
        for name in localNames.union(cloudNames).sorted() {
            let data = localNames.contains(name) ? try? Data(contentsOf: local.appending(path: name))
                : cloudFolder.flatMap { Library.readWithin(30, $0.appending(path: name)) }
            if let data {
                try? data.write(to: mirror.appending(path: name), options: .atomic)
                files[name] = data
            } else if let copy = try? Data(contentsOf: mirror.appending(path: name)) {
                files[name] = copy // iCloud didn't deliver it in time: the copy from before
            } else {
                unreadable.append(name)
            }
        }
        for name in names(in: mirror).subtracting(localNames).subtracting(cloudNames) {
            try? FileManager.default.removeItem(at: mirror.appending(path: name))
        }
        return (files, unreadable)
    }

    /// Deletes a challenge's file everywhere (all devices, with iCloud).
    static func remove(_ name: String) {
        try? FileManager.default.removeItem(at: localFolder.appending(path: name))
        try? FileManager.default.removeItem(at: mirrorFolder.appending(path: name))
        if let cloud = cloudFolder { Library.coordinatedRemove(cloud.appending(path: name)) }
    }

    #if DEBUG
    /// Simulator and screenshots: `-ChallengesFolder <repo>/challenges` reads the challenges from
    /// the Mac (read only); Debug builds for the Mac use the repository's folder by default.
    static var debugFolder: URL? {
        if let path = UserDefaults.standard.string(forKey: "ChallengesFolder") { return URL(filePath: path, directoryHint: .isDirectory) }
        #if targetEnvironment(macCatalyst)
        let repo = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "challenges", directoryHint: .isDirectory)
        if FileManager.default.fileExists(atPath: repo.path(percentEncoded: false)) { return repo }
        #endif
        return nil
    }
    #endif
}

/// Removes what the built-in challenges of versions before 1.13 left on the device: the Trappist
/// and boscafé lists (Application Support) and the ferry, Klompenpaden and MTB route asset packs.
/// Once per device.
enum RetiredChallengeData {
    private static let doneKey = "retiredChallengeDataRemoved"

    static func removeOnce() async {
        guard !UserDefaults.standard.bool(forKey: doneKey) else { return }
        for folder in ["Trappist", "Boscafes"] {
            try? FileManager.default.removeItem(at: URL.applicationSupportDirectory.appending(path: folder, directoryHint: .isDirectory))
        }
        for pack in ["ferries", "klompenpaden", "mtbroutes"] {
            try? await AssetPackManager.shared.remove(assetPackWithID: pack) // throws when it isn't there
        }
        UserDefaults.standard.set(true, forKey: doneKey)
    }
}
