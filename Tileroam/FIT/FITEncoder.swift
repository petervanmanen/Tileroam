import Foundation

/// Writes a minimal but complete FIT activity file (file_id, records, lap, session, activity)
/// that Garmin Connect, Strava and other tools can read.
struct FITEncoder {
    struct Sample {
        var date: Date
        var point: GeoPoint
        var altitude: Double?
    }

    var startDate: Date
    /// Seconds.
    var elapsedTime: Double
    /// Seconds.
    var movingTime: Double
    /// Meters.
    var distance: Double
    /// FIT sport enum.
    var sport: UInt8
    var samples: [Sample] = []

    private var body = [UInt8]()

    static func sport(forName name: String) -> UInt8 {
        switch name {
        case "Running": 1
        case "Cycling": 2
        case "Swimming": 5
        case "Walking": 11
        case "Skiing": 13
        case "Rowing": 15
        case "Hiking": 17
        case "E-biking": 21
        case "Inline skating": 30
        default: 0
        }
    }

    init(startDate: Date, elapsedTime: Double, movingTime: Double, distance: Double, sport: UInt8) {
        self.startDate = startDate
        self.elapsedTime = elapsedTime
        self.movingTime = movingTime
        self.distance = distance
        self.sport = sport
    }

    mutating func encode() -> Data {
        body = []
        let start = Self.fitTime(startDate)
        let end = samples.last.map { Self.fitTime($0.date) } ?? start &+ UInt32(max(0, elapsedTime))
        let elapsedMs = UInt32(max(0, elapsedTime) * 1000)
        let timerMs = UInt32(max(0, movingTime > 0 ? movingTime : elapsedTime) * 1000)
        let distanceCm = UInt32(max(0, distance) * 100)
        let sport = self.sport
        let samples = self.samples

        // file_id: type, manufacturer, product, time_created
        define(local: 0, global: 0, fields: [(0, 1, 0x00), (1, 2, 0x84), (2, 2, 0x84), (4, 4, 0x86)])
        data(local: 0) { $0.u8(4); $0.u16(255); $0.u16(0); $0.u32(start) }

        // record: timestamp, position_lat, position_long, altitude
        if !samples.isEmpty {
            define(local: 1, global: 20, fields: [(253, 4, 0x86), (0, 4, 0x85), (1, 4, 0x85), (2, 2, 0x84)])
            for s in samples {
                data(local: 1) { w in
                    w.u32(Self.fitTime(s.date))
                    w.i32(Self.semicircles(s.point.lat))
                    w.i32(Self.semicircles(s.point.lon))
                    if let alt = s.altitude {
                        w.u16(UInt16(clamping: Int(((alt + 500) * 5).rounded())))
                    } else {
                        w.u16(0xFFFF)
                    }
                }
            }
        }

        // lap: timestamp, event, event_type, start_time, total_elapsed_time, total_timer_time, total_distance
        define(local: 2, global: 19, fields: [(253, 4, 0x86), (0, 1, 0x00), (1, 1, 0x00), (2, 4, 0x86),
                                              (7, 4, 0x86), (8, 4, 0x86), (9, 4, 0x86)])
        data(local: 2) { $0.u32(end); $0.u8(9); $0.u8(1); $0.u32(start); $0.u32(elapsedMs); $0.u32(timerMs); $0.u32(distanceCm) }

        // session: + sport, first_lap_index, num_laps
        define(local: 3, global: 18, fields: [(253, 4, 0x86), (0, 1, 0x00), (1, 1, 0x00), (2, 4, 0x86),
                                              (7, 4, 0x86), (8, 4, 0x86), (9, 4, 0x86), (5, 1, 0x00),
                                              (25, 2, 0x84), (26, 2, 0x84)])
        data(local: 3) {
            $0.u32(end); $0.u8(8); $0.u8(1); $0.u32(start); $0.u32(elapsedMs); $0.u32(timerMs); $0.u32(distanceCm)
            $0.u8(sport); $0.u16(0); $0.u16(1)
        }

        // activity: timestamp, total_timer_time, num_sessions, type, event, event_type
        define(local: 4, global: 34, fields: [(253, 4, 0x86), (0, 4, 0x86), (1, 2, 0x84), (2, 1, 0x00),
                                              (3, 1, 0x00), (4, 1, 0x00)])
        data(local: 4) { $0.u32(end); $0.u32(timerMs); $0.u16(1); $0.u8(0); $0.u8(26); $0.u8(1) }

        var header: [UInt8] = [14, 0x20]
        header += Self.le(UInt16(2132))
        header += Self.le(UInt32(body.count))
        header += Array(".FIT".utf8)
        header += Self.le(Self.crc(header))
        let file = header + body
        return Data(file + Self.le(Self.crc(file)))
    }

    // MARK: Writing

    private mutating func define(local: UInt8, global: UInt16, fields: [(UInt8, UInt8, UInt8)]) {
        body.append(0x40 | local)
        body += [0, 0] // reserved, little endian
        body += Self.le(global)
        body.append(UInt8(fields.count))
        for (number, size, type) in fields { body += [number, size, type] }
    }

    private mutating func data(local: UInt8, _ write: (inout Writer) -> Void) {
        var w = Writer()
        write(&w)
        body.append(local)
        body += w.bytes
    }

    struct Writer {
        var bytes = [UInt8]()
        mutating func u8(_ v: UInt8) { bytes.append(v) }
        mutating func u16(_ v: UInt16) { bytes += FITEncoder.le(v) }
        mutating func u32(_ v: UInt32) { bytes += FITEncoder.le(v) }
        mutating func i32(_ v: Int32) { bytes += FITEncoder.le(UInt32(bitPattern: v)) }
    }

    static func le<T: FixedWidthInteger>(_ v: T) -> [UInt8] {
        withUnsafeBytes(of: v.littleEndian) { Array($0) }
    }

    static func fitTime(_ date: Date) -> UInt32 {
        UInt32(clamping: Int64(date.timeIntervalSince1970 - FITDecoder.fitEpochOffset))
    }

    static func semicircles(_ degrees: Double) -> Int32 {
        Int32(clamping: Int64((degrees / 180 * 2_147_483_648).rounded()))
    }

    private static let crcTable: [UInt16] = [
        0x0000, 0xCC01, 0xD801, 0x1400, 0xF001, 0x3C00, 0x2800, 0xE401,
        0xA001, 0x6C00, 0x7800, 0xB401, 0x5000, 0x9C01, 0x8801, 0x4400,
    ]

    static func crc(_ bytes: [UInt8]) -> UInt16 {
        var crc: UInt16 = 0
        for byte in bytes {
            var tmp = crcTable[Int(crc & 0xF)]
            crc = (crc >> 4) & 0x0FFF
            crc = crc ^ tmp ^ crcTable[Int(byte & 0xF)]
            tmp = crcTable[Int(crc & 0xF)]
            crc = (crc >> 4) & 0x0FFF
            crc = crc ^ tmp ^ crcTable[Int((byte >> 4) & 0xF)]
        }
        return crc
    }
}
