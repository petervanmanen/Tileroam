import Foundation

enum AreaKind: String, CaseIterable, Sendable {
    case municipalities, postcodes
}

/// Countries with municipality (and postcode) boundaries.
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

    /// The countries with municipality and postcode boundaries: those route planning covers
    /// (`RoutingData.countries`). Tiles, routes and statistics work everywhere. The data of more
    /// countries can be built with Tools/build_regions.py (see docs/ROUTING.md, Adding countries).
    static let all: [Country] = [
        Country(code: "NL", minLat: 50.7, maxLat: 53.7, minLon: 3.3, maxLon: 7.3, hasPostcodes: true),
        Country(code: "BE", minLat: 49.4, maxLat: 51.6, minLon: 2.5, maxLon: 6.5, hasPostcodes: true),
        Country(code: "LU", minLat: 49.4, maxLat: 50.2, minLon: 5.7, maxLon: 6.6, hasPostcodes: false),
        Country(code: "DE", minLat: 47.2, maxLat: 55.1, minLon: 5.8, maxLon: 15.1, hasPostcodes: true),
        Country(code: "FR", minLat: 41.3, maxLat: 51.2, minLon: -5.2, maxLon: 9.6, hasPostcodes: true),
        Country(code: "CH", minLat: 45.8, maxLat: 47.9, minLon: 5.9, maxLon: 10.6, hasPostcodes: true),
        Country(code: "AT", minLat: 46.3, maxLat: 49.1, minLon: 9.5, maxLon: 17.2, hasPostcodes: false),
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

    /// Reads a country's file; by default from its downloaded asset pack (see `RegionAssets`).
    static func load(country: String, kind: AreaKind,
                     read: (String, AreaKind) throws -> Data = RegionAssets.data) throws -> [Area] {
        try decode(try read(country, kind))
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

/// Municipalities and postcodes of the visited countries.
struct RegionData: Sendable {
    let countries: [String]
    let municipalities: AreaSet
    let postcodes: AreaSet

    /// Changes when the set of countries (or the data) changes; activities store it to know
    /// whether their visited municipalities/postcodes need recomputing.
    var key: String { "v1:" + countries.joined(separator: ",") }

    static func load(countries: Set<String>,
                     read: (String, AreaKind) throws -> Data = RegionAssets.data) -> RegionData {
        let codes = Country.all.map(\.code).filter(countries.contains)
        var municipalities = [Area]()
        var postcodes = [Area]()
        for code in codes {
            municipalities += (try? RegionFile.load(country: code, kind: .municipalities, read: read)) ?? []
            if Country.named(code)?.hasPostcodes == true {
                postcodes += (try? RegionFile.load(country: code, kind: .postcodes, read: read)) ?? []
            }
        }
        return RegionData(countries: codes, municipalities: AreaSet(areas: municipalities), postcodes: AreaSet(areas: postcodes))
    }

    func areas(_ kind: AreaKind) -> AreaSet {
        kind == .municipalities ? municipalities : postcodes
    }
}
