import MapKit
import SwiftUI

/// Statistics → "Tile history video": renders it (see `TileVideo`) and offers it to share or save.
struct TileVideoView: View {
    @Environment(ActivityStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var progress: Double?
    @State private var video: URL?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "film.stack")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)
                Text("Your tiles, in the order you first visited them, on the map of the country with your largest cluster.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                if let video {
                    ShareLink(item: video) {
                        Label("Share or Save Video", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                } else if let progress {
                    ProgressView(value: progress) {
                        Text("Making the video…")
                    }
                } else {
                    Button {
                        Task { await render() }
                    } label: {
                        Label("Make Video", systemImage: "play.rectangle")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.tiles14.isEmpty)
                }
                if let error {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            }
            .padding(24)
            .frame(maxWidth: 500)
            .navigationTitle("Tile History Video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func render() async {
        error = nil
        progress = 0
        let history = TileHistory(activities: store.activities)
        do {
            video = try await TileVideo.render(history) { value in
                Task { @MainActor in progress = value }
            }
        } catch {
            self.error = error.localizedDescription
        }
        progress = nil
    }
}

/// Statistics → "Year in review": a year's card to share as an image (see `YearInReview`).
struct YearInReviewView: View {
    @Environment(ActivityStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var year: Int?
    @State private var image: UIImage?
    @State private var isMaking = false

    var body: some View {
        let years = YearInReview.years(store.activities)
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if years.count > 1 {
                        Picker("Year", selection: Binding(get: { year ?? years.first ?? 0 }, set: { year = $0 })) {
                            ForEach(years, id: \.self) { Text(String($0)).tag($0) }
                        }
                        .pickerStyle(.menu)
                    }
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .shadow(radius: 4)
                        ShareLink(item: Image(uiImage: image), preview: SharePreview("Tileroam \(String(year ?? 0))", image: Image(uiImage: image))) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.borderedProminent)
                    } else if isMaking {
                        ProgressView()
                            .padding(40)
                    } else if years.isEmpty {
                        Text("No activities yet.").foregroundStyle(.secondary)
                    }
                }
                .padding()
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Year in Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .task(id: year ?? years.first) {
                guard let shown = year ?? years.first else { return }
                year = shown
                await make(shown)
            }
        }
    }

    private func make(_ shown: Int) async {
        isMaking = true
        image = nil
        defer { isMaking = false }
        let activities = store.activities
        let review = await Task.detached(priority: .userInitiated) {
            YearInReview(year: shown, activities: activities, history: TileHistory(activities: activities))
        }.value
        let map = await YearInReviewCard.mapImage(review)
        guard year == shown else { return }
        let renderer = ImageRenderer(content: YearInReviewCard(review: review, map: map))
        renderer.scale = 1
        image = renderer.uiImage
    }
}

/// The year in review as an image: 1080 × 1350, the year's new tiles on the map and its numbers.
struct YearInReviewCard: View {
    let review: YearInReview
    let map: UIImage?

    static let size = CGSize(width: 1080, height: 1350)
    static let mapSize = CGSize(width: 1000, height: 640)

