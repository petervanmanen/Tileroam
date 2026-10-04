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
    @AppStorage(Challenges.key) private var challenges = ""
    let onChooseFolder: (PickerPurpose) -> Void
    let onShowIntro: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // Shown off while iCloud isn't available (the setting itself stays as it is).
                    Toggle(isOn: Binding(get: { store.isICloudAvailable && store.isICloudSyncOn },
                                         set: { store.isICloudSyncOn = $0 })) {
                        Label("Sync with iCloud", systemImage: "icloud")
                    }
                    .disabled(!store.isICloudAvailable)
                    Button { onChooseFolder(.fitFiles) } label: {
                        Label("Import .fit Files…", systemImage: "square.and.arrow.down")
                    }
                    if store.hasSampleRides {
                        Button(role: .destructive) { Task { await store.removeSampleRides() } } label: {
                            Label("Remove Sample Rides", systemImage: "trash")
                        }
                    }
                    if !store.failedFiles.isEmpty {
                        NavigationLink {
                            List(store.failedFiles, id: \.self) { Text($0).font(.footnote) }
                                .navigationTitle("Could Not Read")
                        } label: {
                            Label("Could not read (\(store.failedFiles.count))", systemImage: "exclamationmark.triangle")
                        }
                    }
                    if let message = store.libraryMessage {
                        Text(message).font(.footnote)
                    }
                } header: {
                    Text("Activities")
                } footer: {
                    Text(store.isICloudAvailable
                         ? "\(store.libraryFileCount) activity files on this device, and with iCloud sync also in iCloud Drive › Tileroam. Imported files are copied once."
                         : "\(store.libraryFileCount) activity files on this device. Sign in to iCloud with iCloud Drive on to share them with your other devices.")
                }

                #if STRAVA
                stravaSection
                #endif

                Section {
                    ForEach(Challenges.all) { mode in
                        Toggle(isOn: Binding(
                            get: { Challenges.decode(challenges).contains(mode) },
                            set: { on in
                                var set = Challenges.decode(challenges)
                                if on { set.insert(mode) } else { set.remove(mode) }
                                challenges = Challenges.encode(set)
                            })) {
                            Label(mode.title, systemImage: mode.symbol)
                        }
                    }
                } header: {
                    Text("Challenges")
                } footer: {
                    Text("Tiles are always on the map. Challenges you hide still count.")
                }

                Section {
                    NavigationLink { StorageView() } label: { Label("Storage", systemImage: "internaldrive") }
                    Button { onShowIntro() } label: { Label("Show Introduction", systemImage: "sparkles") }
                    NavigationLink { SourcesView() } label: { Label("Sources & Licenses", systemImage: "doc.text") }
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
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
                Text("Strava activities are saved as .fit files in Tileroam's activities. Detailed GPS downloads within Strava's rate limit (about 100 activities per 15 minutes, 1000 per day) and continues automatically.")
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
        (Country.named("DE")!.name, "© GeoBasis-DE / BKG (dl-de/by-2-0) – Gemeinden; postcodes © OpenStreetMap contributors (ODbL)"),
        (Country.named("FR")!.name, "© IGN, INSEE (Licence Ouverte 2.0) – communes; codes postaux © Etalab / BAN (Licence Ouverte 2.0)"),
        (Country.named("CH")!.name, "© swisstopo – Gemeinden and Ortschaftenverzeichnis (opendata.swiss)"),
        (Country.named("AT")!.name, "© Statistik Austria (CC BY 4.0)"),
        (String(localized: "Route planning"), "© OpenStreetMap contributors (ODbL), via Geofabrik; routing by Valhalla (MIT) on the device"),
        (String(localized: "Badges"), "Country outlines: Natural Earth (public domain)"),
        (String(localized: "Trappist Challenge"), "Brewery logos © the Trappist breweries and abbeys, shown to identify each brewery; locations from public sources"),
        (String(localized: "Elevation and climbs"), "Terrain Tiles (AWS Open Data): SRTM (NASA, public domain); EU-DEM, produced using Copernicus data and information funded by the European Union; climbs found by Tileroam on OpenStreetMap roads (ODbL)"),
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
