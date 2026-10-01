import Foundation

enum ImportEvent: Sendable {
    case started(found: Int, toParse: Int)
    case folderUnreadable(String)
    case progress(done: Int, total: Int)
    case finished(activities: [Activity], failed: [String])
}

/// Scans the folder and parses new/changed .fit files in the background.
enum Importer {
    static func run(folder: URL, existing: [String: Activity],
                    activityID: @escaping @Sendable (String) -> String = { $0 }) -> AsyncStream<ImportEvent> {
        AsyncStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                let didAccess = folder.startAccessingSecurityScopedResource()
                defer { if didAccess { folder.stopAccessingSecurityScopedResource() } }

                do {
                    _ = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                } catch {
                    continuation.yield(.folderUnreadable(error.localizedDescription))
                    continuation.finish()
                    return
                }

                let files = FolderAccess.fitFiles(in: folder)
                var activities = [Activity]()
                var toParse = [FolderAccess.FitFile]()
                for file in files {
                    if let cached = existing[activityID(file.relativePath)], cached.cacheKey == file.cacheKey {
                        activities.append(cached)
                    } else {
                        toParse.append(file)
                    }
                }
                continuation.yield(.started(found: files.count, toParse: toParse.count))

                var failed = [String]()
                var done = 0
                await withTaskGroup(of: (String, Activity?).self) { group in
                    var iterator = toParse.makeIterator()
                    let parallelism = max(2, ProcessInfo.processInfo.activeProcessorCount - 1)
                    for _ in 0..<parallelism {
                        guard let file = iterator.next() else { break }
                        group.addTask { (file.relativePath, parse(file, id: activityID(file.relativePath))) }
                    }
                    for await (path, activity) in group {
                        if let activity { activities.append(activity) } else { failed.append(path) }
                        done += 1
                        continuation.yield(.progress(done: done, total: toParse.count))
                        if Task.isCancelled { break }
                        if let file = iterator.next() {
                            group.addTask { (file.relativePath, parse(file, id: activityID(file.relativePath))) }
                        }
                    }
                }

                activities.sort { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
                continuation.yield(.finished(activities: activities, failed: failed))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func parse(_ file: FolderAccess.FitFile, id: String) -> Activity? {
        guard let data = try? FolderAccess.read(file.url),
              let fit = try? FITDecoder.decode(data) else { return nil }
        return makeActivity(fit, id: id, cacheKey: file.cacheKey)
    }

    static func makeActivity(_ fit: FITActivityData, id: String, cacheKey: String) -> Activity {
        let name = (id as NSString).lastPathComponent.replacingOccurrences(of: ".fit", with: "", options: [.caseInsensitive])
        var activity = makeActivity(points: fit.points, id: id, cacheKey: cacheKey, name: name,
                                    sport: FITDecoder.sportName(fit.sport), startDate: fit.startTime, distance: fit.totalDistance)
        activity.elapsedTime = fit.elapsedTime
        return activity
    }

    /// Derives the simplified track and tiles from full GPS points. Municipalities and postcodes
    /// are added afterwards by `ActivityStore` (they depend on the switched-on countries).
    static func makeActivity(points: [GeoPoint], id: String, cacheKey: String, name: String, sport: String,
                             startDate: Date?, distance: Double?, isSummary: Bool? = nil) -> Activity {
        return Activity(
            id: id,
            cacheKey: cacheKey,
            name: name,
            sport: sport,
            startDate: startDate,
            distance: distance ?? zip(points, points.dropFirst()).reduce(0) { $0 + Geo.distance($1.0, $1.1) },
            trackData: Activity.encodeTrack(Geo.simplify(points, tolerance: 8)),
            tiles14: Array(TileGrid.tiles(for: points, zoom: .explorer)).sorted(),
            tiles17: Array(TileGrid.tiles(for: points, zoom: .squadratinho)).sorted(),
            isSummary: isSummary
        )
    }
}
