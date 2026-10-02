import AuthenticationServices
import SwiftUI

struct SettingsView: View {
    @Environment(ActivityStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var confirmDisconnect = false
    @State private var confirmDeleteStravaFiles = false
    @State private var stravaFileCount = 0
    @State private var showStorage = false
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
                        LabeledContent("Selected", value: store.isICloudAvailable ? "iCloud Drive" : String(localized: "Internal storage"))
                        Text(FolderAccess.defaultSaveLocation)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let message = store.exportMessage {
                        Text(message).font(.footnote)
                    }
                    Button("Choose Save Folder…") { onChooseFolder(.export) }
                    if store.exportFolderName != nil {
                        if store.isICloudAvailable {
                            Button("Use iCloud Drive") { store.useDefaultSaveFolder() }
                        } else {
                            Button("Use Internal Storage") { store.useDefaultSaveFolder() }
                        }
                    }
                } header: {
                    Text("Save Folder")
                } footer: {
                    if FeatureFlags.strava {
                        Text("Tileroam saves planned routes and downloaded activities here, in “Routes” and “\(StravaExport.subfolder)” subfolders. Without a chosen folder they go to Tileroam's folder in iCloud Drive, so your other devices have them too, or to the app's own storage when iCloud Drive is off.")
                    } else {
                        Text("Tileroam saves planned routes here, in a “Routes” subfolder. Without a chosen folder they go to Tileroam's folder in iCloud Drive, so your other devices have them too, or to the app's own storage when iCloud Drive is off.")
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
                    if store.isICloudAvailable {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Label("iCloud Drive", systemImage: "icloud")
                                Spacer()
                                Text("\(store.activityCount(inFolder: FolderAccess.ImportFolder.iCloudID)) activities")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Text(FolderAccess.iCloudLocation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
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
                    if store.hasSampleRides {
                        Button("Remove Sample Rides", role: .destructive) { Task { await store.removeSampleRides() } }
                    }
                    Button("Rescan Now") { Task { await store.refresh() } }
                        .disabled(store.isImporting)
                } header: {
                    Text("Import Folders")
                } footer: {
                    Text("Tileroam reads .fit files from these folders and their subfolders, and always from its own folder in iCloud Drive, shared by your devices, and the Import folder in its own storage (put files there with the Files app or AirDrop). Swipe left on a folder to remove it; its activities disappear from the map, the files themselves are not touched.")
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

                Section {
                    NavigationLink {
                        StatisticsView()
                    } label: {
                        Label("Statistics", systemImage: "chart.bar.xaxis")
                    }
                    LabeledContent("Activities", value: store.activities.count.formatted())
                    LabeledContent("Without GPS", value: store.activitiesWithoutGPS.formatted())
                } footer: {
                    Text("Activities without GPS (indoor workouts, or workouts synced into Apple Health without a route) are counted but can't be drawn.")
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
                    NavigationLink {
                        StorageView()
                    } label: {
                        Label("Storage", systemImage: "internaldrive")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showStorage) { StorageView() }
            #if DEBUG
            // Screenshots: -ShowSettings YES -ShowStorage YES opens Settings → Storage on launch.
            .onAppear { if UserDefaults.standard.bool(forKey: "ShowStorage") { showStorage = true } }
            #endif
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
                    if stravaFileCount > 0 {
                        Button("Delete Files Saved from Strava (\(stravaFileCount))", role: .destructive) {
                            confirmDeleteStravaFiles = true
                        }
                    }
                }
                if let deleted = store.stravaFilesDeleted {
                    Text("Deleted \(deleted) files saved from Strava.").font(.footnote)
                }
                if let error = store.stravaError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .symbolRenderingMode(.multicolor)
                }
            } else {
                Text("Strava is not set up in this build: add StravaConfig.plist with the Client ID and token service URL, then rebuild.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Strava")
        } footer: {
            PoweredByStrava()
                .padding(.vertical, 4)
            if store.isStravaConnected {
                Text("Strava activities are saved as .fit files in the save folder's “\(StravaExport.subfolder)” subfolder. Detailed GPS downloads within Strava's rate limit (about 100 activities per 15 minutes, 1000 per day) and continues automatically.")
            }
        }
        .task(id: store.isStravaConnected) { stravaFileCount = await store.countStravaFiles() }
        .confirmationDialog("Disconnect Strava?", isPresented: $confirmDisconnect, titleVisibility: .visible) {
            Button("Disconnect and Delete Strava Files", role: .destructive) {
                Task {
                    await store.disconnectStrava(deleteFiles: true)
                    stravaFileCount = await store.countStravaFiles()
                }
            }
            Button("Disconnect, Keep Files") {
                Task {
                    await store.disconnectStrava(deleteFiles: false)
                    stravaFileCount = await store.countStravaFiles()
                }
            }
        } message: {
            Text("Strava activities are removed from this device. You can also delete the .fit files Tileroam saved from Strava, in all its folders; files from other apps are never touched.")
        }
        .confirmationDialog("Delete files saved from Strava?", isPresented: $confirmDeleteStravaFiles, titleVisibility: .visible) {
            Button("Delete \(stravaFileCount) Files", role: .destructive) {
                Task {
                    await store.deleteStravaFiles()
                    stravaFileCount = await store.countStravaFiles()
                }
            }
        } message: {
            Text("Only the .fit files Tileroam saved from Strava are deleted; files from other apps are kept.")
        }
    }
    #endif
}

#if STRAVA
/// The official "Connect with Strava" button. Opens the Strava app's authorize screen when the
/// app is installed (it returns via tileroam://), otherwise Strava's web login.
struct StravaConnectButton: View {
    @Environment(ActivityStore.self) private var store
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            Task { await connect() }
        } label: {
            Image("StravaConnect")
                .resizable()
                .scaledToFit()
                .frame(height: 48)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Connect with Strava")
        .disabled(store.stravaConfig == nil)
    }

    private func connect() async {
        guard let config = store.stravaConfig, let state = await store.beginStravaLogin() else { return }
        let appURL = config.appAuthorizeURL(state: state)
        if UIApplication.shared.canOpenURL(appURL) {
            openURL(appURL) // the Strava app returns to tileroam://localhost (handled in TileroamApp)
            return
        }
        do {
            let callback = try await webAuthenticationSession.authenticate(
                using: config.webAuthorizeURL(state: state),
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

/// "Powered by Strava", required next to data from Strava.
struct PoweredByStrava: View {
    var body: some View {
        Image("PoweredByStrava")
            .resizable()
            .scaledToFit()
            .frame(height: 22)
            .accessibilityLabel("Powered by Strava")
    }
}
#endif

/// Data sources and licenses (required attribution).
private struct SourcesView: View {
    private let sources: [(String, String)] = [
        (Country.named("NL")!.name, "© CBS, Kadaster (CC BY 4.0) – gemeenten 2025, postcode4 2024 via PDOK"),
        (Country.named("BE")!.name, "© NGI-IGN, bpost – municipalities and postal codes via Opendatasoft"),
        (Country.named("LU")!.name, "© ACT Luxembourg (CC0)"),
        (String(localized: "Route planning"), "© OpenStreetMap contributors (ODbL), via Geofabrik; routing by Valhalla (MIT) on the device"),
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
