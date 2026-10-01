import AuthenticationServices
import SwiftUI

struct SettingsView: View {
    @Environment(ActivityStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var confirmDisconnect = false
    @AppStorage("tileZoom") private var tileZoom: TileZoom = .explorer
    let onChooseFolder: (PickerPurpose) -> Void
    let onShowIntro: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let name = store.exportFolderName {
                        LabeledContent("Selected", value: name)
                        if let location = store.exportFolderLocation {
                            Text(location)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        LabeledContent("Selected", value: String(localized: "Internal storage"))
                        Text(FolderAccess.internalLocation)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let message = store.exportMessage {
                        Text(message).font(.footnote)
                    }
                    Button("Choose Save Folder…") { onChooseFolder(.export) }
                    if store.exportFolderName != nil {
                        Button("Use Internal Storage") { store.useInternalSaveFolder() }
                    }
                } header: {
                    Text("Save Folder")
                } footer: {
                    if FeatureFlags.strava {
                        Text("Tileroam saves planned routes and downloaded activities here, in “Routes” and “\(StravaExport.subfolder)” subfolders. Without a chosen folder they stay in the app's own storage, which you can open in the Files app. Choose a folder, for example a new “Tileroam” folder in iCloud Drive, to keep them in iCloud.")
                    } else {
                        Text("Tileroam saves planned routes here, in a “Routes” subfolder. Without a chosen folder they stay in the app's own storage, which you can open in the Files app. Choose a folder, for example a new “Tileroam” folder in iCloud Drive, to keep them in iCloud.")
                    }
                }

                Section {
                    ForEach(store.importFolders) { folder in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Label(folder.name, systemImage: "folder")
                                Spacer()
                                Text("\(store.activityCount(inFolder: folder.id)) activities")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            if let location = folder.location {
                                Text(location).font(.caption).foregroundStyle(.secondary)
                            }
                            if let problem = folder.problem {
                                Label(problem, systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .symbolRenderingMode(.multicolor)
                            }
                        }
                        .swipeActions {
                            Button("Remove", role: .destructive) { store.removeFolder(id: folder.id) }
                        }
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Label("Internal storage", systemImage: "iphone")
                            Spacer()
                            Text("\(store.activityCount(inFolder: FolderAccess.ImportFolder.internalID)) activities")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Text("\(FolderAccess.internalLocation) › Import")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button("Add Folder…") { onChooseFolder(.source) }
                    Button("Rescan Now") { Task { await store.refresh() } }
                        .disabled(store.isImporting)
                } header: {
                    Text("Import Folders")
                } footer: {
                    Text("Tileroam reads .fit files from these folders and their subfolders, and always from the Import folder in its own storage (put files there with the Files app or AirDrop). Swipe left on a folder to remove it; its activities disappear from the map, the files themselves are not touched.")
                }

                #if STRAVA
                stravaSection
                #endif

                Section {
                    Picker("Show on map", selection: $tileZoom) {
                        ForEach(TileZoom.allCases) { Text($0.shortTitle).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    tileRow(.explorer)
                    tileRow(.squadratinho)
                } header: {
                    Text("Tiles")
                } footer: {
                    Text("Zoom 14 tiles (~1.5 km in the Netherlands) are the explorer tiles of VeloViewer, StatsHunters and rideeverytile.com. Zoom 17 squadratinhos (~190 m) are used by Squadrats. Both are always counted; this setting chooses which one the map, statistics and route planning use.")
                }

                countriesSection

                Section {
                    NavigationLink {
                        StatisticsView()
                    } label: {
                        Label("Statistics", systemImage: "chart.bar.xaxis")
                    }
                    LabeledContent("Activities", value: store.activities.count.formatted())
                    LabeledContent("Without GPS", value: store.activitiesWithoutGPS.formatted())
                }

                if !store.failedFiles.isEmpty {
                    Section("Could not read (\(store.failedFiles.count))") {
                        ForEach(store.failedFiles, id: \.self) { Text($0).font(.footnote) }
                    }
                }

                Section {
                    Button("Show Introduction") { onShowIntro() }
                    NavigationLink("Sources & Licenses") { SourcesView() }
                }

                Section {
                    Button("Clear Cache & Re-import", role: .destructive) {
                        Task { await store.clearCache() }
                    }
                    .disabled(store.isImporting)
                } footer: {
                    Text("Activities without GPS (indoor workouts, or workouts synced into Apple Health without a route) are counted but can't be drawn.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

extension SettingsView {
    private func tileRow(_ zoom: TileZoom) -> some View {
        let stats = store.tileStats(zoom)
        return LabeledContent {
            Text(store.tiles(zoom).count.formatted()).font(.headline)
        } label: {
            Text(zoom.title)
            Text("Max square \(stats.maxSquare)×\(stats.maxSquare) · cluster \(stats.maxCluster)")
        }
    }

    @ViewBuilder
    private var countriesSection: some View {
        let municipalities = store.regionCounts(.municipalities)
        let postcodes = store.regionCounts(.postcodes)
        Section {
            ForEach(Country.sortedByName) { country in
                Toggle(isOn: Binding(get: { store.enabledCountries.contains(country.code) },
                                     set: { store.setCountry(country.code, enabled: $0) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(country.flag) \(country.name)")
                        if let m = municipalities[country.code] {
                            if let p = postcodes[country.code] {
                                Text("\(m.visited)/\(m.total) municipalities · \(p.visited)/\(p.total) postcodes")
                                    .font(.caption).foregroundStyle(.secondary)
                            } else {
                                Text("\(m.visited)/\(m.total) municipalities")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            NavigationLink("Municipalities") { AreaList(kind: .municipalities) }
            NavigationLink("Postcodes") { AreaList(kind: .postcodes) }
        } header: {
            HStack {
                Text("Countries")
                if store.isLoadingRegions { ProgressView().controlSize(.small) }
            }
        } footer: {
            Text("Municipalities and postcodes are counted for the switched-on countries. Postcodes are only available where their boundaries are open data. In the United Kingdom and Ireland, local authorities count as municipalities; in Andorra and San Marino, parishes and castelli.")
        }
    }

    #if STRAVA
    @ViewBuilder
    private var stravaSection: some View {
        Section {
            if store.stravaConfig != nil {
                if let athlete = store.stravaAthlete {
                    LabeledContent("Connected as", value: athlete.isEmpty ? String(localized: "Strava athlete") : athlete)
                    LabeledContent("Activities", value: store.stravaActivities.count.formatted())
                    LabeledContent("With detailed GPS", value: store.stravaDetailedCount.formatted())
                    LabeledContent("Saved to folder", value: store.stravaExportedCount.formatted())
                    if let status = store.stravaStatus {
                        HStack(spacing: 8) {
                            if store.isStravaSyncing && !store.isStravaPaused { ProgressView() }
                            Text(status).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    Button("Sync Now") { store.syncStrava() }
                        .disabled(store.isStravaSyncing)
                    Button("Disconnect Strava", role: .destructive) { confirmDisconnect = true }
                } else {
                    StravaConnectButton()
                }
                if let error = store.stravaError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .symbolRenderingMode(.multicolor)
                }
            } else {
                Text("Add your Strava API Client ID and Client Secret to StravaSecrets.plist in the Xcode project, then rebuild.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Strava")
        } footer: {
            if store.isStravaConnected {
                Text("Strava activities are saved as .fit files in the save folder's “\(StravaExport.subfolder)” subfolder. Detailed GPS downloads within Strava's rate limit (about 100 activities per 15 minutes, 1000 per day) and continues automatically.")
            }
        }
        .confirmationDialog("Disconnect Strava?", isPresented: $confirmDisconnect, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) { Task { await store.disconnectStrava() } }
        } message: {
            Text("Strava activities are removed from the map. Files already saved to your folder are kept.")
        }
    }
    #endif
}

#if STRAVA
/// "Connect with Strava", used in Settings and the introduction.
struct StravaConnectButton: View {
    @Environment(ActivityStore.self) private var store
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    var body: some View {
        Button {
            Task { await connect() }
        } label: {
            Label("Connect with Strava", systemImage: "link")
                .foregroundStyle(.orange)
        }
        .disabled(store.stravaConfig == nil)
    }

    private func connect() async {
        guard let config = store.stravaConfig else { return }
        do {
            let callback = try await webAuthenticationSession.authenticate(
                using: config.authorizeURL,
                callbackURLScheme: StravaConfig.callbackScheme,
                preferredBrowserSession: .shared)
            await store.completeStravaLogin(callback: callback)
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            // User cancelled.
        } catch {
            store.reportStravaError(String(localized: "Strava login failed: \(error.localizedDescription)"))
        }
    }
}

#endif

/// Searchable list of municipalities or postcodes of the switched-on countries.
private struct AreaList: View {
    @Environment(ActivityStore.self) private var store
    let kind: AreaKind
    @State private var search = ""

    var body: some View {
        let areas = store.regions?.areas(kind).all ?? []
        let visited = kind == .municipalities ? store.visitedMunicipalities : store.visitedPostcodes
        let filtered = areas.filter {
            search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.localCode.hasPrefix(search)
        }
        let byCountry = Dictionary(grouping: filtered, by: \.country)
        List {
            ForEach(Country.sortedByName.filter { byCountry[$0.code] != nil }) { country in
                Section("\(country.flag) \(country.name)") {
                    ForEach(byCountry[country.code]!.sorted { $0.name < $1.name || ($0.name == $1.name && $0.code < $1.code) }) { area in
                        let isVisited = visited.contains(area.code)
                        Label {
                            Text(kind == .postcodes ? area.postcodeLabel : area.name)
                        } icon: {
                            Image(systemName: isVisited ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isVisited ? .green : .secondary)
                        }
                    }
                }
            }
        }
        .searchable(text: $search)
        .navigationTitle(kind == .municipalities ? String(localized: "Municipalities") : String(localized: "Postcodes"))
    }
}

/// Data sources and licenses (required attribution).
private struct SourcesView: View {
    private let sources: [(String, String)] = [
        (Country.named("NL")!.name, "© CBS, Kadaster (CC BY 4.0) – gemeenten 2025, postcode4 2024 via PDOK"),
        (Country.named("BE")!.name, "© NGI-IGN, bpost – municipalities and postal codes via Opendatasoft"),
        (Country.named("DE")!.name, "© GeoBasis-DE / BKG (dl-de/by-2-0) – Gemeinden; postcodes © OpenStreetMap contributors (ODbL)"),
        (Country.named("FR")!.name, "© IGN, INSEE (Licence Ouverte 2.0) – communes; codes postaux © Etalab / BAN (Licence Ouverte 2.0)"),
        (Country.named("ES")!.name, "© IGN España, CNIG, Correos (CC BY 4.0)"),
        (Country.named("CH")!.name, "© swisstopo – Gemeinden and Ortschaftenverzeichnis (opendata.swiss)"),
        (Country.named("AT")!.name, "© Statistik Austria (CC BY 4.0)"),
        (Country.named("LU")!.name, "© ACT Luxembourg (CC0)"),
        (Country.named("GB")!.name, "Contains OS data © Crown copyright and database right; ONS (OGL v3.0); Royal Mail data © Royal Mail copyright; postcode districts CC BY 4.0"),
        (Country.named("IE")!.name, "© Tailte Éireann (CC BY 4.0)"),
        (Country.named("PT")!.name, "© Direção-Geral do Território – CAOP concelhos (public domain)"),
        (Country.named("IT")!.name, "© ISTAT (CC BY 3.0) – comuni"),
        (Country.named("DK")!.name, "© SDFI / Klimadatastyrelsen – DAGI kommuner and postnumre (free data)"),
        (Country.named("NO")!.name, "© Kartverket (CC BY 4.0) – kommuner 2024"),
        (Country.named("SE")!.name, "© OpenStreetMap contributors (ODbL) – kommuner"),
        (Country.named("FI")!.name, "© Statistics Finland (CC BY 4.0) – municipalities and postal code areas 2025"),
        (Country.named("IS")!.name, "© Náttúrufræðistofnun Íslands (CC BY 4.0) – sveitarfélög"),
        ("Liechtenstein, Monaco, San Marino", "© OpenStreetMap contributors (ODbL) via geoBoundaries"),
        ("Andorra, Vatican City", "geoBoundaries"),
        (String(localized: "Route planning"), "Route planning © OpenStreetMap contributors (ODbL), routing by OSRM / FOSSGIS"),
    ] + (FeatureFlags.strava ? [("Strava", String(localized: "Activity data from Strava when connected"))] : [])

    var body: some View {
        List(sources, id: \.0) { source in
            VStack(alignment: .leading, spacing: 4) {
                Text(source.0).font(.headline)
                Text(source.1).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Sources & Licenses")
    }
}
