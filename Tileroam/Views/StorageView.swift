import SwiftUI

/// Settings → Storage: what Tileroam keeps on the device, and removing downloaded map data.
struct StorageView: View {
    @Environment(ActivityStore.self) private var store
    @Environment(PlanStore.self) private var plan
    @AppStorage(MapDataDownloads.allowMobileDataKey) private var allowMobileData = false
    @State private var areas: [StoredArea] = []
    @State private var mainRoads: StoredArea?
    @State private var boundaries: [(country: Country, bytes: Int)] = []
    @State private var cacheBytes = 0
    @State private var confirmRemoveAll = false
    @State private var isWorking = false

    /// Downloaded tiles of one 1° area (levels 1 and 2), or the main roads (level 0, 4° tiles).
    struct StoredArea: Identifiable {
        let lat: Int
        let lon: Int
        let tiles: [RoutingIndex.Tile]
        var id: String { "\(lat),\(lon)" }
        var bytes: Int { tiles.reduce(0) { $0 + $1.rawBytes } }
    }

    private var routingBytes: Int { (areas + [mainRoads].compactMap { $0 }).reduce(0) { $0 + $1.bytes } }
    private var boundaryBytes: Int { boundaries.reduce(0) { $0 + $1.bytes } }

    var body: some View {
        List {
            Section {
                LabeledContent("Total", value: MapDataDownloads.format(routingBytes + boundaryBytes + cacheBytes))
            }

            Section {
                if areas.isEmpty {
                    Text("No route planning areas downloaded.").foregroundStyle(.secondary)
                }
                ForEach(areas) { area in
                    LabeledContent {
                        Text(MapDataDownloads.format(area.bytes)).monospacedDigit()
                    } label: {
                        if let name = name(of: area) {
                            Text(name)
                            Text(coordinates(of: area))
                        } else {
                            Text(coordinates(of: area))
                        }
                    }
                    .swipeActions {
                        Button("Remove", role: .destructive) { remove(area.tiles, all: false) }
                    }
                }
                if let mainRoads {
                    LabeledContent {
                        Text(MapDataDownloads.format(mainRoads.bytes)).monospacedDigit()
                    } label: {
                        Text("Main roads")
                        Text("Shared by all areas")
                    }
                    .swipeActions {
                        Button("Remove", role: .destructive) { remove(mainRoads.tiles, all: false) }
                    }
                }
                if !areas.isEmpty || mainRoads != nil {
                    Button("Remove All Route Planning Data", role: .destructive) { confirmRemoveAll = true }
                        .disabled(isWorking)
                }
            } header: {
                Text("Route Planning Map Data")
            } footer: {
                Text("Map data is downloaded for the surroundings of each route you plan, and listed here per area of about 70 × 110 km. Swipe left to remove one; it downloads again the next time you plan there.")
            }

            Section {
                Toggle("Download Map Data over Mobile Data", isOn: $allowMobileData)
            } footer: {
                Text("Map data larger than \(MapDataDownloads.format(MapDataDownloads.wifiThreshold)) downloads only on Wi-Fi, unless this is on. While planning, you can also choose Download Anyway.")
            }

            Section {
                ForEach(boundaries, id: \.country.code) { item in
                    LabeledContent("\(item.country.flag) \(item.country.name)", value: MapDataDownloads.format(item.bytes))
                }
                if boundaries.isEmpty {
                    Text("No boundaries downloaded.").foregroundStyle(.secondary)
                }
            } header: {
                Text("Municipalities and Postcodes")
            } footer: {
                Text("Downloaded for the countries you have activities in. They're small and load again automatically, so they can't be removed here.")
            }

            Section {
                LabeledContent("Activity cache", value: MapDataDownloads.format(cacheBytes))
                Button("Clear Cache & Re-import", role: .destructive) {
                    Task {
                        await store.clearCache()
                        await reload()
                    }
                }
                .disabled(store.isImporting)
            } footer: {
                Text("Tracks, tiles and areas read from your .fit files, so they don't have to be read again at every start. Clearing it reads all files again.")
            }
        }
        .navigationTitle("Storage")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .confirmationDialog("Remove all route planning map data?", isPresented: $confirmRemoveAll, titleVisibility: .visible) {
            Button("Remove All", role: .destructive) { remove([], all: true) }
        } message: {
            Text("It downloads again the next time you plan a route.")
        }
    }

    /// Measures what's on the device, off the main thread: asking Background Assets where the
    /// boundary files are can take a while, and the routing tiles are a thousand file checks.
    private func reload() async {
        let index = RoutingData.index
        let (downloaded, boundaries, cacheBytes) = await Task.detached(priority: .userInitiated) {
            (index.map(RoutingData.downloadedTiles) ?? [],
             Country.all.compactMap { c in RegionAssets.downloadedBytes(country: c.code).map { (country: c, bytes: $0) } },
             TrackCache.bytes(.folder) + TrackCache.bytes(.strava))
        }.value
        let local = Dictionary(grouping: downloaded.filter { $0.level > 0 }) { [Int($0.lat.rounded(.down)), Int($0.lon.rounded(.down))] }
        areas = local.map { StoredArea(lat: $0.key[0], lon: $0.key[1], tiles: $0.value) }
            .sorted { ($0.lat, $0.lon) > ($1.lat, $1.lon) }
        let main = downloaded.filter { $0.level == 0 }
        mainRoads = main.isEmpty ? nil : StoredArea(lat: 0, lon: 0, tiles: main)
        self.boundaries = boundaries
        self.cacheBytes = cacheBytes
    }

    private func remove(_ tiles: [RoutingIndex.Tile], all: Bool) {
        isWorking = true
        Task {
            await plan.removeRoutingData(tiles, all: all)
            await reload()
            isWorking = false
        }
    }

    /// "Lelystad area": the municipality nearest the area's centre, when boundaries are loaded.
    private func name(of area: StoredArea) -> String? {
        let center = GeoPoint(lat: Double(area.lat) + 0.5, lon: Double(area.lon) + 0.5)
        let nearest = store.regions?.municipalities.all
            .filter { Int(($0.minLat + $0.maxLat) / 2) == area.lat && Int(($0.minLon + $0.maxLon) / 2) == area.lon }
            .min { Geo.distance(middle($0), center) < Geo.distance(middle($1), center) }
        return nearest.map { String(localized: "\($0.name) area") }
    }

    private func middle(_ a: Area) -> GeoPoint {
        GeoPoint(lat: (a.minLat + a.maxLat) / 2, lon: (a.minLon + a.maxLon) / 2)
    }

    private func coordinates(of area: StoredArea) -> String {
        "\(abs(area.lat))°\(area.lat >= 0 ? "N" : "S") \(abs(area.lon))°\(area.lon >= 0 ? "E" : "W")"
    }
}
