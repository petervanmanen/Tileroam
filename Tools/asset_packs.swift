// Compares Tileroam's asset packs in App Store Connect with what the app needs, and lists which
// ones are unused (to archive) and which are missing (to upload). Run it with
// Tools/clean_asset_packs.sh, which also explains the settings.
//
// With ARCHIVE="<prefix> …" it also archives the unused packs whose IDs start with one of those
// prefixes (PATCH /v1/backgroundAssets/{id}, archived: true), after asking for confirmation.
// Archiving removes all versions of a pack, for every app version, including TestFlight builds.
import CryptoKit
import Foundation

let env = ProcessInfo.processInfo.environment
func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(2)
}
func required(_ name: String) -> String {
    guard let v = env[name], !v.isEmpty else { fail("Set \(name)") }
    return v
}
let root = URL(filePath: required("TILEROAM_ROOT"), directoryHint: .isDirectory)

// MARK: What the app needs

/// Boundary packs: one per country in Country.all (Tileroam/Geo/Regions.swift).
func neededBoundaryPacks() -> Set<String> {
    let source = (try? String(contentsOf: root.appending(path: "Tileroam/Geo/Regions.swift"), encoding: .utf8)) ?? ""
    let pattern = try! Regex(#"Country\(code: "([A-Z]{2})""#)
    let codes = source.matches(of: pattern).compactMap { $0.output[1].substring.map(String.init) }
    return Set(codes.map { "regions-\($0)" })
}

/// Routing packs: the base and area packs of every bundled routing index.
func neededRoutingPacks() -> Set<String> {
    struct Index: Decodable { struct Area: Decodable { let pack: String }; let base: String; let areas: [Area] }
    let resources = root.appending(path: "Tileroam/Resources")
    let files = (try? FileManager.default.contentsOfDirectory(atPath: resources.path(percentEncoded: false))) ?? []
    var packs = Set<String>()
    for file in files where file.hasPrefix("routing-") && file.hasSuffix(".json") {
        guard let data = try? Data(contentsOf: resources.appending(path: file)),
              let index = try? JSONDecoder().decode(Index.self, from: data) else { continue }
        packs.insert(index.base)
        packs.formUnion(index.areas.map(\.pack))
    }
    return packs
}

// MARK: App Store Connect

func base64URL(_ data: Data) -> String {
    data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

/// A short-lived token for the App Store Connect API (ES256 JWT).
func token() throws -> String {
    let keyID = required("ASC_KEY_ID"), issuer = required("ASC_ISSUER_ID")
    var keyPEM = env["ASC_KEY_P8"] ?? ""
    if keyPEM.isEmpty {
        let path = URL.homeDirectory.appending(path: ".appstoreconnect/private_keys/AuthKey_\(keyID).p8")
        guard let text = try? String(contentsOf: path, encoding: .utf8) else { fail("No API key at \(path.path())") }
        keyPEM = text
    }
    let header = try JSONSerialization.data(withJSONObject: ["alg": "ES256", "kid": keyID, "typ": "JWT"])
    let now = Int(Date.now.timeIntervalSince1970)
    let payload = try JSONSerialization.data(withJSONObject: ["iss": issuer, "iat": now, "exp": now + 1200,
                                                              "aud": "appstoreconnect-v1"])
    let input = base64URL(header) + "." + base64URL(payload)
    let key = try P256.Signing.PrivateKey(pemRepresentation: keyPEM)
    let signature = try key.signature(for: Data(input.utf8)).rawRepresentation
    return input + "." + base64URL(signature)
}

/// App Store Connect can be slow and flaky when archiving (a request took over a minute; others
/// answered 500): a long timeout, and up to four tries, with growing pauses, when the connection
/// times out or drops or the server answers with a 5xx error.
func send(_ request: URLRequest, tries: Int = 4) async throws -> (Data, Int) {
    var request = request
    request.timeoutInterval = 300
    var attempt = 0
    while true {
        attempt += 1
        let pause = Duration.seconds(15 * attempt)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (500...599).contains(status), attempt < tries {
                FileHandle.standardError.write(Data("  App Store Connect answered \(status); trying again in \(pause)…\n".utf8))
                try await Task.sleep(for: pause)
                continue
            }
            return (data, status)
        } catch let error as URLError where attempt < tries && [.timedOut, .networkConnectionLost].contains(error.code) {
            FileHandle.standardError.write(Data("  \(error.localizedDescription) Trying again in \(pause)…\n".utf8))
            try await Task.sleep(for: pause)
        }
    }
}

/// Whether App Store Connect now has the pack archived (an archive that answered with an error
/// may have gone through anyway).
func isArchived(_ resourceID: String, auth: String) async -> Bool {
    var request = URLRequest(url: URL(string: "https://api.appstoreconnect.apple.com/v1/backgroundAssets/\(resourceID)")!)
    request.setValue(auth, forHTTPHeaderField: "Authorization")
    guard let (data, status) = try? await send(request, tries: 2), status == 200,
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let attributes = (json["data"] as? [String: Any])?["attributes"] as? [String: Any] else { return false }
    return attributes["archived"] as? Bool ?? false
}

struct Pack {
    /// App Store Connect's resource ID (for PATCH).
    let resourceID: String
    let id: String
    let archived: Bool
    let bytes: Int64
}

func listPacks() async throws -> [Pack] {
    let auth = "Bearer \(try token())"
    let appID = required("ASC_APP_ID")
    var next: URL? = URL(string: "https://api.appstoreconnect.apple.com/v1/apps/\(appID)/backgroundAssets?limit=200")
    var packs = [Pack]()
    while let url = next {
        var request = URLRequest(url: url)
        request.setValue(auth, forHTTPHeaderField: "Authorization")
        let (data, status) = try await send(request)
        guard status == 200 else {
            fail("App Store Connect answered \(status): \(String(decoding: data, as: UTF8.self).prefix(500))")
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        for item in json["data"] as? [[String: Any]] ?? [] {
            let a = item["attributes"] as? [String: Any] ?? [:]
            packs.append(Pack(resourceID: item["id"] as? String ?? "",
                              id: a["assetPackIdentifier"] as? String ?? "?",
                              archived: a["archived"] as? Bool ?? false,
                              bytes: (a["usedBytes"] as? NSNumber)?.int64Value ?? 0))
        }
        next = ((json["links"] as? [String: Any])?["next"] as? String).flatMap(URL.init(string:))
    }
    return packs
}

// MARK: Report

let needed = neededBoundaryPacks().union(neededRoutingPacks())
if env["OFFLINE"] == "1" {
    // Only what the app needs, without contacting App Store Connect.
    print("The app needs \(needed.count) asset packs:")
    for id in needed.sorted() { print("    \(id)") }
    exit(0)
}
let packs = try await listPacks()
let active = packs.filter { !$0.archived }
if env["LIST"] == "1" {
    // Only the IDs of the active packs, one per line (for Tools/upload_asset_packs.sh --resume).
    for id in active.map(\.id).sorted() { print(id) }
    exit(0)
}
let unused = active.filter { !needed.contains($0.id) }.sorted { $0.id < $1.id }
let present = Set(active.map(\.id))
let missing = needed.subtracting(present).sorted()
let archived = packs.filter(\.archived).count
func mb(_ b: Int64) -> String { String(format: "%.1f MB", Double(b) / 1_000_000) }

print("Asset packs in App Store Connect: \(packs.count) (\(archived) archived)")
print("The app needs \(needed.count): \(neededBoundaryPacks().count) boundary, \(neededRoutingPacks().count) routing.\n")
if missing.isEmpty {
    print("✓ Every needed pack is in App Store Connect.")
} else {
    print("✗ Needed but missing (\(missing.count)); upload them with Tools/upload_asset_packs.sh:")
    for id in missing { print("    \(id)") }
}
if unused.isEmpty {
    print("✓ No unused packs.")
} else {
    print("\nUnused (\(unused.count), \(mb(unused.reduce(0) { $0 + $1.bytes })) together):")
    for p in unused { print("    \(p.id)  \(mb(p.bytes))") }
}

// MARK: Archiving

let prefixes = (env["ARCHIVE"] ?? "").split(separator: " ").map(String.init)
if !prefixes.isEmpty {
    let toArchive = unused.filter { p in prefixes.contains { p.id.hasPrefix($0) } }
    guard !toArchive.isEmpty else {
        print("\nNothing to archive: no unused pack starts with \(prefixes.joined(separator: " or ")).")
        exit(missing.isEmpty ? 0 : 1)
    }
    print("""

    Archive these \(toArchive.count) packs? Archiving removes all their versions from App Store Connect, \
    for every app version, including TestFlight builds. Only archive packs that no app version in \
    TestFlight or on the App Store still uses.
    """)
    for p in toArchive { print("    \(p.id)") }
    print("\nType \"archive\" to continue: ", terminator: "")
    guard readLine()?.trimmingCharacters(in: .whitespaces) == "archive" else {
        print("Nothing archived.")
        exit(1)
    }
    var failed = [String]()
    for (n, p) in toArchive.enumerated() {
        let auth = "Bearer \(try token())" // fresh for every pack: a slow run can outlast a token
        var request = URLRequest(url: URL(string: "https://api.appstoreconnect.apple.com/v1/backgroundAssets/\(p.resourceID)")!)
        request.httpMethod = "PATCH"
        request.setValue(auth, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "data": ["type": "backgroundAssets", "id": p.resourceID, "attributes": ["archived": true]],
        ])
        let progress = "[\(n + 1)/\(toArchive.count)]"
        var problem: String?
        do {
            let (data, status) = try await send(request)
            if status != 200 {
                problem = "App Store Connect answered \(status): " + String(decoding: data, as: UTF8.self)
                    .replacingOccurrences(of: "\n", with: " ").prefix(200)
            }
        } catch {
            problem = error.localizedDescription
        }
        if problem == nil {
            print("\(progress) Archived \(p.id)")
        } else if await isArchived(p.resourceID, auth: auth) {
            print("\(progress) Archived \(p.id) (after an error)")
        } else {
            failed.append(p.id)
            print("\(progress) Not archived: \(p.id). \(problem!)")
        }
    }
    if !failed.isEmpty {
        print("\n\(failed.count) not archived. Run the same command again later for those; App Store Connect's archiving is sometimes unavailable.")
    }
    exit(failed.isEmpty ? 0 : 1)
} else if !unused.isEmpty {
    print("""

    To archive some of them, name their prefix, for example:
        ARCHIVE="regions-" Tools/clean_asset_packs.sh
    Archiving removes all versions of a pack, for every app version at once, so only archive packs
    that no app version in TestFlight or on the App Store still uses.
    """)
}
exit(missing.isEmpty ? 0 : 1)
