import Foundation

/// Saves Strava activities as .fit files in the selected folder (subfolder "Strava").
enum StravaExport {
    static let subfolder = "Strava"

    static func fileName(for activity: Activity) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let date = activity.startDate.map(formatter.string(from:)) ?? "undated"
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>\n\r\t")
        let name = activity.name.components(separatedBy: invalid).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        let id = StravaImport.stravaID(of: activity).map(String.init) ?? "x"
        return "\(date)-\(name.prefix(60))-Strava-\(id).fit"
    }

    static func fitData(for activity: Activity, stream: StravaStream?) -> Data {
        let start = activity.startDate ?? .now
        var encoder = FITEncoder(startDate: start,
                                 elapsedTime: activity.elapsedTime ?? stream?.times.last ?? 0,
                                 movingTime: activity.movingTime ?? 0,
                                 distance: activity.distance,
                                 sport: FITEncoder.sport(forName: activity.sport))
        // Keeps virtual rides recognizable when another device imports the file.
        if activity.isVirtual == true { encoder.subSport = 58 }
        if let stream {
            encoder.samples = stream.points.indices.map { i in
                FITEncoder.Sample(date: start.addingTimeInterval(i < stream.times.count ? stream.times[i] : Double(i)),
                                  point: stream.points[i],
                                  altitude: i < stream.altitudes.count ? stream.altitudes[i] : nil)
            }
        }
        return encoder.encode()
    }

    /// Files this app wrote (HealthFit's own exports end in "-Strava.fit" without an id).
    static func isOwnFile(_ name: String) -> Bool {
        name.range(of: #"-Strava-\d+\.fit$"#, options: .regularExpression) != nil
    }

    /// Moves previously exported files from `oldFolder/Strava` to `newFolder/Strava`.
    /// Returns the number of files moved.
    static func moveExports(from oldFolder: URL, to newFolder: URL, subfolder: String = subfolder,
                            isOwn: (String) -> Bool = isOwnFile) throws -> Int {
        let oldAccess = oldFolder.startAccessingSecurityScopedResource()
        let newAccess = newFolder.startAccessingSecurityScopedResource()
        defer {
            if oldAccess { oldFolder.stopAccessingSecurityScopedResource() }
            if newAccess { newFolder.stopAccessingSecurityScopedResource() }
        }
        let source = oldFolder.appending(path: subfolder, directoryHint: .isDirectory)
        let target = newFolder.appending(path: subfolder, directoryHint: .isDirectory)
        guard source.standardizedFileURL != target.standardizedFileURL,
              let names = try? FileManager.default.contentsOfDirectory(atPath: source.path(percentEncoded: false)) else { return 0 }
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)

        var moved = 0
        for name in names {
            // iCloud placeholders look like ".name.fit.icloud"
            let realName = name.hasPrefix(".") && name.hasSuffix(".icloud") ? String(name.dropFirst().dropLast(7)) : name
            guard isOwn(realName) else { continue }
            let from = source.appending(path: name)
            let to = target.appending(path: realName)
            var coordinationError: NSError?
            var moveError: Error?
            NSFileCoordinator().coordinate(writingItemAt: from, options: .forMoving,
                                           writingItemAt: to, options: .forReplacing, error: &coordinationError) { a, b in
                do {
                    if FileManager.default.fileExists(atPath: b.path(percentEncoded: false)) {
                        try FileManager.default.removeItem(at: a) // already there
                    } else {
                        try FileManager.default.moveItem(at: a, to: b)
                    }
                } catch {
                    moveError = error
                }
            }
            if let error = coordinationError ?? moveError { throw error }
            moved += 1
        }
        // Remove the now empty subfolder we created in the other app's folder.
        if let rest = try? FileManager.default.contentsOfDirectory(atPath: source.path(percentEncoded: false)),
           rest.allSatisfy({ $0.hasPrefix(".") && !$0.hasSuffix(".icloud") }) {
            try? FileManager.default.removeItem(at: source)
        }
        return moved
    }

    /// Names of the files Tileroam saved from Strava in `folder/Strava` (iCloud placeholders included).
    static func ownFiles(in folder: URL) -> [URL] {
        let access = folder.startAccessingSecurityScopedResource()
        defer { if access { folder.stopAccessingSecurityScopedResource() } }
        let dir = folder.appending(path: subfolder, directoryHint: .isDirectory)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path(percentEncoded: false))) ?? []
        return names.filter { name in
            let real = name.hasPrefix(".") && name.hasSuffix(".icloud") ? String(name.dropFirst().dropLast(7)) : name
            return isOwnFile(real)
        }.map { dir.appending(path: $0) }
    }

    /// Deletes the files Tileroam saved from Strava in `folder/Strava` (never other apps' files).
    /// Returns the number of files deleted.
    static func deleteOwnFiles(in folder: URL) -> Int {
        let access = folder.startAccessingSecurityScopedResource()
        defer { if access { folder.stopAccessingSecurityScopedResource() } }
        var deleted = 0
        for url in ownFiles(in: folder) {
            var coordinationError: NSError?
            NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &coordinationError) { url in
                if (try? FileManager.default.removeItem(at: url)) != nil { deleted += 1 }
            }
        }
        return deleted
    }

    /// Writes the file and returns its name.
    static func write(_ activity: Activity, stream: StravaStream?, to folder: URL) throws -> String {
        let name = fileName(for: activity)
        try SaveFolder.write(fitData(for: activity, stream: stream), name: name, subfolder: subfolder, in: folder)
        return name
    }
}
