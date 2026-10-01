import SwiftUI
import UniformTypeIdentifiers

enum PickerPurpose {
    /// Folder with .fit files to import.
    case source
    /// The app's own save folder (e.g. iCloud Drive › Tileroam).
    case export
    /// A GPX route to check against visited tiles and areas.
    case gpx
    /// Individual .fit files, copied into the app's internal Import folder.
    case fitFiles

    var contentTypes: [UTType] {
        switch self {
        case .source, .export: [.folder]
        case .gpx: [UTType(filenameExtension: "gpx"), .xml].compactMap { $0 }
        case .fitFiles: [UTType(filenameExtension: "fit") ?? .data, .data]
        }
    }

    var allowsMultipleSelection: Bool { self == .source || self == .fitFiles }
}

struct ContentView: View {
    @Environment(ActivityStore.self) private var store
    @Environment(PlanStore.self) private var plan
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("mapMode") private var mode: MapMode = .squares
    @AppStorage("tileZoom") private var tileZoom: TileZoom = .explorer
    @AppStorage("mapStyle") private var mapStyle: MapStyle = .standard
    @State private var showPicker = false
    @State private var showSettings = false
    @State private var showStatistics = false
    @State private var pickerPurpose = PickerPurpose.source
    @State private var pickAfterSettings: PickerPurpose?
    @State private var selectedArea: Area?
    @State private var locateRequest = 0
    @State private var isFollowingUser = false
    @State private var locationDenied = false
    @AppStorage("hasSeenIntro") private var hasSeenIntro = false
    @State private var showIntro = false
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// iPad (or a wide window): controls in a floating side panel instead of top and bottom bars.
    private var isWide: Bool { sizeClass == .regular }
    private let sidePanelWidth: CGFloat = 380