    /// The map around the year's new tiles (orange), with the earlier ones in green.
    static func mapImage(_ review: YearInReview) async -> UIImage? {
        let shown = review.newTiles.isEmpty ? Array(review.earlierTiles) : review.newTiles
        guard !shown.isEmpty else { return nil }
        let region = TileHistory.region(around: shown, aspect: mapSize.width / mapSize.height)
        guard let map = try? await TileMapImage.make(region: region, size: mapSize) else { return nil }
        let earlier = review.earlierTiles, new = review.newTiles
        return UIGraphicsImageRenderer(size: mapSize, format: .init(for: .init(displayScale: 1))).image { _ in
            map.snapshot.image.draw(at: .zero)
            UIColor.systemGreen.withAlphaComponent(0.45).setFill()
            for key in earlier { UIRectFillUsingBlendMode(map.rect(key).insetBy(dx: 0.5, dy: 0.5), .normal) }
            UIColor.systemOrange.withAlphaComponent(0.85).setFill()
            for key in new { UIRectFillUsingBlendMode(map.rect(key).insetBy(dx: 0.5, dy: 0.5), .normal) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: String(review.year)).font(.system(size: 96, weight: .heavy))
                Spacer()
                Text("Tileroam").font(.system(size: 40, weight: .semibold)).foregroundStyle(.secondary)
            }
            if let map {
                Image(uiImage: map)
                    .resizable()
                    .frame(width: Self.mapSize.width, height: Self.mapSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
            }
            Grid(alignment: .leading, horizontalSpacing: 40, verticalSpacing: 18) {
                GridRow {
                    number(review.newTiles.count, "new tiles", color: .orange)
                    number(review.activities, "activities")
                    number(Int(review.distanceKm.rounded()), "km")
                }
                GridRow {
                    number(review.maxSquare.after, "max square", detail: change(review.maxSquare))
                    number(review.newMunicipalities, "new municipalities")
                    number(review.newPostcodes, "new postcodes")
                }
                GridRow {
                    number(review.eddington.after, "Eddington", detail: change(review.eddington))
                    number(review.newClimbs, "climbs first climbed")
                    number(review.newCountries.count, "new countries")
                }
            }
            Text(extras).font(.system(size: 30)).foregroundStyle(.secondary).lineLimit(3)
            Spacer(minLength: 0)
        }
        .padding(40)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(Color.white)
        .foregroundStyle(.black)
        .environment(\.colorScheme, .light)
    }

    private func change(_ value: (before: Int, after: Int)) -> String? {
        value.after > value.before ? "+\(value.after - value.before)" : nil
    }

    private func number(_ value: Int, _ label: LocalizedStringKey, detail: String? = nil, color: Color = .black) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(value.formatted()).font(.system(size: 64, weight: .bold)).foregroundStyle(color)
                if let detail { Text(verbatim: detail).font(.system(size: 30, weight: .semibold)).foregroundStyle(.green) }
            }
            Text(label).font(.system(size: 28)).foregroundStyle(.secondary)
        }
    }

    /// "3 Trappist breweries · 5 boscafés · 12 ferries · Badges: Century, Everester"
    private var extras: String {
        var parts = [String]()
        if review.newTrappists > 0 { parts.append(String(localized: "\(review.newTrappists) Trappist breweries")) }
        if review.newBoscafes > 0 { parts.append(String(localized: "\(review.newBoscafes) boscafés")) }
        if review.newFerries > 0 { parts.append(String(localized: "\(review.newFerries) ferries")) }
        if !review.badges.isEmpty {
            parts.append(String(localized: "Badges: \(review.badges.map(\.title).formatted(.list(type: .and)))"))
        }
        return parts.joined(separator: " · ")
    }
}

#if DEBUG
/// Simulator check: -RecapDemo YES writes the tile video and this year's card to the app's
/// Documents folder once the activities are read ("RECAP_DEMO <path>" in the log).
enum RecapDemo {
    @MainActor
    static func run(_ store: ActivityStore) async {
        guard UserDefaults.standard.bool(forKey: "RecapDemo") else { return }
        while store.isImporting || store.activities.isEmpty || store.tiles14.isEmpty { try? await Task.sleep(for: .seconds(1)) }
        let folder = URL.documentsDirectory
        let activities = store.activities
        let history = TileHistory(activities: activities)
        if let year = YearInReview.years(activities).first {
            let review = YearInReview(year: year, activities: activities, history: history)
            let renderer = ImageRenderer(content: YearInReviewCard(review: review, map: await YearInReviewCard.mapImage(review)))
            renderer.scale = 1
            if let data = renderer.uiImage?.pngData() {
                try? data.write(to: folder.appending(path: "recap-year.png"))
                print("RECAP_DEMO \(folder.appending(path: "recap-year.png").path(percentEncoded: false))")
            }
        }
        if let url = try? await TileVideo.render(history, progress: { _ in }) {
            let target = folder.appending(path: "recap-tiles.mp4")
            try? FileManager.default.removeItem(at: target)
            try? FileManager.default.moveItem(at: url, to: target)
            print("RECAP_DEMO \(target.path(percentEncoded: false))")
        }
    }
}
#endif
