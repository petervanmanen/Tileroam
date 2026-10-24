import Compression
import Foundation
import Testing
@testable import Tileroam

/// ZIP archives as Garmin delivers them, built here (CRCs are left at zero: the reader doesn't
/// check them).
enum ZipFixture {
    static func archive(_ entries: [(name: String, data: Data, deflate: Bool)]) -> Data {
        var out = Data(), central = Data()
        func le16(_ v: Int) -> Data { Data([UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF)]) }
        func le32(_ v: Int) -> Data { le16(v & 0xFFFF) + le16(v >> 16 & 0xFFFF) }
        for entry in entries {
            let stored = entry.deflate ? deflate(entry.data) : entry.data
            let name = Data(entry.name.utf8), offset = out.count, method = entry.deflate ? 8 : 0
            let sizes: [Data] = [le32(0), le32(stored.count), le32(entry.data.count), le16(name.count), le16(0)]
            let local: [Data] = [le32(0x0403_4B50), le16(20), le16(0), le16(method), le32(0)] + sizes + [name, stored]
            let header: [Data] = [le32(0x0201_4B50), le16(20), le16(20), le16(0), le16(method), le32(0)] + sizes
                + [le16(0), le16(0), le16(0), le32(0), le32(offset), name]
            local.forEach { out.append($0) }
            header.forEach { central.append($0) }
        }
        let start = out.count
        out.append(central)
        let end: [Data] = [le32(0x0605_4B50), le16(0), le16(0), le16(entries.count), le16(entries.count),
                           le32(central.count), le32(start), le16(0)]
        end.forEach { out.append($0) }
        return out
    }

    static func deflate(_ data: Data) -> Data {
        var output = Data(count: data.count + 1024)
        let written = output.withUnsafeMutableBytes { out in
            data.withUnsafeBytes { input in
                compression_encode_buffer(out.bindMemory(to: UInt8.self).baseAddress!, data.count + 1024,
                                          input.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        return output.prefix(written)
    }

    /// Bytes that look like a .fit file (".FIT" at offset 8), with some content.
    static func fit(_ marker: String) -> Data {
        Data([14, 0x10, 0, 0, 0, 0, 0, 0]) + Data(".FIT".utf8) + Data([0, 0]) + Data(String(repeating: marker, count: 50).utf8)
    }
}

struct ZipTests {
    @Test func storedAndDeflatedEntries() throws {
        let fit = ZipFixture.fit("ride")
        let stored = ZipFixture.archive([("readme.txt", Data("hi".utf8), false), ("123_ACTIVITY.fit", fit, false)])
        #expect(try Zip.firstFile(withExtension: "fit", in: stored) == fit)
        let deflated = ZipFixture.archive([("123_ACTIVITY.FIT", fit, true)])
        #expect(try Zip.firstFile(withExtension: "fit", in: deflated) == fit)
    }

    @Test func noFitFileOrNoZip() throws {
        #expect(try Zip.firstFile(withExtension: "fit", in: ZipFixture.archive([("track.gpx", Data("<gpx/>".utf8), true)])) == nil)
        #expect(throws: Zip.ZipError.notAZip) { try Zip.firstFile(withExtension: "fit", in: Data("not a zip at all, but long enough".utf8)) }
    }

    @Test func garminDownloads() {
        let fit = ZipFixture.fit("x")
        #expect(GarminSync.fitFile(in: ZipFixture.archive([("1.fit", fit, true)])) == fit)
        #expect(GarminSync.fitFile(in: fit) == fit) // a bare .fit file
        #expect(GarminSync.fitFile(in: ZipFixture.archive([("1.tcx", Data("<tcx/>".utf8), false)])) == nil)
    }
}

/// A fake Garmin server: answers by path, records the requests.
final class GarminStub: URLProtocol, @unchecked Sendable {
    struct Reply: Sendable { var status = 200; var body = Data() }
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> Reply)?
    nonisolated(unsafe) static var requests: [URLRequest] = []
    static let lock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let reply: Reply = Self.lock.withLock {
            Self.requests.append(request)
            return Self.handler?(request) ?? Reply(status: 404)
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}

    static var session: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GarminStub.self]
        return URLSession(configuration: configuration)
    }
}

