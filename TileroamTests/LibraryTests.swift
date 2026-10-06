import Foundation
import Synchronization
import Testing
@testable import Tileroam

struct LibraryNameTests {
    @Test func namesFilesByContent() {
        let a = Data([1, 2, 3]), b = Data([4, 5, 6])
        // Strava files Tileroam saved keep their name: one per Strava activity.
        #expect(Library.libraryName(original: "2023-08-10-105956-Rit-Strava-123.fit", data: a) == "2023-08-10-105956-Rit-Strava-123.fit")
        #expect(!StravaExport.isOwnFile("2018-10-27-125008-Outdoor Running-Strava.fit")) // HealthFit's own export
        // The same file imported twice gets the same name; another file with that name doesn't.
        let first = Library.libraryName(original: "Morning Ride.fit", data: a)
        #expect(first == Library.libraryName(original: "Morning Ride.fit", data: a))
        #expect(first != Library.libraryName(original: "Morning Ride.fit", data: b))
        #expect(first.hasPrefix("Morning Ride-") && first.hasSuffix(".fit"))
        // A library file brought back in keeps its name.
        #expect(Library.libraryName(original: first, data: a) == first)
    }

    @Test func prefersTheOriginalRecording() {
        func activity(_ name: String, power: Double? = nil) -> Activity {
            var a = Activity(id: "lib|" + name, cacheKey: "", name: name, sport: "Cycling", startDate: .now, distance: 40_000,
                             trackData: Activity.encodeTrack([GeoPoint(lat: 52, lon: 5), GeoPoint(lat: 52.1, lon: 5)]))
            a.averagePower = power
            return a
        }
        let strava = activity("2023-08-10-105956-Rit-Strava-123.fit")
        let watch = activity("Ride-1a2b3c4d.fit")
        let withPower = activity("Ride-5e6f7a8b.fit", power: 210)
        #expect(ActivityMerge.preferredFile([strava, watch]).id == watch.id)
        #expect(ActivityMerge.preferredFile([watch, withPower, strava]).id == withPower.id)
    }
}

struct DeletionTests {
    private func stores() -> (UserDefaults, UserDefaults) {
        (UserDefaults(suiteName: "deletions-local-\(UUID())")!, UserDefaults(suiteName: "deletions-cloud-\(UUID())")!)
    }

    @Test func sharedWithOtherDevices() {
        let (phone, cloud) = stores()
        let (iPad, _) = stores()
        Deletions.add(names: ["a.fit", "b.fit"], local: phone, cloud: cloud)
        // Another device sees them through iCloud, and keeps them locally too.
        #expect(Deletions.names(local: iPad, cloud: cloud) == ["a.fit", "b.fit"])
        #expect(Set((iPad.dictionary(forKey: "deletedActivityFiles") ?? [:]).keys) == ["a.fit", "b.fit"])
        // Importing a file again undoes its deletion everywhere, also on the phone that still
        // remembers it as deleted.
        Deletions.forget(name: "a.fit", local: iPad, cloud: cloud, now: .now.addingTimeInterval(1))
        #expect(Deletions.names(local: phone, cloud: cloud) == ["b.fit"])
        // Deleting it again later wins over that.
        Deletions.add(names: ["a.fit"], local: phone, cloud: cloud, now: .now.addingTimeInterval(2))
        #expect(Deletions.names(local: iPad, cloud: cloud) == ["a.fit", "b.fit"])
    }

    @Test func stravaActivities() {
        let (local, cloud) = stores()
        Deletions.add(stravaIDs: [42, 7], local: local, cloud: cloud)
        Deletions.add(stravaIDs: [42], local: local, cloud: cloud)
        #expect(Deletions.stravaIDs(local: local, cloud: cloud) == [42, 7])
    }

    @Test func worksWithoutICloud() {
        let (local, _) = stores()
        let (_, emptyCloud) = stores()
        Deletions.add(names: ["c.fit"], local: local, cloud: emptyCloud)
        #expect(Deletions.names(local: local, cloud: UserDefaults(suiteName: "deletions-none-\(UUID())")!) == ["c.fit"])
    }
}

/// The iCloud mirror, between two temporary folders standing in for this device and iCloud.
struct LibraryMirrorTests {
    private func folders() throws -> (URL, URL) {
        let root = FileManager.default.temporaryDirectory.appending(path: "mirror-\(UUID())", directoryHint: .isDirectory)
        let local = root.appending(path: "local", directoryHint: .isDirectory), cloud = root.appending(path: "cloud", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cloud, withIntermediateDirectories: true)
        return (local, cloud)
    }

