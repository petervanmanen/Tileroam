import Foundation
import MapKit
import Testing
@testable import Tileroam

struct GeoTests {
    @Test func tileNumbersMatchOSMFormula() {
        // Reference values from the standard slippy-map formula (computed independently).
        #expect(TileGrid.cell(lat: 52.0907, lon: 5.1214, zoom: .explorer)! == (8425, 5405))
        #expect(TileGrid.cell(lat: 52.0907, lon: 5.1214, zoom: .squadratinho)! == (67400, 43241))
        #expect(TileGrid.cell(lat: -33.8568, lon: 151.2153, zoom: .explorer)! == (15073, 9831))
        #expect(TileGrid.cell(lat: 89, lon: 0, zoom: .explorer) == nil)
    }

    @Test func tileSizeAt52Degrees() {
        let nw = TileGrid.corner(x: 8425, y: 5405, zoom: .explorer)
        let ne = TileGrid.corner(x: 8426, y: 5405, zoom: .explorer)
        let sw = TileGrid.corner(x: 8425, y: 5406, zoom: .explorer)
        #expect(abs(Geo.distance(nw, ne) - 1503) < 10)
        #expect(abs(Geo.distance(nw, sw) - 1503) < 15) // approximate distance formula
        // The tile contains the point it was computed from.
        #expect(nw.lat > 52.0907 && sw.lat < 52.0907 && nw.lon < 5.1214 && ne.lon > 5.1214)
    }

    @Test func tileKeyRoundTrip() {
        for (x, y) in [(0, 0), (8425, 5405), (131_071, 131_071)] {
            let c = TileGrid.cell(of: TileGrid.key(x: x, y: y))
            #expect(c.x == x && c.y == y)
        }
    }

    @Test func squareStats() {
        var visited = Set<Int64>()
        for x in 10..<13 { for y in 400..<403 { visited.insert(TileGrid.key(x: x, y: y)) } }
        visited.insert(TileGrid.key(x: 50, y: 450))
        let stats = SquareStats(visited: visited)
        #expect(stats.count == 10)
        #expect(stats.maxSquare == 3)
        #expect(stats.maxSquareOrigin?.x == 10 && stats.maxSquareOrigin?.y == 400)
        #expect(stats.maxCluster == 1)
    }

    @Test func squareStatsSparseFarApart() {
        // Tiles on opposite sides of the world: must not allocate a grid over the bounding box.
        var visited = Set<Int64>()
        for x in 0..<4 { for y in 0..<4 { visited.insert(TileGrid.key(x: x, y: y)) } }
        visited.insert(TileGrid.key(x: 131_000, y: 131_000))
        let stats = SquareStats(visited: visited)
        #expect(stats.maxSquare == 4)
        #expect(stats.maxCluster == 4)
    }

    @Test func densifyAndSimplify() {
        let line = [GeoPoint(lat: 52, lon: 5), GeoPoint(lat: 52.01, lon: 5)] // ~1.1 km
        let dense = Geo.densified(line, spacing: 100)
        #expect(dense.count == 13)
        #expect(Geo.simplify(dense, tolerance: 5).count == 2)
    }

    /// The boundary files from the repository (in the app they come from asset packs).
    static func read(_ country: String, _ kind: AreaKind) throws -> Data {
        let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try Data(contentsOf: root.appending(path: "AssetPacks/Regions/\(country)-\(kind.rawValue).fmr"))
    }

    static let regions = RegionData.load(countries: ["NL", "BE", "DE"], read: read)

    @Test func regionFilesDecode() throws {
        for country in Country.all {
            let municipalities = try RegionFile.load(country: country.code, kind: .municipalities, read: Self.read)
            #expect(!municipalities.isEmpty, "\(country.code) municipalities")
            #expect(municipalities.allSatisfy { $0.country == country.code && !$0.polygons.isEmpty })
            if country.hasPostcodes {
                #expect(try !RegionFile.load(country: country.code, kind: .postcodes, read: Self.read).isEmpty, "\(country.code) postcodes")
            }
        }
    }

    @Test func municipalityLookup() {
        let m = Self.regions.municipalities
        #expect(m.countByCountry()["NL"] == 342)
        #expect(m.area(at: GeoPoint(lat: 52.3731, lon: 4.8926))?.code == "NL:GM0363") // Amsterdam
        #expect(m.area(at: GeoPoint(lat: 52.0907, lon: 5.1214))?.name == "Utrecht")
        #expect(m.area(at: GeoPoint(lat: 50.8466, lon: 4.3528))?.country == "BE") // Brussels
        #expect(m.area(at: GeoPoint(lat: 52.5163, lon: 13.3777))?.name.contains("Berlin") == true)
        #expect(m.area(at: GeoPoint(lat: 48.85, lon: 2.35)) == nil) // France not loaded
    }

