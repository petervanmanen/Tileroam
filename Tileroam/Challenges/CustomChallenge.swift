import CryptoKit
import Foundation

/// A challenge the user added as a file: places to visit (`locations`) or routes to ride, run or
/// walk (`routes`). The file is GeoJSON with a `tileroam` block; the format is documented in
/// challenges/README.md and read by `CustomChallenge.parse`. The files live in the Challenges
/// folder (see `ChallengeFiles`).
struct CustomChallenge: Sendable, Identifiable {
    enum Kind: String, Sendable { case locations, routes }

    /// When a route counts as done.
    enum Completion: String, Sendable {
        /// The activities together cover `coverage` of the route (Klompenpaden, MTB routes).
        case cover
        /// One activity goes from one end to the other (ferries).
        case cross
    }

    /// Supported version of the format (`tileroam.format`).
    static let format = 1

    let id: String
    let name: String
    /// Short name for the tab at the top of the map.
    let tab: String
    /// An emoji, drawn on the map for every item that has none of its own.
    let icon: String
    let description: String?
    /// Shown in Settings → Sources & Licenses (Markdown links allowed).
    let attribution: String?
    let link: URL?
    let kind: Kind
    let completion: Completion
    /// Locations: metres between the place and the track.
    let radius: Double
    /// Cover routes: the share of the route that makes it done.
    let coverage: Double
    /// Cover routes: metres between the checkpoints along a route.
    let spacing: Double
    /// Only activities of these sports count (`Activity.sport`); nil: all.
    let sports: Set<String>?
    let items: [ChallengeItem]
    /// The file it was read from, in the Challenges folder.
    let fileName: String
    /// A fingerprint of the file and the matchers' rules: results stored with another key are
    /// computed again (see `ChallengeResults`).
    let key: String

    /// The items on the map can be route planning targets: places only.
    var isPlanningTarget: Bool { kind == .locations }

    func counts(_ activity: Activity) -> Bool {
        sports.map { $0.contains(activity.sport) } ?? true
    }

    func item(_ id: String) -> ChallengeItem? { itemsByID[id] }

    private let itemsByID: [String: ChallengeItem]

    init(id: String, name: String, tab: String? = nil, icon: String? = nil, description: String? = nil,
         attribution: String? = nil, link: URL? = nil, kind: Kind, completion: Completion = .cover,
         radius: Double = 200, coverage: Double = 0.9, spacing: Double = 50, sports: Set<String>? = nil,
         items: [ChallengeItem], fileName: String = "", key: String? = nil) {
        self.id = id
        self.name = name
        self.tab = tab ?? name
        self.icon = icon ?? (kind == .locations ? "📍" : "🛤️")
        self.description = description
        self.attribution = attribution
        self.link = link
        self.kind = kind
        self.completion = completion
        self.radius = radius
        self.coverage = coverage
        self.spacing = spacing
        self.sports = sports
        self.items = items
        self.fileName = fileName
        self.key = key ?? "x\(ChallengeResults.version)-\(id)-\(items.count)"
        itemsByID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }
}

/// A place or route of a challenge.
struct ChallengeItem: Sendable, Identifiable {
    /// How hard a route is, in the usual MTB colours: green, blue, red, black.
    enum Difficulty: String, CaseIterable, Sendable {
        case easy, moderate, hard
        case veryHard = "very-hard"

        var title: String {
            switch self {
            case .easy: String(localized: "Easy", comment: "Route difficulty (green)")
            case .moderate: String(localized: "Moderate", comment: "Route difficulty (blue)")
            case .hard: String(localized: "Hard", comment: "Route difficulty (red)")
            case .veryHard: String(localized: "Very hard", comment: "Route difficulty (black)")
            }
        }
    }

    let id: String
    let name: String
    let subtitle: String?
    /// An emoji instead of the challenge's.
    let icon: String?
    let link: URL?
    let difficulty: Difficulty?
    /// A location; for a route the middle of a crossing, else its start.
    let point: GeoPoint
    /// A route, in one or more pieces (empty for a location).
    let pieces: [[GeoPoint]]
    /// Metres along a route (0 for a location).
    let length: Double

