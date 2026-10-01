import SwiftUI

/// Introduction shown on first launch (and from Settings).
struct IntroView: View {
    @Environment(ActivityStore.self) private var store
    let onFinish: () -> Void

    @State private var page = 0
    @State private var showPicker = false
    @State private var pickerPurpose = PickerPurpose.source

    private enum Page: CaseIterable { case welcome, activities, strava, planning, ready }

    /// The Strava page only exists in builds with the Strava feature.
    private let pages = Page.allCases.filter { $0 != .strava || FeatureFlags.strava }
    private var pageCount: Int { pages.count }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                if page < pageCount - 1 {
                    Button("Skip", action: onFinish)
                        .padding()
                }
            }
            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                    view(for: page).tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if page < pageCount - 1 {
                    withAnimation { page += 1 }
                } else {
                    onFinish()
                }
            } label: {
                Text(page < pageCount - 1 ? "Next" : "Get Started")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: 520)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        // Opaque on its own: on iPad the full-screen cover can otherwise show the map through it.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground).ignoresSafeArea())
        .fileImporter(isPresented: $showPicker, allowedContentTypes: pickerPurpose.contentTypes,
                      allowsMultipleSelection: pickerPurpose.allowsMultipleSelection) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            switch pickerPurpose {
            case .export: Task { await store.selectExportFolder(url) }
            case .fitFiles: Task { await store.importFiles(urls) }
            default: Task { await store.addFolders(urls) }
            }
        }
    }

    // MARK: Pages

    @ViewBuilder
    private func view(for page: Page) -> some View {
        switch page {
        case .welcome: welcome
        case .activities: activities
        case .strava:
            #if STRAVA
            strava
            #else
            EmptyView()
            #endif
        case .planning: planning
        case .ready: ready
        }
    }

    private var saveFolderButton: some View {
        Button {
            pickerPurpose = .export
            showPicker = true
        } label: {
            Label(store.exportFolderName == nil ? String(localized: "Choose Save Folder…")
                                               : String(localized: "Save folder: \(store.exportFolderName ?? "")"),
                  systemImage: store.exportFolderName == nil ? "folder.badge.plus" : "checkmark.circle.fill")
        }
        .buttonStyle(.bordered)
    }

    private var welcome: some View {
        IntroPage(symbol: "map.fill", color: .green,
                  title: "Welcome to Tileroam",
                  text: "See everywhere you have been: every map tile, municipality and postcode area you have visited on your rides, runs and walks.") {
            VStack(alignment: .leading, spacing: 12) {
                feature("square.grid.3x3.fill", "Tiles (zoom 14) and squadratinhos (zoom 17), with your max square and cluster")
                feature("building.2.fill", "Municipalities and postcodes in 22 European countries")
                feature("bicycle", "Your Eddington number, also as a widget")
            }
        }
    }

    private var activities: some View {
        IntroPage(symbol: "folder.fill", color: .blue,
                  title: "Add Your Activities",
                  text: "Choose the iCloud Drive folder with your .fit files, for example exports from HealthFit, Garmin or Wahoo. Tileroam reads them in place and picks up new files automatically.") {
            VStack(spacing: 10) {
                Button {
                    pickerPurpose = .source
                    showPicker = true
                } label: {
                    Label(store.hasImportFolders ? String(localized: "Add Another Folder") : String(localized: "Choose Folder…"),
                          systemImage: "folder.badge.plus")
                }
                .buttonStyle(.bordered)
                Button {
                    pickerPurpose = .fitFiles
                    showPicker = true
                } label: {
                    Label("Import .fit Files…", systemImage: "doc.badge.plus")
                }
                .buttonStyle(.bordered)
                ForEach(store.importFolders) { folder in
                    Label(folder.name, systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                }
                Text("You can add more folders or change them later in Settings.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    #if STRAVA
    private var strava: some View {
        IntroPage(symbol: "arrow.triangle.2.circlepath", color: .orange,
                  title: "Connect Strava",
                  text: "Optionally connect Strava to download your full history with GPS. Activities are also saved as .fit files in a save folder of your choice, such as iCloud Drive › Tileroam.") {
            VStack(spacing: 10) {
                if let athlete = store.stravaAthlete {
                    Label(String(localized: "Connected as \(athlete)"), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if store.stravaConfig != nil {
                    StravaConnectButton()
                        .buttonStyle(.bordered)
                } else {
                    Text("Strava is not available in this version.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                saveFolderButton
                if let error = store.stravaError {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            }
        }
    }
    #endif

    private var planning: some View {
        IntroPage(symbol: "point.topleft.down.to.point.bottomright.curvepath", color: .purple,
                  title: "Plan Routes to New Places",
                  text: "Tap the route button, select unvisited tiles, municipalities or postcodes, and Tileroam plans the shortest cycling round trip from where you are. Export it as GPX for your bike computer.") {
            VStack(alignment: .leading, spacing: 12) {
                feature("hand.tap.fill", "Select as many places as you like, mixed types allowed")
                feature("arrow.triangle.turn.up.right.diamond.fill", "Routes follow cycle-friendly roads")
                feature("square.and.arrow.up", "Share as GPX or open an existing GPX to see what it would collect")
                if !FeatureFlags.strava {
                    saveFolderButton
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                }
            }
        }
    }

    private var ready: some View {
        IntroPage(symbol: "checkmark.seal.fill", color: .green,
                  title: "You're All Set",
                  text: "Switch between tiles, routes, municipalities and postcodes at the top of the map. Settings has your statistics, countries and folders.") {
            EmptyView()
        }
    }

    private func feature(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        Label {
            Text(text).font(.subheadline)
        } icon: {
            Image(systemName: symbol).foregroundStyle(.tint)
        }
    }
}

private struct IntroPage<Content: View>: View {
    let symbol: String
    let color: Color
    let title: LocalizedStringKey
    let text: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: symbol)
                    .font(.system(size: 64))
                    .foregroundStyle(color)
                    .padding(.top, 24)
                Text(title)
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text(text)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                content
                    .padding(.top, 8)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 48)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
    }
}