    @Test func postcodeLookup() {
        let p = Self.regions.postcodes
        #expect(p.countByCountry()["NL"] == 4071)
        #expect(p.area(at: GeoPoint(lat: 52.0907, lon: 5.1214))?.code == "NL:3512") // Utrecht Dom
        #expect(p.area(at: GeoPoint(lat: 52.3731, lon: 4.8926))?.localCode == "1012") // Amsterdam Dam
        #expect(p.area(at: GeoPoint(lat: 52.5163, lon: 13.3777))?.localCode == "10117") // Brandenburger Tor
    }

    @Test func otherCountries() {
        let r = RegionData.load(countries: ["FR", "ES", "GB", "IE", "CH", "AT", "LU"], read: Self.read)
        #expect(r.municipalities.area(at: GeoPoint(lat: 48.8584, lon: 2.2945))?.name == "Paris")
        #expect(r.municipalities.area(at: GeoPoint(lat: 40.4168, lon: -3.7038))?.name == "Madrid")
        #expect(r.municipalities.area(at: GeoPoint(lat: 53.3498, lon: -6.2603))?.country == "IE")
        #expect(r.municipalities.area(at: GeoPoint(lat: 51.5007, lon: -0.1246))?.name == "Westminster")
        #expect(r.municipalities.area(at: GeoPoint(lat: 47.3769, lon: 8.5417))?.name == "Zürich")
        #expect(r.municipalities.area(at: GeoPoint(lat: 48.2082, lon: 16.3738))?.name == "Wien")
        #expect(r.municipalities.area(at: GeoPoint(lat: 49.6116, lon: 6.1319))?.name == "Luxembourg")
        #expect(r.postcodes.area(at: GeoPoint(lat: 51.5007, lon: -0.1246))?.localCode == "SW1A")
        #expect(r.postcodes.area(at: GeoPoint(lat: 47.3769, lon: 8.5417))?.localCode.hasPrefix("80") == true)
    }

    @Test func westernAndNordicCountries() {
        let r = RegionData.load(countries: ["PT", "IT", "DK", "NO", "SE", "FI", "IS", "LI", "MC", "AD", "SM", "VA"], read: Self.read)
        let m = r.municipalities
        #expect(m.area(at: GeoPoint(lat: 41.8902, lon: 12.4922))?.name == "Roma") // Colosseum
        #expect(m.area(at: GeoPoint(lat: 41.9029, lon: 12.4534))?.country == "VA") // St. Peter's
        #expect(m.area(at: GeoPoint(lat: 38.7139, lon: -9.1394))?.name == "Lisboa")
        #expect(m.area(at: GeoPoint(lat: 55.6761, lon: 12.5683))?.name == "København")
        #expect(m.area(at: GeoPoint(lat: 59.9139, lon: 10.7522))?.name == "Oslo")
        #expect(m.area(at: GeoPoint(lat: 59.3293, lon: 18.0686))?.name == "Stockholm")
        #expect(m.area(at: GeoPoint(lat: 60.1699, lon: 24.9384))?.name == "Helsinki")
        #expect(m.area(at: GeoPoint(lat: 64.1466, lon: -21.9426))?.name == "Reykjavíkurborg")
        #expect(m.area(at: GeoPoint(lat: 47.1410, lon: 9.5209))?.name == "Vaduz")
        #expect(m.area(at: GeoPoint(lat: 43.7384, lon: 7.4246))?.country == "MC")
        #expect(m.area(at: GeoPoint(lat: 42.5063, lon: 1.5218))?.country == "AD")
        #expect(m.area(at: GeoPoint(lat: 43.9356, lon: 12.4473))?.country == "SM")
        #expect(r.postcodes.area(at: GeoPoint(lat: 55.6761, lon: 12.5683))?.localCode.hasPrefix("1") == true)
        #expect(r.postcodes.area(at: GeoPoint(lat: 60.1699, lon: 24.9384))?.localCode == "00100")
    }

    @Test func mapFocusPicksDensestArea() {
        let utrecht = (0..<20).map { GeoPoint(lat: 52.09 + Double($0) * 0.001, lon: 5.12) }
        let paris = (0..<5).map { GeoPoint(lat: 48.85 + Double($0) * 0.001, lon: 2.35) }
        let c = MapFocus.densestCenter(utrecht + paris)!
        #expect(abs(c.lat - 52.0995) < 0.001 && abs(c.lon - 5.12) < 0.001)
        #expect(MapFocus.densestCenter([]) == nil)
        let rect = MapFocus.rect(center: c, aspectRatio: 0.5)
        #expect(abs(rect.height - MKMapSize.world.height / 1024) < 1)
        #expect(abs(rect.width - rect.height / 2) < 1)
    }

    @Test func activityFromTrack() {
        var fit = FITActivityData()
        fit.points = (0..<200).map { GeoPoint(lat: 52.0907 + Double($0) * 0.0001, lon: 5.1214) }
        let a = Importer.makeActivity(fit, id: "rides/ride.fit", cacheKey: "1")
        #expect(a.name == "ride")
        #expect((a.tiles14?.count ?? 0) >= 1)
        #expect((a.tiles17?.count ?? 0) >= 10)
        #expect(a.coordinates.count == 2)
    }
}
