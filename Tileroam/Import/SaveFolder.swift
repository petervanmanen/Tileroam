import Foundation

/// Writes files into the app's own save folder (e.g. iCloud Drive › Tileroam).
enum SaveFolder {
    /// Writes `data` to `folder/subfolder/name` with file coordination (iCloud-safe).
    static func write(_ data: Data, name: String, subfolder: String, in folder: URL) throws {
        let didAccess = folder.startAccessingSecurityScopedResource()
        defer { if didAccess { folder.stopAccessingSecurityScopedResource() } }

        let directory = folder.appending(path: subfolder, directoryHint: .isDirectory)
        let file = directory.appending(path: name)
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: file, options: .forReplacing, error: &coordinationError) { url in
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
            } catch {
                writeError = error
            }
        }
        if let error = coordinationError ?? writeError { throw error }
    }
}
