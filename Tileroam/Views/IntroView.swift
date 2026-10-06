import SwiftUI

/// Introduction shown on first launch (and from Settings).
struct IntroView: View {
    @Environment(ActivityStore.self) private var store
    let onFinish: () -> Void

    @State private var page = 0
    @State private var showPicker = false
    private enum Page: CaseIterable { case welcome, activities, strava, planning, ready }

    /// The Strava page only exists in builds with the Strava feature. On a further device, where
    /// iCloud already has the activities, there's nothing to set up: no import or Strava page.
    private var pages: [Page] {
        Page.allCases.filter { page in
            if page == .strava && !FeatureFlags.strava { return false }
            if store.iCloudHasActivities && store.isICloudSyncOn && (page == .activities || page == .strava) { return false }
            return true
        }
    }
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
        .fileImporter(isPresented: $showPicker, allowedContentTypes: PickerPurpose.fitFiles.contentTypes,
                      allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result, !urls.isEmpty else { return }
            Task { await store.importFiles(urls) }
        }
        .onChange(of: pageCount) { if page >= pageCount { page = pageCount - 1 } }
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

    private var welcome: some View {
        IntroPage(symbol: "map.fill", color: .green,
                  title: "Welcome to Tileroam",
                  text: "See everywhere you have been, and take on challenges with your rides, runs and walks.") {
            VStack(alignment: .leading, spacing: 12) {
                feature("square.grid.3x3.fill", "Map tiles, with your max square and cluster")
                feature("building.2.fill", "Challenges: municipalities and postcodes in the Netherlands, Belgium, Luxembourg, Germany, France, Switzerland and Austria")
                feature("mountain.2.fill", "Climbs from short steep hills to HC, and the ones you climbed")
                feature("mug.fill", "The Trappist Challenge: ride past the Trappist breweries")
                feature("tree.fill", "The Boscafé Challenge: visit the cafés in the woods")
                feature("shoeprints.fill", "Klompenpaden: walk the 167 country paths of Gelderland and Utrecht")
                feature("bicycle", "Mountain bike routes: the signposted MTB routes of OpenStreetMap")
                feature("rosette", "18 badges, from 100! and Everester to Festive 500 and Globetrotter")
                feature("bicycle", "Your Eddington number, also as a widget")
                if store.iCloudHasActivities && store.isICloudSyncOn {
                    feature("icloud.fill", "Your activities come from iCloud, from your other devices")
                }
            }
        }
    }

    private var activities: some View {
        IntroPage(symbol: "folder.fill", color: .blue,
                  title: "Add Your Activities",
                  text: "Import your .fit files, for example exports from HealthFit, Garmin or Wahoo: separate files or a whole folder. Tileroam keeps its own copy, and with iCloud your other devices have them too.") {
            VStack(spacing: 10) {
                Button {
                    showPicker = true
                } label: {
                    Label("Import .fit Files…", systemImage: "doc.badge.plus")
                }
                .buttonStyle(.bordered)
                if store.libraryFileCount > 0 {
                    Label(String(localized: "\(store.libraryFileCount) activities"), systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                }
                Text("You can import more later in Settings.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    #if STRAVA
    private var strava: some View {
        IntroPage(symbol: "arrow.triangle.2.circlepath", color: .orange,
                  title: "Connect Strava",
                  text: "Optionally connect Strava to download your full history with GPS. Activities are saved as .fit files in Tileroam and, with iCloud, on your other devices.") {
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
                  text: "Tap the route button, select unvisited tiles, municipalities, postcodes, climbs, Trappist breweries or boscafés, and Tileroam plans the shortest cycling round trip from where you are. Export it as GPX for your bike computer.") {
            VStack(alignment: .leading, spacing: 12) {
                feature("hand.tap.fill", "Select as many places as you like, mixed types allowed")
                feature("arrow.triangle.turn.up.right.diamond.fill", "Routes follow cycle-friendly roads")
                feature("square.and.arrow.up", "Share as GPX or open an existing GPX to see what it would collect")
            }
        }
    }

    private var ready: some View {
        IntroPage(symbol: "checkmark.seal.fill", color: .green,
                  title: "You're All Set",
                  text: "Tiles are at the top of the map; add the challenges you like with the +. The chart button has your statistics and badges, Settings your iCloud sync and imports.") {
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
