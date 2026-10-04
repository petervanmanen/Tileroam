import Foundation

/// A challenge's list on Cloudflare R2 (`<server>/<remote>/<name>`), kept on the device in a
/// folder: downloaded when the copy is missing or older than `maxAge`, the copy used offline.
/// Used for the Trappist breweries and the Klompenpaden.
enum RemoteList {
    /// How long a downloaded list is used before checking for a new one.
    static let maxAge: TimeInterval = 24 * 3600

    /// The list on the device (empty before the first download).
    static func cached<T: Decodable>(_ type: T.Type, name: String, in folder: URL) -> [T] {
        (try? Data(contentsOf: folder.appending(path: name))).flatMap { try? JSONDecoder().decode([T].self, from: $0) } ?? []
    }

    /// The list, downloaded when needed. Throws when there's no list at all (offline on first use).
    static func load<T: Decodable>(_ type: T.Type, name: String, remote: String, into folder: URL,
                                   from server: URL, session: URLSession, now: Date = .now) async throws -> [T] {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: name)
        let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        var list = cached(T.self, name: name, in: folder)
        guard list.isEmpty || modified.map({ now.timeIntervalSince($0) > maxAge }) ?? true else { return list }
        do {
            let data = try await RemoteFile.get(server.appending(path: "\(remote)/\(name)"), session: session) {
                (try? JSONDecoder().decode([T].self, from: $0)) != nil
            }
            try data.write(to: file, options: .atomic)
            list = try JSONDecoder().decode([T].self, from: data)
        } catch where !list.isEmpty {
            // Offline or a passing problem: keep using the copy on the device.
        }
        return list
    }
}
