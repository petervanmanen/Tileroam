import Foundation
@testable import Tileroam

/// Builds small FIT files for tests (record + session messages).
struct FITTestEncoder {
    var bigEndian = false
    private var body = [UInt8]()

    private mutating func append(_ value: UInt64, size: Int) {
        for k in 0..<size {
            let shift = bigEndian ? (size - 1 - k) * 8 : k * 8
            body.append(UInt8((value >> UInt64(shift)) & 0xFF))
        }
    }

    mutating func defineRecord(local: UInt8 = 0) {
        body.append(0x40 | local)
        body.append(0)
        body.append(bigEndian ? 1 : 0)
        append(20, size: 2)
        body += [3, 253, 4, 0x86, 0, 4, 0x85, 1, 4, 0x85]
    }

    mutating func record(local: UInt8 = 0, timestamp: UInt32, lat: Double, lon: Double) {
        body.append(local)
        append(UInt64(timestamp), size: 4)
        append(UInt64(UInt32(bitPattern: Int32(lat / 180 * 2_147_483_648))), size: 4)
        append(UInt64(UInt32(bitPattern: Int32(lon / 180 * 2_147_483_648))), size: 4)
    }

    mutating func session(local: UInt8 = 1, sport: UInt8, startTime: UInt32, distanceMeters: Double) {
        body.append(0x40 | local)
        body.append(0)
        body.append(bigEndian ? 1 : 0)
        append(18, size: 2)
        body += [3, 2, 4, 0x86, 9, 4, 0x86, 5, 1, 0x00]
        body.append(local)
        append(UInt64(startTime), size: 4)
        append(UInt64(distanceMeters * 100), size: 4)
        body.append(sport)
    }

    var data: Data {
        var header: [UInt8] = [14, 0x20, 0x08, 0x08]
        let size = UInt32(body.count)
        header += [UInt8(size & 0xFF), UInt8(size >> 8 & 0xFF), UInt8(size >> 16 & 0xFF), UInt8(size >> 24)]
        header += Array(".FIT".utf8) + [0, 0]
        return Data(header + body + [0, 0])
    }
}
