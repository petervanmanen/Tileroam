import Foundation

/// The subset of a FIT activity file this app cares about.
struct FITActivityData: Sendable {
    var points: [GeoPoint] = []
    var sport: UInt8?
    var startTime: Date?
    /// Meters.
    var totalDistance: Double?
    /// Seconds.
    var elapsedTime: Double?
    /// Seconds of timer time (moving, without pauses).
    var movingTime: Double?
    /// Watts, averaged over the timer time of all sessions with power.
    var averagePower: Double? { powerTime > 0 ? powerTotal / powerTime : nil }
    /// Sum of average power × timer time, and that timer time, over sessions with power.
    var powerTotal = 0.0
    var powerTime = 0.0
    /// FIT sub_sport (e.g. 6 indoor cycling, 58 virtual activity).
    var subSport: UInt8?
    /// FIT manufacturer from file_id (e.g. 260 Zwift).
    var manufacturer: UInt16?

    /// Indoor or virtual (Zwift, Rouvy, …): GPS positions, if any, are not real places.
    var isVirtual: Bool {
        if let subSport, FITDecoder.virtualSubSports.contains(subSport) { return true }
        if let manufacturer, FITDecoder.virtualManufacturers.contains(manufacturer) { return true }
        return false
    }
}

enum FITError: Error, Equatable {
    case invalidHeader
    case missingDefinition(Int)
}

/// Minimal decoder for Garmin FIT files.
///
/// Handles normal and compressed-timestamp record headers, both endiannesses,
/// developer fields (skipped) and chained FIT files. Truncated files return
/// whatever was decoded before the truncation.
enum FITDecoder {
    private static let semicircleToDegrees = 180.0 / 2_147_483_648.0
    /// Seconds between the Unix epoch and the FIT epoch (1989-12-31T00:00:00Z).
    static let fitEpochOffset: TimeInterval = 631_065_600

    private struct FieldDef {
        let number: UInt8
        let size: Int
    }

    private struct MessageDef {
        let globalNumber: UInt16
        let bigEndian: Bool
        let fields: [FieldDef]
        let size: Int
    }

    static func decode(_ data: Data) throws -> FITActivityData {
        let bytes = [UInt8](data)
        var result = FITActivityData()
        var fileStart = 0
        var decodedAny = false

        while fileStart + 12 <= bytes.count {
            let headerSize = Int(bytes[fileStart])
            guard headerSize >= 12, fileStart + headerSize <= bytes.count,
                  bytes[fileStart + 8] == 0x2E, bytes[fileStart + 9] == 0x46,
                  bytes[fileStart + 10] == 0x49, bytes[fileStart + 11] == 0x54
            else {
                if decodedAny { break }
                throw FITError.invalidHeader
            }
            let dataSize = Int(readUInt(bytes, fileStart + 4, 4, bigEndian: false))
            let start = fileStart + headerSize
            let end = min(start + dataSize, bytes.count)
            try decodeRecords(bytes, from: start, to: end, into: &result)
            decodedAny = true
            fileStart = start + dataSize + 2 // skip file CRC
        }
        return result
    }

    private static func decodeRecords(_ b: [UInt8], from start: Int, to end: Int, into result: inout FITActivityData) throws {
        var defs = [MessageDef?](repeating: nil, count: 16)
        var i = start

        while i < end {
            let header = b[i]
            i += 1

            if header & 0x80 != 0 {
                // Compressed timestamp header: always a data message.
                let local = Int((header >> 5) & 0x03)
                guard let def = defs[local] else { throw FITError.missingDefinition(local) }
                guard i + def.size <= end else { return }
                handle(def, b, i, &result)
                i += def.size
            } else if header & 0x40 != 0 {
                // Definition message.
                let local = Int(header & 0x0F)
                let hasDeveloperData = header & 0x20 != 0
                guard i + 5 <= end else { return }
                let bigEndian = b[i + 1] == 1
                let global = UInt16(readUInt(b, i + 2, 2, bigEndian: bigEndian))
                let fieldCount = Int(b[i + 4])
                i += 5
                guard i + fieldCount * 3 <= end else { return }
                var fields = [FieldDef]()
                var size = 0
                for f in 0..<fieldCount {
                    let fieldSize = Int(b[i + f * 3 + 1])
                    fields.append(FieldDef(number: b[i + f * 3], size: fieldSize))
                    size += fieldSize
                }
                i += fieldCount * 3
                if hasDeveloperData {
                    guard i < end else { return }
                    let devCount = Int(b[i])
                    i += 1
                    guard i + devCount * 3 <= end else { return }
                    for f in 0..<devCount { size += Int(b[i + f * 3 + 1]) }
                    i += devCount * 3
                }
                defs[local] = MessageDef(globalNumber: global, bigEndian: bigEndian, fields: fields, size: size)
            } else {
                let local = Int(header & 0x0F)
                guard let def = defs[local] else { throw FITError.missingDefinition(local) }
                guard i + def.size <= end else { return }
                handle(def, b, i, &result)
                i += def.size
            }
        }
    }

