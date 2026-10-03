import SwiftUI

/// The climbs the user climbed, and those not climbed yet in the areas they ride.
struct ClimbsView: View {
    @Environment(ActivityStore.self) private var store
    @State private var showClimbed = true

    /// Hardest first: category, then gain.
    private func sorted(_ climbs: [Climb]) -> [Climb] {
        climbs.sorted { ($0.cat, $0.gain) > ($1.cat, $1.gain) }
    }

    var body: some View {
        let climbed = sorted(store.climbed.keys.compactMap { store.climbs[$0] })
        let open = sorted(store.climbs.values.filter { store.climbed[$0.id] == nil })
        List {
            Section {
                Picker("Show", selection: $showClimbed) {
                    Text("Climbed (\(climbed.count))").tag(true)
                    Text("Not yet (\(open.count))").tag(false)
                }
                .pickerStyle(.segmented)
            } footer: {
                if !showClimbed {
                    Text("Climbs in the areas where you ride and that you looked at on the map.")
                }
            }
            let shown = showClimbed ? climbed : open
            ForEach(Climb.Category.allCases.reversed(), id: \.self) { category in
                let items = shown.filter { $0.cat == category }
                if !items.isEmpty {
                    Section(category.title) {
                        ForEach(items.prefix(500)) { climb in
                            ClimbRow(climb: climb, climbed: store.climbed[climb.id] ?? [])
                        }
                    }
                }
            }
        }
        .overlay {
            if (showClimbed ? climbed : open).isEmpty {
                ContentUnavailableView(showClimbed ? "No Climbs Yet" : "No Climbs", systemImage: "mountain.2",
                                       description: Text("Climbs appear once your activities are checked against the climbs of their area, or when you look at the Climbs map."))
            }
        }
        .navigationTitle("Climbs")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ClimbRow: View {
    let climb: Climb
    let climbed: [Date]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(climb.title).font(.headline).lineLimit(1)
            Text(climb.details).font(.subheadline.monospacedDigit())
            if let last = climbed.first {
                Text(String(localized: "Climbed \(climbed.count) times, last on \(last.formatted(date: .abbreviated, time: .omitted))"))
                    .font(.footnote).foregroundStyle(.secondary)
            } else if let place = climb.place, climb.name != nil {
                Text(place).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