    @Test func copiesWhatTheOtherSideMisses() throws {
        let (local, cloud) = try folders()
        try Data([1]).write(to: local.appending(path: "a.fit"))
        try Data([2]).write(to: cloud.appending(path: "b.fit"))
        try Data([3]).write(to: cloud.appending(path: "gone.fit"))
        // Down: b arrives, the deleted one doesn't.
        #expect(Library.copyMissing(from: cloud, to: local, ext: "fit", skipping: ["gone.fit"], coordinated: false) == 1)
        // Up: a goes to iCloud.
        #expect(Library.copyMissing(from: local, to: cloud, ext: "fit", skipping: [], coordinated: true) == 1)
        #expect(Library.names(in: local, ext: "fit") == ["a.fit", "b.fit"])
        #expect(Library.names(in: cloud, ext: "fit") == ["a.fit", "b.fit", "gone.fit"])
        #expect(try Data(contentsOf: local.appending(path: "b.fit")) == Data([2]))
    }

    @Test func manyFilesInParallel() throws {
        let (local, cloud) = try folders()
        for i in 0..<300 { try Data("ride \(i)".utf8).write(to: cloud.appending(path: "r\(i).fit")) }
        let seen = Mutex([Int]())
        let copied = Library.copyMissing(from: cloud, to: local, ext: "fit", skipping: ["r7.fit"], coordinated: false) { done, total in
            #expect(total == 299)
            seen.withLock { $0.append(done) }
        }
        #expect(copied == 299)
        #expect(Library.names(in: local, ext: "fit").count == 299)
        #expect(try Data(contentsOf: local.appending(path: "r42.fit")) == Data("ride 42".utf8))
        // Progress counts up to the total, once per file.
        #expect(seen.withLock { $0.sorted() } == Array(1...299))
    }

    @Test func readsWithinTheTimeLimit() throws {
        let (local, _) = try folders()
        let file = local.appending(path: "a.fit")
        try Data([7, 8]).write(to: file)
        #expect(Library.readWithin(5, file) == Data([7, 8]))
        #expect(Library.readWithin(1, local.appending(path: "missing.fit")) == nil) // gives up after the limit
    }

    @Test func deletionsReachBothSides() throws {
        let (local, cloud) = try folders()
        for folder in [local, cloud] { try Data([1]).write(to: folder.appending(path: "x.fit")) }
        try Data([2]).write(to: local.appending(path: "keep.fit"))
        Library.applyDeletions(["x.fit"], local: local, cloud: cloud)
        #expect(Library.names(in: local, ext: "fit") == ["keep.fit"])
        #expect(Library.names(in: cloud, ext: "fit").isEmpty)
    }

    @Test func seesICloudPlaceholders() throws {
        let (_, cloud) = try folders()
        try Data().write(to: cloud.appending(path: ".Evening Ride-1a2b3c4d.fit.icloud")) // not downloaded yet
        try Data().write(to: cloud.appending(path: ".DS_Store"))
        #expect(Library.names(in: cloud, ext: "fit") == ["Evening Ride-1a2b3c4d.fit"])
    }
}

@Suite(.serialized)
struct LibraryImportTests {
    /// A folder with .fit files the way a user or an earlier version had them.
    private func folder(_ files: [String: Data]) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "import-\(UUID())", directoryHint: .isDirectory)
        for (path, data) in files {
            let url = root.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }
        return root
    }

    private func cleanUp(_ names: [String]) {
        for name in names { try? FileManager.default.removeItem(at: Library.activitiesFolder.appending(path: name)) }
    }

    @Test func importsFilesAndFoldersOnce() throws {
        let marker = UUID().uuidString
        let source = try folder(["2024/ride \(marker).fit": Data(marker.utf8), "notes.txt": Data([0])])
        let result = Library.importOnce([source])
        defer { cleanUp(result.added) }
        #expect(result.added.count == 1 && result.failed.isEmpty)
        #expect(result.added[0].hasPrefix("ride \(marker)-"))
        // The source isn't touched or watched: deleting it leaves the library copy.
        try FileManager.default.removeItem(at: source)
        #expect(FileManager.default.fileExists(atPath: Library.activitiesFolder.appending(path: result.added[0]).path(percentEncoded: false)))
    }
}