    private static func handle(_ def: MessageDef, _ b: [UInt8], _ offset: Int, _ result: inout FITActivityData) {
        switch def.globalNumber {
        case 20: // record
            var lat: Int32?
            var lon: Int32?
            forEachField(def, b, offset) { number, value in
                switch number {
                case 0: lat = Int32(truncatingIfNeeded: value)
                case 1: lon = Int32(truncatingIfNeeded: value)
                default: break
                }
            }
            guard let lat, let lon, lat != Int32.max, lon != Int32.max, lat != 0 || lon != 0 else { return }
            result.points.append(GeoPoint(lat: Double(lat) * semicircleToDegrees, lon: Double(lon) * semicircleToDegrees))
        case 0: // file_id
            forEachField(def, b, offset) { number, value in
                if number == 1, value != 0xFFFF { result.manufacturer = result.manufacturer ?? UInt16(truncatingIfNeeded: value) }
            }
        case 12: // sport
            forEachField(def, b, offset) { number, value in
                if number == 1, value != 0xFF { result.subSport = result.subSport ?? UInt8(truncatingIfNeeded: value) }
            }
        case 18: // session
            var timer: Double?
            var power: Double?
            forEachField(def, b, offset) { number, value in
                switch number {
                case 8 where value != 0xFFFF_FFFF:
                    timer = Double(value) / 1000
                    result.movingTime = (result.movingTime ?? 0) + Double(value) / 1000
                case 20 where value != 0xFFFF && value > 0:
                    power = Double(value)
                case 6 where value != 0xFF:
                    result.subSport = result.subSport ?? UInt8(truncatingIfNeeded: value)
                case 5 where value != 0xFF:
                    result.sport = result.sport ?? UInt8(truncatingIfNeeded: value)
                case 2 where value != 0xFFFF_FFFF:
                    result.startTime = result.startTime ?? Date(timeIntervalSince1970: Double(value) + fitEpochOffset)
                case 9 where value != 0xFFFF_FFFF:
                    result.totalDistance = (result.totalDistance ?? 0) + Double(value) / 100
                case 7 where value != 0xFFFF_FFFF:
                    result.elapsedTime = (result.elapsedTime ?? 0) + Double(value) / 1000
                default: break
                }
            }
            if let power, let timer, timer > 0 {
                result.powerTotal += power * timer
                result.powerTime += timer
            }
        default:
            break
        }
    }

    /// Calls `body` for each field of up to 8 bytes; larger fields (strings, arrays) are skipped.
    private static func forEachField(_ def: MessageDef, _ b: [UInt8], _ offset: Int, _ body: (UInt8, UInt64) -> Void) {
        var o = offset
        for field in def.fields {
            if field.size == 1 || field.size == 2 || field.size == 4 || field.size == 8 {
                body(field.number, readUInt(b, o, field.size, bigEndian: def.bigEndian))
            }
            o += field.size
        }
    }

    private static func readUInt(_ b: [UInt8], _ offset: Int, _ size: Int, bigEndian: Bool) -> UInt64 {
        var value: UInt64 = 0
        for k in 0..<size {
            let byte = UInt64(b[offset + (bigEndian ? k : size - 1 - k)])
            value = value << 8 | byte
        }
        return value
    }

    /// sub_sport values for indoor and virtual activities: treadmill (1), indoor cycling (6),
    /// indoor rowing (14) and virtual activity (58, used by Zwift, Rouvy, MyWhoosh and others).
    static let virtualSubSports: Set<UInt8> = [1, 6, 14, 58]
    /// Manufacturer ids of virtual platforms that don't always set sub_sport: Zwift (260).
    static let virtualManufacturers: Set<UInt16> = [260]

    static func sportName(_ sport: UInt8?) -> String {
        switch sport {
        case 1: "Running"
        case 2: "Cycling"
        case 5: "Swimming"
        case 11: "Walking"
        case 17: "Hiking"
        case 4: "Fitness"
        case 13: "Skiing"
        case 15: "Rowing"
        case 30: "Inline skating"
        case 21: "E-biking"
        default: "Activity"
        }
    }
}