@MainActor
@Suite(.serialized)
struct GarminSyncTests {
    /// A JWT whose payload says it expires in a day.
    nonisolated static let token: String = {
        let payload = Data(#"{"exp":\#(Int(Date.now.timeIntervalSince1970) + 86_400)}"#.utf8).base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
        return "eyJhbGciOiJub25lIn0.\(payload).sig"
    }()

    final class Saved: @unchecked Sendable {
        var files: [String: Data] = [:]
        var deleted: [String] = []
        var key: String?
        let lock = NSLock()
    }

    /// A GarminSync against the stub, with files, key and state kept here.
    func makeSync(_ saved: Saved, key: String? = nil) -> GarminSync {
        let defaults = UserDefaults(suiteName: "GarminSyncTests")!
        defaults.removePersistentDomain(forName: "GarminSyncTests")
        saved.key = key
        var environment = GarminSync.Environment()
        environment.session = GarminStub.session
        environment.base = URL(string: "https://garmin.test")!
        environment.save = { data, name in saved.lock.withLock { saved.files[name] = data }; return name }
        environment.delete = { names in saved.lock.withLock { saved.deleted += names } }
        environment.loadKey = { saved.key }
        environment.storeKey = { saved.key = $0 }
        environment.defaults = defaults
        return GarminSync(environment: environment)
    }

    /// Serves the token for "good-key", `list` as the activity list (one page) and a ZIP per activity:
    /// a .fit file, or a GPX file for IDs in `gpx`.
    func serve(_ list: [(Int64, String)], gpx: Set<Int64> = []) {
        let json = try! JSONSerialization.data(withJSONObject: list.map {
            ["activityId": $0.0, "activityName": $0.1, "startTimeLocal": "2026-10-20 07:12:33"] as [String: Any]
        })
        GarminStub.lock.withLock {
            GarminStub.requests = []
            GarminStub.handler = { request in
                let path = request.url!.path
                if path.hasSuffix("/personal-api-key/token") {
                    return request.value(forHTTPHeaderField: "Authorization") == "ApiKey good-key"
                        ? .init(body: Data(Self.token.utf8)) : .init(status: 401)
                }
                guard request.value(forHTTPHeaderField: "Authorization") == "Bearer \(Self.token)" else { return .init(status: 401) }
                if path.hasSuffix("/activities/search/activities") {
                    let start = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "start" }?.value
                    return .init(body: start == "0" ? json : Data("[]".utf8))
                }
                if let id = Int64(path.split(separator: "/").last ?? ""), path.contains("/download-service/files/activity/") {
                    let entry = gpx.contains(id) ? ("\(id).gpx", Data("<gpx/>".utf8), true) : ("\(id)_ACTIVITY.fit", ZipFixture.fit("\(id)"), true)
                    return .init(body: ZipFixture.archive([entry]))
                }
                return .init(status: 404)
            }
        }
    }

    var downloads: Int {
        GarminStub.lock.withLock { GarminStub.requests.count { $0.url!.path.contains("/download-service/") } }
    }

    @Test func connectDownloadsTheHistoryThenOnlyNewActivities() async {
        let saved = Saved()
        serve([(2, "Evening Walk"), (1, "Morning Ride")], gpx: [2])
        let sync = makeSync(saved)
        #expect(!sync.isConnected)
        #expect(await sync.connect(key: " good-key\n"))
        #expect(sync.isConnected && saved.key == "good-key")
        while sync.isSyncing { try? await Task.sleep(for: .milliseconds(20)) }

        // The ride has a .fit file; the walk (uploaded as GPX) is skipped, but remembered.
        #expect(saved.files.keys.sorted() == ["2026-10-20 Morning Ride Garmin 1.fit"])
        #expect(sync.downloadedCount == 1 && sync.error == nil && downloads == 2)

        // A new activity on top: only that one is downloaded.
        serve([(3, "Run"), (2, "Evening Walk"), (1, "Morning Ride")], gpx: [2])
        await sync.run()
        #expect(downloads == 1 && sync.downloadedCount == 2)
        #expect(saved.files["2026-10-20 Run Garmin 3.fit"] == ZipFixture.fit("3"))

        // Disconnecting can delete what was downloaded (not the skipped GPX one).
        await sync.disconnect(deleteFiles: true)
        #expect(!sync.isConnected && saved.key == nil && sync.downloadedCount == 0)
        #expect(saved.deleted.sorted() == ["2026-10-20 Morning Ride Garmin 1.fit", "2026-10-20 Run Garmin 3.fit"])
    }

    @Test func aWrongKeyIsRefused() async {
        let saved = Saved()
        serve([])
        let sync = makeSync(saved)
        #expect(!(await sync.connect(key: "wrong")))
        #expect(!sync.isConnected && saved.key == nil)
        #expect(sync.error == GarminError.invalidKey.localizedDescription)
    }

    @Test func tokenExpiryComesFromTheJWT() {
        let payload = Data(#"{"exp":1793000000}"#.utf8).base64EncodedString().replacingOccurrences(of: "=", with: "")
        #expect(GarminClient.expiry(ofJWT: "eyJhbGciOiJub25lIn0.\(payload).sig") == Date(timeIntervalSince1970: 1_793_000_000))
        #expect(GarminClient.expiry(ofJWT: Self.token).map { $0 > .now } == true)
        #expect(GarminClient.expiry(ofJWT: "not-a-jwt") == nil)
    }

    @Test func fileNames() {
        #expect(GarminSync.fileName(GarminActivity(activityId: 7, activityName: "Lunch Ride", startTimeLocal: "2026-10-20 12:00:00"))
                == "2026-10-20 Lunch Ride Garmin 7.fit")
        #expect(GarminSync.fileName(GarminActivity(activityId: 8, activityName: nil, startTimeLocal: nil)) == "Garmin 8.fit")
    }
}
