import Foundation
import Testing
@testable import Tileroam

struct ActivitiesTests {
    /// A FIT file with session messages only: elapsed (7), timer (8) and total distance (9) as
    /// uint32, average power (20) as uint16 (0xFFFF: no power).
    private func fit(sessions: [(elapsed: UInt32, timer: UInt32, power: UInt16, distance: UInt32)]) -> Data {
        var body: [UInt8] = [0x40, 0, 0, 18, 0, 4, 7, 4, 0x86, 8, 4, 0x86, 20, 2, 0x84, 9, 4, 0x86]
        func u32(_ v: UInt32) -> [UInt8] { withUnsafeBytes(of: v.littleEndian, Array.init) }
        for s in sessions {
            body += [0x00] + u32(s.elapsed) + u32(s.timer) + withUnsafeBytes(of: s.power.littleEndian, Array.init) + u32(s.distance)
        }
        var header: [UInt8] = [12, 0x10, 0, 0] + u32(UInt32(body.count))
        header += Array(".FIT".utf8)
        return Data(header + body + [0, 0])
    }

    @Test func readsMovingTimeAndPowerFromFIT() throws {
        // A 1 h session at 200 W and a 30 min session at 260 W: 220 W over the timer time.
        let two = try FITDecoder.decode(fit(sessions: [(4_000_000, 3_600_000, 200, 3_000_000), (2_000_000, 1_800_000, 260, 1_500_000)]))
        #expect(two.elapsedTime == 6000)
        #expect(two.movingTime == 5400)
        #expect(two.averagePower == 220)
        #expect(two.totalDistance == 45_000)
        // Without a power meter: no power.
        let none = try FITDecoder.decode(fit(sessions: [(4_000_000, 3_600_000, 0xFFFF, 3_000_000)]))
        #expect(none.averagePower == nil)
        #expect(none.movingTime == 3600)
    }

    @Test func durationAndSpeed() {
        var a = Activity(id: "a", cacheKey: "", name: "Ride", sport: "Cycling", startDate: .now, distance: 36_000, trackData: Data())
        #expect(a.duration == nil && a.averageSpeed == nil)
        a.elapsedTime = 5400
        #expect(a.duration == 5400)
        a.movingTime = 3600 // moving time wins: 36 km in 1 h is 10 m/s
        #expect(a.duration == 3600 && a.averageSpeed == 10)
    }

    @Test func mergeKeepsPowerFromAnotherCopy() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var strava = Activity(id: "strava:1", cacheKey: "", name: "Ride", sport: "Cycling", startDate: start,
                              distance: 40_000, trackData: Activity.encodeTrack([GeoPoint(lat: 52, lon: 5), GeoPoint(lat: 52.1, lon: 5)]))
        strava.elapsedTime = 3600
        var watch = Activity(id: "ride.fit", cacheKey: "", name: "Ride", sport: "Cycling", startDate: start.addingTimeInterval(20),
                             distance: 39_000, trackData: Data())
        watch.elapsedTime = 3580
        watch.averagePower = 210
        let merged = ActivityMerge.merge([strava, watch])
        #expect(merged.count == 1)
        #expect(merged[0].id == "strava:1") // the best GPS
        #expect(merged[0].averagePower == 210) // power from the watch
    }

    @Test func formatsDetails() {
        var a = Activity(id: "a", cacheKey: "", name: "Ride", sport: "Cycling", startDate: .now, distance: 42_300, trackData: Data())
        a.movingTime = 5025 // 1:23:45
        let speed = ActivityFormat.details(a)
        #expect(speed.contains("1:23:45") && speed.contains("42") && speed.contains("30")) // 30.3 km/h
        a.averagePower = 215
        let power = ActivityFormat.details(a)
        #expect(power.contains("215") && !power.contains("30"))
        #expect(ActivityFormat.duration(2530) == "42:10")
    }

    @MainActor
    @Test func newestFirst() throws {
        let old = Activity(id: "old", cacheKey: "", name: "Old", sport: "Cycling", startDate: Date(timeIntervalSince1970: 1_600_000_000), distance: 1, trackData: Data())
        let new = Activity(id: "new", cacheKey: "", name: "New", sport: "Cycling", startDate: Date(timeIntervalSince1970: 1_700_000_000), distance: 1, trackData: Data())
        let sorted = ActivitiesView.newestFirst([old, new])
        #expect(sorted.map(\.id) == ["new", "old"])
    }
}
