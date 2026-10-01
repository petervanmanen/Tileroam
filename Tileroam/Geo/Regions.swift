import Foundation

enum AreaKind: String, CaseIterable, Sendable {
    case municipalities, postcodes
}

/// Countries with bundled municipality (and postcode) boundaries.
struct Country: Identifiable, Hashable, Sendable {
    let code: String
    /// Mainland bounding box, used to switch countries on automatically.
    let minLat, maxLat, minLon, maxLon: Double
    let hasPostcodes: Bool

    var id: String { code }

    var name: String {
        Locale.current.localizedString(forRegionCode: code) ?? code
    }

    var flag: String {
        code.unicodeScalars.compactMap { UnicodeScalar(127_397 + $0.value) }.map(String.init).joined()
    }

    func contains(_ p: GeoPoint) -> Bool {
        (minLat...maxLat).contains(p.lat) && (minLon...maxLon).contains(p.lon)
    }

    static let all: [Country] = [
        Country(code: "NL", minLat: 50.7, maxLat: 53.7, minLon: 3.3, maxLon: 7.3, hasPostcodes: true),
        Country(code: "BE", minLat: 49.4, maxLat: 51.6, minLon: 2.5, maxLon: 6.5, hasPostcodes: true),
        Country(code: "LU", minLat: 49.4, maxLat: 50.2, minLon: 5.7, maxLon: 6.6, hasPostcodes: false),
        Country(code: "DE", minLat: 47.2, maxLat: 55.1, minLon: 5.8, maxLon: 15.1, hasPostcodes: true),
        Country(code: "FR", minLat: 41.3, maxLat: 51.2, minLon: -5.2, maxLon: 9.6, hasPostcodes: true),
        Country(code: "ES", minLat: 27.6, maxLat: 43.9, minLon: -18.2, maxLon: 4.4, hasPostcodes: true),
        Country(code: "CH", minLat: 45.8, maxLat: 47.9, minLon: 5.9, maxLon: 10.6, hasPostcodes: true),
        Country(code: "AT", minLat: 46.3, maxLat: 49.1, minLon: 9.5, maxLon: 17.2, hasPostcodes: false),
        Country(code: "GB", minLat: 49.8, maxLat: 60.9, minLon: -8.7, maxLon: 1.8, hasPostcodes: true),
        Country(code: "IE", minLat: 51.4, maxLat: 55.5, minLon: -10.7, maxLon: -5.9, hasPostcodes: false),
        Country(code: "PT", minLat: 36.9, maxLat: 42.2, minLon: -9.6, maxLon: -6.1, hasPostcodes: false),
        Country(code: "IT", minLat: 35.4, maxLat: 47.1, minLon: 6.6, maxLon: 18.6, hasPostcodes: false),
        Country(code: "LI", minLat: 47.04, maxLat: 47.28, minLon: 9.47, maxLon: 9.64, hasPostcodes: false),
        Country(code: "MC", minLat: 43.72, maxLat: 43.76, minLon: 7.40, maxLon: 7.44, hasPostcodes: false),
        Country(code: "AD", minLat: 42.42, maxLat: 42.66, minLon: 1.40, maxLon: 1.79, hasPostcodes: false),
        Country(code: "SM", minLat: 43.89, maxLat: 44.0, minLon: 12.40, maxLon: 12.52, hasPostcodes: false),
        Country(code: "VA", minLat: 41.90, maxLat: 41.91, minLon: 12.44, maxLon: 12.46, hasPostcodes: false),
        Country(code: "DK", minLat: 54.5, maxLat: 57.8, minLon: 8.0, maxLon: 15.2, hasPostcodes: true),
        Country(code: "NO", minLat: 57.9, maxLat: 71.3, minLon: 4.5, maxLon: 31.2, hasPostcodes: false),
        Country(code: "SE", minLat: 55.3, maxLat: 69.1, minLon: 10.9, maxLon: 24.2, hasPostcodes: false),
        Country(code: "FI", minLat: 59.7, maxLat: 70.1, minLon: 20.5, maxLon: 31.6, hasPostcodes: true),
        Country(code: "IS", minLat: 63.2, maxLat: 66.6, minLon: -24.6, maxLon: -13.4, hasPostcodes: false),
    ]