    init(id: String, name: String, subtitle: String? = nil, icon: String? = nil, link: URL? = nil,
         difficulty: Difficulty? = nil, point: GeoPoint) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.icon = icon
        self.link = link
        self.difficulty = difficulty
        self.point = point
        pieces = []
        length = 0
    }

    init(id: String, name: String, subtitle: String? = nil, icon: String? = nil, link: URL? = nil,
         difficulty: Difficulty? = nil, pieces: [[GeoPoint]], crossing: Bool = false) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.icon = icon
        self.link = link
        self.difficulty = difficulty
        self.pieces = pieces
        length = pieces.reduce(0) { $0 + Self.length($1) }
        point = crossing ? Self.middle(pieces.first ?? []) : pieces.first?.first ?? GeoPoint(lat: 0, lon: 0)
    }

    static func length(_ line: [GeoPoint]) -> Double {
        zip(line, line.dropFirst()).reduce(0) { $0 + Geo.distance($1.0, $1.1) }
    }

    /// The point halfway along a line.
    static func middle(_ line: [GeoPoint]) -> GeoPoint {
        guard var previous = line.first else { return GeoPoint(lat: 0, lon: 0) }
        var left = length(line) / 2
        for p in line.dropFirst() {
            let d = Geo.distance(previous, p)
            if d >= left, d > 0 {
                let t = left / d
                return GeoPoint(lat: previous.lat + (p.lat - previous.lat) * t, lon: previous.lon + (p.lon - previous.lon) * t)
            }
            left -= d
            previous = p
        }
        return previous
    }
}

extension CustomChallenge {
    enum ParseError: LocalizedError, Equatable {
        case notJSON
        case notFeatureCollection
        case noHeader
        case unsupportedFormat(Int)
        case missing(String)
        case invalid(String)
        case noItems

        var errorDescription: String? {
            switch self {
            case .notJSON: String(localized: "The file isn't valid JSON.")
            case .notFeatureCollection: String(localized: "The file isn't a GeoJSON FeatureCollection.")
            case .noHeader: String(localized: "The file has no \"tileroam\" block.")
            case .unsupportedFormat(let v): String(localized: "Format \(v) needs a newer version of Tileroam.")
            case .missing(let field): String(localized: "\"\(field)\" is missing.")
            case .invalid(let field): String(localized: "\"\(field)\" isn't valid.")
            case .noItems: String(localized: "The file has no usable places or routes.")
            }
        }
    }

    /// Ids: lower-case letters, digits and hyphens.
    static func isValidID(_ id: String) -> Bool {
        id.wholeMatch(of: /[a-z0-9][a-z0-9-]{0,63}/) != nil
    }

    /// The id for a file without one: its name, in lower case with hyphens.
    static func id(fromFileName name: String) -> String {
        let stem = (name as NSString).deletingPathExtension.replacingOccurrences(of: ".tileroam", with: "")
        let folded = stem.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
        let slug = folded.map { $0.isLetter && $0.isASCII || $0.isNumber ? String($0) : "-" }.joined()
            .split(separator: "-").joined(separator: "-")
        return String((slug.isEmpty ? "challenge" : slug).prefix(64))
    }

    /// Reads a challenge file. Features that can't be used (no name, wrong geometry) are skipped
    /// and counted in `skipped`; the file fails only when its header is wrong or nothing is left.
    static func parse(_ data: Data, fileName: String) throws -> (challenge: CustomChallenge, skipped: Int) {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ParseError.notJSON }
        guard root["type"] as? String == "FeatureCollection", let features = root["features"] as? [Any] else {
            throw ParseError.notFeatureCollection
        }
        guard let header = root["tileroam"] as? [String: Any] else { throw ParseError.noHeader }
        guard let format = (header["format"] as? NSNumber)?.intValue else { throw ParseError.missing("tileroam.format") }
        guard format <= Self.format else { throw ParseError.unsupportedFormat(format) }
        guard let name = text(header["name"]) else { throw ParseError.missing("tileroam.name") }
        guard let kindName = header["kind"] as? String else { throw ParseError.missing("tileroam.kind") }
        guard let kind = Kind(rawValue: kindName) else { throw ParseError.invalid("tileroam.kind") }
        let id = header["id"] == nil ? Self.id(fromFileName: fileName) : header["id"] as? String ?? ""
        guard isValidID(id) else { throw ParseError.invalid("tileroam.id") }
        let completion: Completion
        if let c = header["complete"] {
            guard let s = c as? String, let value = Completion(rawValue: s), kind == .routes else { throw ParseError.invalid("tileroam.complete") }
            completion = value
        } else {
            completion = .cover
        }
        func number(_ key: String, default value: Double, in range: ClosedRange<Double>) throws -> Double {
            guard let raw = header[key] else { return value }
            guard let n = (raw as? NSNumber)?.doubleValue, range.contains(n) else { throw ParseError.invalid("tileroam.\(key)") }
            return n
        }
        let radius = try number("radius", default: 200, in: 10...5_000)
        let coverage = try number("coverage", default: 0.9, in: 0.1...1)
        let spacing = try number("spacing", default: 50, in: 10...1_000)
        var sports: Set<String>?
        if let raw = header["sports"] {
            guard let list = raw as? [String], !list.isEmpty else { throw ParseError.invalid("tileroam.sports") }
            sports = Set(list)
        }
        var icon: String?
        if let raw = header["icon"] {
            guard let s = text(raw), isEmoji(s) else { throw ParseError.invalid("tileroam.icon") }
            icon = s
        }

