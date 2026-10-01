import Foundation
import Testing
@testable import Tileroam

struct FITDecoderTests {
    @Test(arguments: [false, true])
    func decodesRecordsAndSession(bigEndian: Bool) throws {
        var e = FITTestEncoder(bigEndian: bigEndian)
        e.defineRecord()
        e.record(timestamp: 1_000_000_000, lat: 52.0907, lon: 5.1214)
        e.record(timestamp: 1_000_000_001, lat: 52.0917, lon: 5.1224)
        e.session(sport: 2, startTime: 1_000_000_000, distanceMeters: 1234.5)

        let fit = try FITDecoder.decode(e.data)
        #expect(fit.points.count == 2)
        #expect(abs(fit.points[0].lat - 52.0907) < 1e-6)
        #expect(abs(fit.points[1].lon - 5.1224) < 1e-6)
        #expect(fit.sport == 2)
        #expect(fit.totalDistance == 1234.5)
        #expect(fit.startTime == Date(timeIntervalSince1970: 1_000_000_000 + FITDecoder.fitEpochOffset))
    }

    @Test func rejectsNonFITData() {
        #expect(throws: FITError.invalidHeader) { try FITDecoder.decode(Data("hello world, not a fit".utf8)) }
    }

    @Test func toleratesTruncation() throws {
        var e = FITTestEncoder()
        e.defineRecord()
        e.record(timestamp: 1, lat: 52, lon: 5)
        e.record(timestamp: 2, lat: 52.001, lon: 5)
        let data = e.data.dropLast(8)
        let fit = try FITDecoder.decode(Data(data))
        #expect(fit.points.count == 1)
    }
}