    /// Sorted by name in the current language, for lists.
    static var sortedByName: [Country] {
        all.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    static func named(_ code: String) -> Country? {
        all.first { $0.code == code }
    }
}

/// Reads the compact region files made by `Tools/build_regions.py`.
enum RegionFile {
    enum DecodeError: Error { case missing, corrupt }

    static func load(country: String, kind: AreaKind, bundle: Bundle = .main) throws -> [Area] {
        guard let url = bundle.url(forResource: "\(country)-\(kind.rawValue)", withExtension: "fmr") else {
            throw DecodeError.missing
        }
        return try decode(try Data(contentsOf: url))
    }

    static func decode(_ compressed: Data) throws -> [Area] {
        let data = try (compressed as NSData).decompressed(using: .zlib) as Data
        return try data.withUnsafeBytes { raw -> [Area] in
            let b = raw.bindMemory(to: UInt8.self)
            var i = 0
            func byte() throws -> UInt8 {
                guard i < b.count else { throw DecodeError.corrupt }
                defer { i += 1 }
                return b[i]
            }
            func varint() throws -> UInt64 {
                var result: UInt64 = 0, shift: UInt64 = 0
                while true {
                    let x = try byte()
                    result |= UInt64(x & 0x7F) << shift
                    if x & 0x80 == 0 { return result }
                    shift += 7
                }
            }
            func zigzag() throws -> Int64 {
                let n = try varint()
                return Int64(bitPattern: n >> 1) ^ -Int64(bitPattern: n & 1)
            }
            func string(_ length: Int) throws -> String {
                guard i + length <= b.count else { throw DecodeError.corrupt }
                defer { i += length }
                return String(decoding: UnsafeBufferPointer(rebasing: b[i..<(i + length)]), as: UTF8.self)
            }

            guard try string(4) == "FMR1", b.count >= 8 else { throw DecodeError.corrupt }
            let count = Int(UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16 | UInt32(b[i + 3]) << 24)
            i += 4
            var lat: Int64 = 0, lon: Int64 = 0
            var areas = [Area]()
            areas.reserveCapacity(count)
            for _ in 0..<count {
                let code = try string(Int(try byte()))
                let nameLength = Int(try byte()) | Int(try byte()) << 8
                let name = try string(nameLength)
                var minLat = 90.0, maxLat = -90.0, minLon = 180.0, maxLon = -180.0
                var polygons = [Area.Polygon]()
                for _ in 0..<(try varint()) {
                    var rings = [[GeoPoint]]()
                    for _ in 0..<(try varint()) {
                        let n = Int(try varint())
                        var ring = [GeoPoint]()
                        ring.reserveCapacity(n)
                        for _ in 0..<n {
                            lat += try zigzag()
                            lon += try zigzag()
                            let p = GeoPoint(lat: Double(lat) / 1e5, lon: Double(lon) / 1e5)
                            minLat = min(minLat, p.lat); maxLat = max(maxLat, p.lat)
                            minLon = min(minLon, p.lon); maxLon = max(maxLon, p.lon)
                            ring.append(p)
                        }
                        rings.append(ring)
                    }
                    polygons.append(Area.Polygon(rings: rings))
                }
                guard minLat <= maxLat else { continue } // no points (degenerate source geometry)
                areas.append(Area(code: code, name: name, polygons: polygons,
                                  minLat: minLat, maxLat: maxLat, minLon: minLon, maxLon: maxLon))
            }
            return areas
        }
    }
}

/// Municipalities and postcodes of the switched-on countries.
struct RegionData: Sendable {
    let countries: [String]
    let municipalities: AreaSet
    let postcodes: AreaSet

    /// Changes when the set of countries (or the data) changes; activities store it to know
    /// whether their visited municipalities/postcodes need recomputing.
    var key: String { "v1:" + countries.joined(separator: ",") }

    static func load(countries: Set<String>) -> RegionData {
        let codes = Country.all.map(\.code).filter(countries.contains)
        var municipalities = [Area]()
        var postcodes = [Area]()
        for code in codes {
            municipalities += (try? RegionFile.load(country: code, kind: .municipalities)) ?? []
            if Country.named(code)?.hasPostcodes == true {
                postcodes += (try? RegionFile.load(country: code, kind: .postcodes)) ?? []
            }
        }
        return RegionData(countries: codes, municipalities: AreaSet(areas: municipalities), postcodes: AreaSet(areas: postcodes))
    }

    func areas(_ kind: AreaKind) -> AreaSet {
        kind == .municipalities ? municipalities : postcodes
    }
}