        var items = [ChallengeItem](), seen = Set<String>(), skipped = 0
        for case let feature as [String: Any] in features {
            guard let item = Self.item(feature, kind: kind, completion: completion), seen.insert(item.id).inserted else {
                skipped += 1
                continue
            }
            items.append(item)
        }
        skipped += features.count - features.compactMap { $0 as? [String: Any] }.count
        guard !items.isEmpty else { throw ParseError.noItems }

        let hash = SHA256.hash(data: data).prefix(6).map { String(format: "%02x", $0) }.joined()
        let challenge = CustomChallenge(
            id: id, name: name, tab: text(header["tab"]), icon: icon, description: text(header["description"]),
            attribution: text(header["attribution"]), link: (header["url"] as? String).flatMap(webURL),
            kind: kind, completion: completion, radius: radius, coverage: coverage, spacing: spacing, sports: sports,
            items: items, fileName: fileName, key: "x\(ChallengeResults.version)-\(hash)")
        return (challenge, skipped)
    }

    private static func item(_ feature: [String: Any], kind: Kind, completion: Completion) -> ChallengeItem? {
        guard feature["type"] as? String == "Feature", let geometry = feature["geometry"] as? [String: Any] else { return nil }
        let properties = feature["properties"] as? [String: Any] ?? [:]
        guard let id = identifier(feature["id"]) ?? identifier(properties["id"]), let name = text(properties["name"]) else { return nil }
        let subtitle = text(properties["subtitle"])
        let icon = text(properties["icon"]).flatMap { isEmoji($0) ? $0 : nil }
        let link = (properties["url"] as? String).flatMap(webURL)
        let difficulty = (properties["difficulty"] as? String).flatMap(ChallengeItem.Difficulty.init(rawValue:))
        let type = geometry["type"] as? String, coordinates = geometry["coordinates"]
        switch kind {
        case .locations:
            guard type == "Point", let p = point(coordinates) else { return nil }
            return ChallengeItem(id: id, name: name, subtitle: subtitle, icon: icon, link: link, difficulty: difficulty, point: p)
        case .routes:
            var pieces: [[GeoPoint]]
            switch type {
            case "LineString": pieces = [line(coordinates)].compactMap { $0 }
            case "MultiLineString": pieces = (coordinates as? [Any] ?? []).compactMap(line)
            default: return nil
            }
            pieces = pieces.filter { $0.count >= 2 }
            // A crossing goes from the first point of its line to the last: one line.
            guard !pieces.isEmpty, completion == .cover || pieces.count == 1 else { return nil }
            return ChallengeItem(id: id, name: name, subtitle: subtitle, icon: icon, link: link, difficulty: difficulty,
                                 pieces: pieces, crossing: completion == .cross)
        }
    }

    /// A GeoJSON position: [longitude, latitude] (an elevation after it is ignored).
    private static func point(_ value: Any?) -> GeoPoint? {
        guard let c = value as? [Any], c.count >= 2, let lon = (c[0] as? NSNumber)?.doubleValue,
              let lat = (c[1] as? NSNumber)?.doubleValue, (-90...90).contains(lat), (-180...180).contains(lon) else { return nil }
        return GeoPoint(lat: lat, lon: lon)
    }

    private static func line(_ value: Any?) -> [GeoPoint]? {
        guard let list = value as? [Any] else { return nil }
        let points = list.compactMap(point)
        return points.count == list.count ? points : nil
    }

    private static func identifier(_ value: Any?) -> String? {
        if let s = value as? String, !s.isEmpty { return s }
        if let n = value as? NSNumber { return n.stringValue }
        return nil
    }

    private static func text(_ value: Any?) -> String? {
        guard let s = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }

    private static func webURL(_ s: String) -> URL? {
        guard let url = URL(string: s), url.scheme == "https" || url.scheme == "http" else { return nil }
        return url
    }

    /// One emoji (a single character that draws as an emoji).
    static func isEmoji(_ s: String) -> Bool {
        guard s.count == 1, let scalar = s.unicodeScalars.first else { return false }
        return scalar.properties.isEmojiPresentation || s.unicodeScalars.count > 1 && scalar.properties.isEmoji
    }
}
