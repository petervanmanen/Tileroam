import Foundation
import Testing
@testable import Tileroam

struct CountryOutlinesTests {
    let outlines = CountryOutlines.bundled!

    @Test func pointsInCountries() {
        #expect(outlines.country(at: GeoPoint(lat: 52.0907, lon: 5.1214)) == "NL") // Utrecht
        #expect(outlines.country(at: GeoPoint(lat: 50.8514, lon: 5.6910)) == "NL") // Maastricht
        #expect(outlines.country(at: GeoPoint(lat: 50.6326, lon: 5.5797)) == "BE") // Liège
        #expect(outlines.country(at: GeoPoint(lat: 49.6116, lon: 6.1319)) == "LU") // Luxembourg
        #expect(outlines.country(at: GeoPoint(lat: 53.0600, lon: 4.8000)) == "NL") // Texel
        #expect(outlines.country(at: GeoPoint(lat: 50.7753, lon: 6.0839)) == "DE") // Aachen
        #expect(outlines.country(at: GeoPoint(lat: 52.5163, lon: 13.3777)) == "DE") // Berlin
        #expect(outlines.country(at: GeoPoint(lat: 47.4210, lon: 10.9850)) == "DE") // Zugspitze area
    }

    @Test func pointsOutsideSupportedCountries() {
        #expect(outlines.country(at: GeoPoint(lat: 53.5, lon: 3.0)) == nil) // North Sea
        #expect(outlines.country(at: GeoPoint(lat: 50.0755, lon: 14.4378)) == nil) // Prague
        #expect(outlines.country(at: GeoPoint(lat: 47.5596, lon: 7.5886)) == nil) // Basel
        #expect(outlines.country(at: GeoPoint(lat: 48.8566, lon: 2.3522)) == nil) // Paris
    }

    @Test func tracksNearBordersOnlyCountTheirCountries() {
        // Rides around Maastricht and Utrecht: Belgium's bounding box contains these points, its
        // outline doesn't.
        let tracks = [
            [GeoPoint(lat: 50.8514, lon: 5.6910), GeoPoint(lat: 50.87, lon: 5.70)],
            [GeoPoint(lat: 52.0907, lon: 5.1214), GeoPoint(lat: 52.10, lon: 5.15)],
        ]
        #expect(outlines.countries(visitedBy: tracks) == ["NL"])
        // A track's last point counts too.
        #expect(outlines.countries(visitedBy: [[GeoPoint(lat: 50.8514, lon: 5.6910), GeoPoint(lat: 50.6326, lon: 5.5797)]])
                == ["NL", "BE"])
    }
}

struct CountrySelectionTests {
    @Test func keepsVisitedAndFailedCountries() {
        let keep = CountrySelection.pruned(enabled: ["NL", "BE", "DE", "FR"],
                                           visitedMunicipalities: ["NL:GM0344", "BE:71002"], failed: ["FR"])
        #expect(keep == ["NL", "BE", "FR"])
    }

    @Test func noChangeGivesNil() {
        #expect(CountrySelection.pruned(enabled: ["NL"], visitedMunicipalities: ["NL:GM0344"], failed: []) == nil)
    }

    @Test func noVisitsKeepsTheCurrentChoice() {
        #expect(CountrySelection.pruned(enabled: ["NL", "BE"], visitedMunicipalities: [], failed: []) == nil)
    }
}

@MainActor
struct SettingsSyncTests {
    private func stores() -> (local: UserDefaults, cloud: UserDefaults) {
        (UserDefaults(suiteName: "test-local-\(UUID())")!, UserDefaults(suiteName: "test-cloud-\(UUID())")!)
    }

    @Test func pushesChangedSettingsOnce() {
        let (local, cloud) = stores()
        local.set(17, forKey: "tileZoom")
        local.set("something", forKey: "notSynced")
        #expect(SettingsSync.push(from: local, to: cloud) == ["tileZoom"])
        #expect(cloud.integer(forKey: "tileZoom") == 17)
        #expect(cloud.object(forKey: "notSynced") == nil)
        #expect(SettingsSync.push(from: local, to: cloud).isEmpty) // already equal: no write loop
    }

    @Test func pullsOnlySyncedKeysThatDiffer() {
        let (local, cloud) = stores()
        cloud.set("hybrid", forKey: "mapStyle")
        cloud.set(["DE"], forKey: "enabledCountries") // not synced (any more)
        local.set("standard", forKey: "mapStyle")
        #expect(SettingsSync.pull(["mapStyle", "enabledCountries"], from: cloud, to: local) == ["mapStyle"])
        #expect(local.string(forKey: "mapStyle") == "hybrid")
        #expect(local.object(forKey: "enabledCountries") == nil)
        #expect(SettingsSync.pull(["mapStyle"], from: cloud, to: local).isEmpty)
    }
}

@Suite(.serialized)
struct StravaFilesTests {
    @Test func findsOnlyOwnStravaFiles() throws {
        let marker = UUID().uuidString.prefix(8)
        let names = ["2026-05-01-090000-Ride \(marker)-Strava-900000123.fit", // ours
                     ".2026-05-02-090000-Ride \(marker)-Strava-900000456.fit.icloud", // ours, not downloaded
                     "2026-05-01-HealthFit \(marker)-Strava.fit"] // HealthFit's own export
        for name in names { try Data([1]).write(to: Library.activitiesFolder.appending(path: name)) }
        defer { for name in names { try? FileManager.default.removeItem(at: Library.activitiesFolder.appending(path: name)) } }
        let own = StravaExport.ownFiles().filter { $0.contains(marker) }
        #expect(own == ["2026-05-01-090000-Ride \(marker)-Strava-900000123.fit", "2026-05-02-090000-Ride \(marker)-Strava-900000456.fit"])
    }
}

struct StravaEventTests {
    @Test func decodesTheTokenServiceEvents() throws {
        let json = #"{"events":[{"type":"deleted","time":1790900001,"activity":999},{"type":"deauthorized","time":1790900000}]}"#
        struct Response: Decodable { let events: [StravaEvent] }
        let events = try JSONDecoder().decode(Response.self, from: Data(json.utf8)).events
        #expect(events == [StravaEvent(type: "deleted", time: 1790900001, activity: 999),
                           StravaEvent(type: "deauthorized", time: 1790900000, activity: nil)])
    }

    @Test func changesFromEvents() {
        let changes = StravaEventChanges([
            StravaEvent(type: "created", time: 1, activity: 10),
            StravaEvent(type: "deleted", time: 2, activity: 11),
            StravaEvent(type: "deleted", time: 3, activity: 12),
            StravaEvent(type: "private", time: 4, activity: 13), // older Worker: ignored
        ])
        #expect(!changes.revoked)
        #expect(changes.removedActivities == [11, 12])
        #expect(StravaEventChanges([StravaEvent(type: "deauthorized", time: 5, activity: nil)]).revoked)
    }

    @Test func findsOnlyFilesOfDeletedActivities() throws {
        // Strava files in the library, with IDs no real file has; 9000000012 must not match 900000001.
        let names = ["2026-05-01-Ride-Strava-900000001.fit", "2026-05-02-Ride-Strava-9000000012.fit", "2026-05-03-Ride-Strava-900000045.fit"]
        for name in names { try Data([1]).write(to: Library.activitiesFolder.appending(path: name)) }
        defer { for name in names { try? FileManager.default.removeItem(at: Library.activitiesFolder.appending(path: name)) } }
        #expect(StravaExport.ownFiles(of: [900000001, 900000045]) == [names[0], names[2]])
    }
}
