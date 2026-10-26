import Foundation
import Testing
@testable import Tileroam

/// Dives: a dive computer has no GPS under water, so its .fit records have no positions; the
/// entry and exit points are in the laps (and the session). They must still count.
struct DiveTests {
    /// A minimal .fit file: a lap with start and end positions and a session with sport 53
    /// (diving), no records with positions.
    private func diveFile(entry: GeoPoint, exit: GeoPoint, sessionStart: GeoPoint? = nil, withLap: Bool = true) -> Data {
        var body = [UInt8]()
        func le16(_ v: UInt16) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8)] }
        func le32(_ v: Int32) -> [UInt8] { withUnsafeBytes(of: v.littleEndian, Array.init) }
        func semicircles(_ degrees: Double) -> Int32 { Int32(degrees / 180 * 2_147_483_648) }
        if withLap {
            // Definition, local 0: lap (19), fields 3–6 as sint32.
            body += [0x40, 0, 0] + le16(19) + [4, 3, 4, 0x85, 4, 4, 0x85, 5, 4, 0x85, 6, 4, 0x85]
            body += [0x00] + le32(semicircles(entry.lat)) + le32(semicircles(entry.lon))
                + le32(semicircles(exit.lat)) + le32(semicircles(exit.lon))
        }
        // Definition, local 1: session (18), sport (5) and start_position (3, 4).
        body += [0x41, 0, 0] + le16(18) + [3, 5, 1, 0x00, 3, 4, 0x85, 4, 4, 0x85]
        let start = sessionStart ?? entry
        body += [0x01, 53] + le32(semicircles(start.lat)) + le32(semicircles(start.lon))
        let size = UInt32(body.count)
        let header: [UInt8] = [14, 0x20] + le16(2134)
            + [UInt8(size & 0xFF), UInt8((size >> 8) & 0xFF), UInt8((size >> 16) & 0xFF), UInt8(size >> 24)]
            + Array(".FIT".utf8) + [0, 0]
        return Data(header + body + [0, 0])
    }

    @Test func diveLandsWhereItWasEntered() throws {
        let entry = GeoPoint(lat: 51.6512, lon: 3.9120), exit = GeoPoint(lat: 51.6520, lon: 3.9135) // Zeeland
        let fit = try FITDecoder.decode(diveFile(entry: entry, exit: exit))
        #expect(FITDecoder.sportName(fit.sport) == "Diving")
        #expect(fit.points.count == 2)
        #expect(abs(fit.points[0].lat - entry.lat) < 1e-6 && abs(fit.points[1].lon - exit.lon) < 1e-6)
        let activity = Importer.makeActivity(fit, id: "dive", cacheKey: "")
        #expect(activity.isOnMap)
        #expect(activity.sport == "Diving")
        #expect(!TileGrid.tiles(for: [entry, exit], zoom: .explorer).isEmpty)
    }

    @Test func sessionStartWithoutLaps() throws {
        let p = GeoPoint(lat: 52.0, lon: 5.0)
        let fit = try FITDecoder.decode(diveFile(entry: p, exit: p, withLap: false))
        #expect(fit.points.count == 1)
    }
}