    var body: some View {
        ActivityMapView(mode: mode, mapStyle: mapStyle, tileZoom: tileZoom, store: store, version: store.version, selectedArea: $selectedArea,
                        locateRequest: locateRequest, isFollowingUser: $isFollowingUser, locationDenied: $locationDenied,
                        plan: plan, planVersion: plan.version, leadingInset: isWide ? sidePanelWidth + 32 : 0)
            .ignoresSafeArea()
            .alert("Location Access Is Off", isPresented: $locationDenied) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Allow Tileroam to use your location in Settings to center the map on where you are.")
            }
            .safeAreaInset(edge: .top) { if !isWide { header } }
            .safeAreaInset(edge: .bottom) { if !isWide { footer } }
            .overlay(alignment: .topLeading) { if isWide { sidePanel } }
            .overlay(alignment: .bottomTrailing) { if isWide { mapControls.padding(24) } }
            .overlay {
                if !store.hasImportFolders && store.activities.isEmpty && !store.isStravaConnected && !store.isImporting {
                    emptyState
                }
            }
            .fileImporter(isPresented: $showPicker, allowedContentTypes: pickerPurpose.contentTypes,
                          allowsMultipleSelection: pickerPurpose.allowsMultipleSelection) { result in
                guard case .success(let urls) = result, let url = urls.first else { return }
                switch pickerPurpose {
                case .source: Task { await store.addFolders(urls) }
                case .export: Task { await store.selectExportFolder(url) }
                case .gpx: Task { await plan.importGPX(url, with: store) }
                case .fitFiles: Task { await store.importFiles(urls) }
                }
            }
            .sheet(isPresented: $showSettings, onDismiss: {
                // Present the picker only after the sheet is gone; one fileImporter for the whole app.
                if let purpose = pickAfterSettings {
                    pickAfterSettings = nil
                    pickerPurpose = purpose
                    showPicker = true
                }
            }) {
                SettingsView(onChooseFolder: { purpose in
                    pickAfterSettings = purpose
                    showSettings = false
                }, onShowIntro: {
                    showSettings = false
                    Task {
                        try? await Task.sleep(for: .milliseconds(400))
                        showIntro = true
                    }
                })
            }
            .sheet(isPresented: $showStatistics) {
                NavigationStack {
                    StatisticsView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showStatistics = false }
                            }
                        }
                }
            }
            .fullScreenCover(isPresented: $showIntro) {
                IntroView {
                    hasSeenIntro = true
                    showIntro = false
                }
                .presentationBackground(Color(.systemBackground))
            }
            .onAppear {
                if !hasSeenIntro { showIntro = true }
                #if DEBUG
                // Screenshots: -ShowSettings YES opens Settings on launch.
                if UserDefaults.standard.bool(forKey: "ShowSettings") { showSettings = true }
                if UserDefaults.standard.bool(forKey: "ShowStatistics") { showStatistics = true }
                #endif
            }
            .task { await store.refreshAll() }
            #if DEBUG
            .task { await plan.runDebugDemo(with: store) }
            #endif
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await store.refreshAll() } }
            }
            .onChange(of: mode) { selectedArea = nil }
            .onChange(of: tileZoom, initial: true) { _, zoom in WidgetData.saveTileZoom(zoom.rawValue) }
            .onChange(of: plan.isPlanning) { _, planning in
                selectedArea = nil
                if planning, mode == .activities { mode = .squares }
            }
    }

    private var header: some View {
        headerContent
            .padding(10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)
    }

    /// iPad: header at the top, status and planning cards at the bottom of a left column.
    private var sidePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerContent
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 8) { footerCards }
        }
        .frame(width: sidePanelWidth)
        .padding(16)
    }

    private var headerContent: some View {
        VStack(spacing: 8) {
            Picker("Mode", selection: $mode) {
                ForEach(MapMode.allCases.filter { !plan.isPlanning || $0 != .activities }) { Text($0.tabTitle).tag($0) }
            }
            .pickerStyle(.segmented)
            HStack(alignment: .center, spacing: 10) {
                Text(statsText)
                    .font(.footnote.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    plan.isPlanning.toggle()
                } label: {
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.title3)
                        .foregroundStyle(plan.isPlanning ? Color.white : Color.accentColor)
                        .padding(4)
                        .background(plan.isPlanning ? Color.purple : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                }
                .accessibilityLabel(plan.isPlanning ? Text("Stop route planning") : Text("Plan a route"))
                Button {
                    showStatistics = true
                } label: {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.title3)
                }
                .accessibilityLabel("Statistics")
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.title3)
                }
                .accessibilityLabel("Settings")
            }
        }
    }

    private var statsText: String {
        if plan.isPlanning { return String(localized: "Route planning · tap unvisited items to select them") }
        switch mode {
        case .squares:
            let s = store.tileStats(tileZoom)
            let count = tileZoom.countLabel(store.tiles(tileZoom).count)
            return String(localized: "\(count) · max square \(s.maxSquare)×\(s.maxSquare) · cluster \(s.maxCluster)")
        case .activities:
            let onMap = store.mapActivities.count
            let e = store.eddingtonCycling
            return String(localized: "\(onMap) on map · \(store.activities.count - onMap) indoor, virtual or without GPS")
                + "\n" + String(localized: "Eddington \(e.number) · \(e.daysNeeded) more rides of \(e.number + 1) km to reach \(e.number + 1)")
        case .gemeenten:
            guard let areas = store.municipalityAreas else { return String(localized: "Loading municipalities…") }
            return String(localized: "\(store.visitedMunicipalities.count) / \(areas.all.count) municipalities visited")
        case .postcodes:
            guard let areas = store.postcodeAreas else { return String(localized: "Loading postcodes…") }
            return String(localized: "\(store.visitedPostcodes.count) / \(areas.all.count) postcodes visited")
        }
    }

    /// Layer choice and location button at the bottom right of the map.
    private var mapControls: some View {
        VStack(spacing: 10) {
            layersButton
            locationButton
        }
    }

    private var layersButton: some View {
        Menu {
            Picker("Map Style", selection: $mapStyle) {
                ForEach(MapStyle.allCases) { style in
                    Label(style.title, systemImage: style.symbol).tag(style)
                }
            }
        } label: {
            Image(systemName: "square.3.layers.3d")
                .font(.title3)
                .frame(width: 48, height: 48)
                .background(.regularMaterial, in: Circle())
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        }
        .accessibilityLabel("Map Style")
    }

    private var locationButton: some View {
        Button {
            locateRequest += 1
        } label: {
            Image(systemName: isFollowingUser ? "location.fill" : "location")
                .font(.title3)
                .frame(width: 48, height: 48)
                .background(.regularMaterial, in: Circle())
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        }
        .accessibilityLabel(isFollowingUser ? Text("Stop following location") : Text("Center on my location"))
    }

    private var footer: some View {
        VStack(alignment: .trailing, spacing: 8) {
            mapControls
            footerCards
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal)
    }

    /// Planning panel, problems and progress; at the bottom on iPhone, in the side panel on iPad.
    @ViewBuilder
    private var footerCards: some View {
        Group {
            if plan.isPlanning {
                PlanPanel {
                    pickerPurpose = .gpx
                    showPicker = true
                }
            }
            if let problem = store.problem, !store.isImporting {
                VStack(alignment: .leading, spacing: 8) {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .symbolRenderingMode(.multicolor)
                    Button("Add Another Folder") {
                        pickerPurpose = .source
                        showPicker = true
                    }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
            if store.isImporting, store.progress.total == 0 {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Scanning folder…").font(.footnote)
                }
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
            if let status = store.stravaStatus {
                Label(status, systemImage: "arrow.triangle.2.circlepath")
                    .font(.footnote)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
            }
            if !plan.isPlanning, let m = selectedArea, let (_, visitedCodes) = mode.areas(in: store) {
                let visited = visitedCodes.contains(m.code)
                HStack {
                    Image(systemName: visited ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(visited ? .green : .secondary)
                    Text(mode == .postcodes ? String(localized: "Postcode \(m.postcodeLabel)") : m.name).font(.headline)
                    Spacer()
                    (visited ? Text("Visited") : Text("Not visited")).foregroundStyle(.secondary)
                }
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
            if store.isImporting, store.progress.total > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Importing \(store.progress.done) of \(store.progress.total) activities…")
                        .font(.footnote)
                    ProgressView(value: Double(store.progress.done), total: Double(store.progress.total))
                }
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    /// First start: choose a folder, import files or connect Strava.
    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "map")
                .font(.largeTitle)
                .foregroundStyle(.green)
            Text("Add your activities")
                .font(.headline)
            if FeatureFlags.strava {
                Text("Choose a folder with .fit files, import files, or connect Strava to see where you have been.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("Choose a folder with .fit files or import files to see where you have been.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            VStack(spacing: 10) {
                Button {
                    pickerPurpose = .source
                    showPicker = true
                } label: {
                    Label("Choose Folder…", systemImage: "folder.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button {
                    pickerPurpose = .fitFiles
                    showPicker = true
                } label: {
                    Label("Import .fit Files…", systemImage: "doc.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                #if STRAVA
                if store.stravaConfig != nil {
                    StravaConnectButton()
                        .frame(maxWidth: .infinity)
                        .buttonStyle(.bordered)
                }
                #endif
                Button {
                    Task { await store.addSampleRides() }
                } label: {
                    Text("Try with Sample Rides")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderless)
                .padding(.top, 4)
            }
            .frame(maxWidth: 280)
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding(32)
    }
}
