import SwiftUI
import UniformTypeIdentifiers

enum PickerPurpose {
    /// A GPX route to check against visited tiles and areas.
    case gpx
    /// .fit files, or folders with .fit files, copied into the library once.
    case fitFiles

    var contentTypes: [UTType] {
        switch self {
        case .gpx: [UTType(filenameExtension: "gpx"), .xml].compactMap { $0 }
        case .fitFiles: [UTType(filenameExtension: "fit") ?? .data, .folder, .data]
        }
    }

    var allowsMultipleSelection: Bool { self == .fitFiles }
}

struct ContentView: View {
    @Environment(ActivityStore.self) private var store
    @Environment(PlanStore.self) private var plan
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("mapMode") private var mode: MapMode = .squares
    @AppStorage(Challenges.key) private var challenges = ""
    /// Zoom 14 (zoom 17 squadratinhos were removed in 1.5.9).
    private let tileZoom = TileZoom.explorer
    @AppStorage("mapStyle") private var mapStyle: MapStyle = .standard
    @State private var showPicker = false
    @State private var showSettings = false
    @State private var showStatistics = false
    @State private var showActivities = false
    @State private var pickerPurpose = PickerPurpose.fitFiles
    @State private var pickAfterSettings: PickerPurpose?
    @State private var selectedArea: Area?
    @State private var selectedClimb: Climb?
    @State private var selectedTrappist: Trappist?
    @State private var selectedKlompenpad: Klompenpad?
    @State private var selectedMTBRoute: MTBRoute?
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
        ActivityMapView(mode: mode, mapStyle: mapStyle, tileZoom: tileZoom, store: store, version: store.version, selectedArea: $selectedArea, selectedClimb: $selectedClimb, selectedTrappist: $selectedTrappist, selectedKlompenpad: $selectedKlompenpad, selectedMTBRoute: $selectedMTBRoute,
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
                // A further device whose iCloud has activities shows those instead (they load first).
                if store.activities.isEmpty && !store.isStravaConnected && !store.isImporting
                    && !(store.iCloudHasActivities && store.isICloudSyncOn) {
                    emptyState
                }
            }
            .fileImporter(isPresented: $showPicker, allowedContentTypes: pickerPurpose.contentTypes,
                          allowsMultipleSelection: pickerPurpose.allowsMultipleSelection) { result in
                guard case .success(let urls) = result, let url = urls.first else { return }
                switch pickerPurpose {
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
                .environment(store).environment(plan)
            }
            .sheet(isPresented: $showActivities) {
                NavigationStack {
                    ActivitiesView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showActivities = false }
                            }
                        }
                }
                .environment(store).environment(plan)
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
                .environment(store).environment(plan)
            }
            .fullScreenCover(isPresented: $showIntro) {
                IntroView {
                    hasSeenIntro = true
                    showIntro = false
                }
                .presentationBackground(Color(.systemBackground))
                // Passed on explicitly: on the Mac (Catalyst) presented views didn't get them.
                .environment(store).environment(plan)
            }
            .onAppear {
                if !hasSeenIntro { showIntro = true }
                // Users who were on a challenge's tab before challenges could be turned off (and
                // launches with -mapMode gemeenten) keep that challenge.
                if mode.isChallenge, !Challenges.decode(challenges).contains(mode) {
                    challenges = Challenges.encode(Challenges.decode(challenges).union([mode]))
                }
                #if DEBUG
                // Screenshots: -ShowSettings YES opens Settings on launch.
                if UserDefaults.standard.bool(forKey: "ShowSettings") { showSettings = true }
                if UserDefaults.standard.bool(forKey: "ShowStatistics") { showStatistics = true }
                if UserDefaults.standard.bool(forKey: "ShowActivities") { showActivities = true }
                #if targetEnvironment(macCatalyst)
                // Mac screenshots: -WindowSize 1440x900 fixes the window's size (points).
                let size = (UserDefaults.standard.string(forKey: "WindowSize") ?? "").split(separator: "x").compactMap { Double($0) }
                if size.count == 2 {
                    for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
                        scene.sizeRestrictions?.minimumSize = CGSize(width: size[0], height: size[1])
                        scene.sizeRestrictions?.maximumSize = CGSize(width: size[0], height: size[1])
                    }
                }
                #endif
                #endif
            }
            .task { await store.refreshAll() }
            // A challenge turned off (here or on another device) while its tab shows: back to Tiles.
            .onChange(of: challenges) { _, raw in
                if mode.isChallenge, !Challenges.decode(raw).contains(mode) { mode = .squares }
            }
            #if DEBUG
            .task { await plan.runDebugDemo(with: store) }
            .task { await runPreviewTour() }
            #endif
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await store.refreshAll() } }
            }
            .onChange(of: mode) {
                selectedArea = nil; selectedClimb = nil; selectedTrappist = nil; selectedKlompenpad = nil; selectedMTBRoute = nil
            }
            .onChange(of: plan.isPlanning) { _, planning in
                selectedArea = nil
                selectedClimb = nil
                selectedTrappist = nil
                selectedKlompenpad = nil
                selectedMTBRoute = nil
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
            ModeChips(modes: Challenges.visibleModes(challenges), selection: $mode, challenges: $challenges)
            HStack(alignment: .center, spacing: 10) {
                Text(statsText)
                    .font(.footnote.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if FeatureFlags.routePlanning {
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
                }
                Button {
                    showActivities = true
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.title3)
                }
                .accessibilityLabel("Activities")
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
        case .gemeenten:
            guard let areas = store.municipalityAreas else { return String(localized: "Loading municipalities…") }
            return String(localized: "\(store.visitedMunicipalities.count) / \(areas.all.count) municipalities visited")
        case .postcodes:
            guard let areas = store.postcodeAreas else { return String(localized: "Loading postcodes…") }
            return String(localized: "\(store.visitedPostcodes.count) / \(areas.all.count) postcodes visited")
        case .climbs:
            return String(localized: "\(store.climbed.count) climbs climbed · \(store.climbs.count) on the map")
        case .trappists:
            return String(localized: "\(store.trappistVisits.count) of \(store.trappists.count) Trappist breweries visited")
        case .klompenpaden:
            return String(localized: "\(store.klompenpadenWalked) of \(store.klompenpaden.count) Klompenpaden walked")
        case .mtb:
            return String(localized: "\(store.mtbRoutesRidden) of \(store.mtbRoutes.count) mountain bike routes ridden")
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
            if let error = store.regionsError, !store.isLoadingRegions {
                VStack(alignment: .leading, spacing: 8) {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .symbolRenderingMode(.multicolor)
                    if let detail = store.regionsErrorDetail {
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    Button("Try Again") { store.retryRegions() }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
            if store.isImporting, store.progress.total == 0 {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(store.importPhase ?? String(localized: "Checking your activities…")).font(.footnote)
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
            if !plan.isPlanning, let climb = selectedClimb {
                ClimbCard(climb: climb, climbed: store.climbed[climb.id] ?? [])
            }
            if !plan.isPlanning, let trappist = selectedTrappist {
                TrappistCard(trappist: trappist, visits: store.trappistVisits[trappist.id] ?? [])
            }
            if !plan.isPlanning, let path = selectedKlompenpad {
                KlompenpadCard(path: path, progress: store.klompenpadProgress[path.id] ?? 0)
            }
            if !plan.isPlanning, let route = selectedMTBRoute {
                MTBRouteCard(route: route, progress: store.mtbProgress[route.id] ?? 0)
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
                Text("Import .fit files, or connect Strava, to see where you have been.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("Import .fit files to see where you have been.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            VStack(spacing: 10) {
                Button {
                    pickerPurpose = .fitFiles
                    showPicker = true
                } label: {
                    Label("Import .fit Files…", systemImage: "doc.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
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

#if DEBUG
extension ContentView {
    /// App Store preview video: -PreviewTour YES plays a fixed tour while the simulator records
    /// (see Tools/record_app_preview.sh). Prints markers so the recording can be trimmed.
    func runPreviewTour() async {
        guard UserDefaults.standard.bool(forKey: "PreviewTour") else { return }
        _ = await store.loadedRegions()
        try? await Task.sleep(for: .seconds(6)) // map tiles and overlays finish drawing
        challenges = Challenges.encode(Set(Challenges.all))
        print("PREVIEW_TOUR_START \(Date.now.timeIntervalSince1970)")
        try? await Task.sleep(for: .seconds(3))
        mode = .gemeenten
        try? await Task.sleep(for: .seconds(2.5))
        mode = .postcodes
        try? await Task.sleep(for: .seconds(2.5))
        mode = .squares
        plan.isPlanning = true
        try? await Task.sleep(for: .seconds(1))
        await plan.planDemoRoute(with: store, pace: .milliseconds(400))
        try? await Task.sleep(for: .seconds(3.5))
        plan.isPlanning = false
        showStatistics = true
        try? await Task.sleep(for: .seconds(4))
        print("PREVIEW_TOUR_END \(Date.now.timeIntervalSince1970)")
    }
}
#endif

/// The map modes as chips that scroll sideways when they don't fit (five no longer fit a
/// segmented control on an iPhone).
private struct ModeChips: View {
    let modes: [MapMode]
    @Binding var selection: MapMode
    /// Challenges.key's value: which challenges are in the bar.
    @Binding var challenges: String

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(modes) { mode in
                        Button {
                            withAnimation(.snappy) { selection = mode }
                        } label: {
                            Text(mode.tabTitle)
                                .font(.subheadline.weight(selection == mode ? .semibold : .regular))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                // UIKit's label colours: SwiftUI's .secondary came out invisible
                                // inside this scroll view in the iPad side panel.
                                .foregroundStyle(Color(uiColor: selection == mode ? .label : .secondaryLabel))
                                .background(selection == mode ? AnyShapeStyle(.background) : AnyShapeStyle(.clear), in: Capsule())
                                .shadow(color: .black.opacity(selection == mode ? 0.12 : 0), radius: 2, y: 1)
                        }
                        .buttonStyle(.plain)
                        .id(mode)
                        .accessibilityAddTraits(selection == mode ? .isSelected : [])
                    }
                    challengesMenu
                }
                .padding(3)
            }
            .background(.quaternary.opacity(0.6), in: Capsule())
            .onChange(of: selection, initial: true) { _, mode in withAnimation { proxy.scrollTo(mode, anchor: .center) } }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Mode")
        }
    }

    /// Turns challenges on and off; a turned-off challenge that's showing switches the map to Tiles.
    private var challengesMenu: some View {
        Menu {
            Section("Challenges") {
                ForEach(Challenges.all) { mode in
                    Toggle(mode.title, isOn: Binding(
                        get: { Challenges.decode(challenges).contains(mode) },
                        set: { on in
                            var set = Challenges.decode(challenges)
                            if on { set.insert(mode) } else { set.remove(mode) }
                            withAnimation(.snappy) {
                                challenges = Challenges.encode(set)
                                if on { selection = mode } else if selection == mode { selection = .squares }
                            }
                        }))
                }
            }
        } label: {
            Image(systemName: "plus")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(uiColor: .secondaryLabel))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Capsule())
        }
        .accessibilityLabel("Challenges")
    }
}
