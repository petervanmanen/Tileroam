import Foundation
import Testing
@testable import Tileroam

struct StravaTests {
    @Test func decodesGooglePolyline() {
        let points = StravaImport.decodePolyline("_p~iF~ps|U_ulLnnqC_mqNvxq`@")
        #expect(points.count == 3)
        #expect(points[0] == GeoPoint(lat: 38.5, lon: -120.2))
        #expect(points[1] == GeoPoint(lat: 40.7, lon: -120.95))
        #expect(points[2] == GeoPoint(lat: 43.252, lon: -126.453))
    }

    @Test func decodesActivityList() throws {
        let json = """
        [{"id": 123, "name": "Morning Ride", "sport_type": "GravelRide", "type": "Ride",
          "start_date": "2023-08-10T08:59:56Z", "distance": 77019.0, "elapsed_time": 11000, "moving_time": 10000,
          "trainer": false, "map": {"id": "a123", "summary_polyline": "_p~iF~ps|U_ulLnnqC"}}]
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        let summaries = try decoder.decode([StravaSummary].self, from: Data(json.utf8))
        let a = StravaImport.activity(from: summaries[0])
        #expect(a.id == "strava:123")
        #expect(StravaImport.stravaID(of: a) == 123)
        #expect(a.sport == "Cycling")
        #expect(a.isSummary == true)
        #expect(a.elapsedTime == 11000)
        #expect(a.startDate == Date(timeIntervalSince1970: 1_691_657_996))
    }

    @Test func mergePrefersBestCopy() {
        func activity(_ id: String, _ t: TimeInterval, track: Bool, summary: Bool? = nil) -> Activity {
            Activity(id: id, cacheKey: "", name: id, sport: "Cycling", startDate: Date(timeIntervalSince1970: t),
                     distance: 0, trackData: track ? Data([1, 2, 3, 4, 5, 6, 7, 8]) : Data(),
                     isSummary: summary)
        }
        let merged = ActivityMerge.merge([
            activity("healthfit.fit", 1000, track: false),
            activity("strava:1", 1030, track: true, summary: true),
            activity("garmin.fit", 1010, track: true),
            activity("other.fit", 5000, track: false),
        ])
        #expect(merged.map(\.id) == ["garmin.fit", "other.fit"])
    }

    @Test func fitEncoderRoundTrip() throws {
        let start = Date(timeIntervalSince1970: 1_691_657_996)
        var encoder = FITEncoder(startDate: start, elapsedTime: 600, movingTime: 550, distance: 1234.5, sport: 2)
        encoder.samples = (0..<50).map {
            FITEncoder.Sample(date: start.addingTimeInterval(Double($0)),
                              point: GeoPoint(lat: 52.09 + Double($0) * 0.0001, lon: 5.12), altitude: 3)
        }
        let data = encoder.encode()
        let bytes = [UInt8](data)
        #expect(FITEncoder.crc(Array(bytes[0..<12])) == UInt16(bytes[12]) | UInt16(bytes[13]) << 8)
        #expect(FITEncoder.crc(bytes) == 0) // CRC over file including trailing CRC is zero

        let fit = try FITDecoder.decode(data)
        #expect(fit.points.count == 50)
        #expect(abs(fit.points[49].lat - (52.09 + 49 * 0.0001)) < 1e-6)
        #expect(fit.sport == 2)
        #expect(fit.totalDistance == 1234.5)
        #expect(fit.startTime == start)
        #expect(!fit.isVirtual)

        encoder.subSport = 58
        #expect(try FITDecoder.decode(encoder.encode()).isVirtual)
    }

    @Test func exportFileName() {
        var a = Activity(id: "strava:42", cacheKey: "", name: "Rondje / Utrecht: 50km", sport: "Cycling",
                         startDate: Date(timeIntervalSince1970: 1_691_657_996), distance: 0, trackData: Data())
        a.isSummary = false
        let name = StravaExport.fileName(for: a)
        #expect(name.hasSuffix("-Rondje   Utrecht  50km-Strava-42.fit"))
        #expect(!name.contains("/"))
    }

    @Test func rateLimitHeaders() {
        let now = Date(timeIntervalSince1970: 1_700_000_200) // 100 s after a 15-minute boundary
        #expect(StravaClient.pauseDate(headers: ["X-ReadRateLimit-Limit": "100,1000", "X-ReadRateLimit-Usage": "10,100"],
                                       status: 200, now: now) == nil)
        let quarter = StravaClient.pauseDate(headers: ["X-ReadRateLimit-Limit": "100,1000", "X-ReadRateLimit-Usage": "99,500"],
                                             status: 200, now: now)
        #expect(quarter == Date(timeIntervalSince1970: 1_700_000_100 + 900 + 30))
        let daily = StravaClient.pauseDate(headers: ["x-ratelimit-limit": "200,2000", "x-ratelimit-usage": "5,1999"],
                                           status: 200, now: now)
        #expect(daily.map { $0.timeIntervalSince(now) > 3600 } == true)
        #expect(StravaClient.pauseDate(headers: [:], status: 429, now: now) != nil)
    }
}

struct StravaExportMoveTests {
    @Test func movesOnlyOwnFiles() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let old = root.appending(path: "HealthFit"), new = root.appending(path: "Tileroam")
        let oldStrava = old.appending(path: "Strava")
        try FileManager.default.createDirectory(at: oldStrava, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: new, withIntermediateDirectories: true)
        try Data([1]).write(to: oldStrava.appending(path: "2023-08-10-105956-Rit-Strava-123.fit"))
        try Data([2]).write(to: oldStrava.appending(path: "2023-08-10-105956-Outdoor Cycling-Strava.fit"))
        try Data([3]).write(to: old.appending(path: "2023-08-11-Outdoor Cycling-Strava-9.fit"))

        #expect(try StravaExport.moveExports(from: old, to: new) == 1)
        #expect(FileManager.default.fileExists(atPath: new.appending(path: "Strava/2023-08-10-105956-Rit-Strava-123.fit").path))
        #expect(FileManager.default.fileExists(atPath: oldStrava.appending(path: "2023-08-10-105956-Outdoor Cycling-Strava.fit").path))
        #expect(FileManager.default.fileExists(atPath: old.appending(path: "2023-08-11-Outdoor Cycling-Strava-9.fit").path))
        #expect(!StravaExport.isOwnFile("2018-10-27-125008-Outdoor Running-Strava.fit"))
    }
}

struct ImportFolderTests {
    @Test func iCloudLocations() {
        let root = "/private/var/mobile/Library/Mobile Documents"
        #expect(FolderAccess.displayLocation(URL(filePath: "\(root)/com~apple~CloudDocs/Sport/FIT"))
                == "iCloud Drive › Sport › FIT")
        #expect(FolderAccess.displayLocation(URL(filePath: "\(root)/iCloud~nl~petervanmanen~Tileroam/Documents/Strava"))
                == "iCloud Drive › Tileroam › Strava")
        #expect(FolderAccess.ImportFolder.iCloudDrive.isBuiltIn)
    }

    @Test func activityIDsPerFolder() {
        let legacy = FolderAccess.ImportFolder(id: FolderAccess.ImportFolder.legacyID, name: "HealthFit", bookmark: Data())
        let garmin = FolderAccess.ImportFolder(id: "A1B2", name: "Garmin", bookmark: Data())
        // The first folder keeps plain paths, so caches from the single-folder version stay valid.
        #expect(legacy.activityID(for: "2023/ride.fit") == "2023/ride.fit")
        #expect(garmin.activityID(for: "2023/ride.fit") == "A1B2|2023/ride.fit")
        #expect(legacy.owns("2023/ride.fit") && !legacy.owns("A1B2|2023/ride.fit"))
        #expect(garmin.owns("A1B2|2023/ride.fit") && !garmin.owns("2023/ride.fit"))
    }
}

struct StravaLoginTests {
    @Test func authorizeURLsCarryStateAndRedirect() throws {
        let config = StravaConfig(clientID: "12345", tokenServiceURL: URL(string: "https://example.workers.dev/token")!)
        let app = try #require(URLComponents(url: config.appAuthorizeURL(state: "abc"), resolvingAgainstBaseURL: false))
        #expect(app.scheme == "strava" && app.host == "oauth" && app.path == "/mobile/authorize")
        let items = Dictionary(uniqueKeysWithValues: (app.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(items["client_id"] == "12345")
        #expect(items["redirect_uri"] == "tileroam://localhost")
        #expect(items["state"] == "abc")
        #expect(items["scope"] == "read,activity:read_all")
        let web = config.webAuthorizeURL(state: "abc")
        #expect(web.absoluteString.hasPrefix("https://www.strava.com/oauth/mobile/authorize?"))
    }

    @Test func callbackWithWrongStateIsRejected() async {
        let config = StravaConfig(clientID: "12345", tokenServiceURL: URL(string: "https://example.invalid/token")!)
        let client = StravaClient(config: config)
        _ = await client.beginLogin()
        await #expect(throws: StravaError.self) {
            try await client.completeLogin(callback: URL(string: "tileroam://localhost?state=forged&code=abcdef0123&scope=read,activity:read_all")!)
        }
    }
}
