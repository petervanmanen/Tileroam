import SwiftUI

/// Statistics: countries and municipalities visited, Eddington numbers and totals per sport.
struct StatisticsView: View {
    @Environment(ActivityStore.self) private var store

    private var year: Int { Calendar.current.component(.year, from: .now) }

    var body: some View {
        let municipalities = store.regionCounts(.municipalities)
        let visitedCountries = Country.sortedByName.filter { (municipalities[$0.code]?.visited ?? 0) > 0 }
        List {
            Section("Overview") {
                LabeledContent("Countries visited", value: visitedCountries.count.formatted())
                LabeledContent("Municipalities visited", value: store.visitedMunicipalities.count.formatted())
                LabeledContent("Postcodes visited", value: store.visitedPostcodes.count.formatted())
                LabeledContent(TileZoom.explorer.title, value: store.tiles14.count.formatted())
                LabeledContent(TileZoom.squadratinho.title, value: store.tiles17.count.formatted())
            }

            Section {
                eddington(store.eddingtonCycling, symbol: "bicycle", title: String(localized: "Cycling")) { e in
                    Text("\(e.daysNeeded) more rides of at least \(e.number + 1) km to reach \(e.number + 1)")
                }
                eddington(store.eddingtonWalking, symbol: "figure.walk", title: String(localized: "Walking")) { e in
                    Text("\(e.daysNeeded) more walks of at least \(e.number + 1) km to reach \(e.number + 1)")
                }
                eddington(store.eddingtonRunning, symbol: "figure.run", title: String(localized: "Running")) { e in
                    Text("\(e.daysNeeded) more runs of at least \(e.number + 1) km to reach \(e.number + 1)")
                }
            } header: {
                Text("Eddington Number")
            } footer: {
                Text("The largest number E such that you covered at least E km on at least E days. Walking includes hikes.")
            }

            Section {
                if store.regions == nil {
                    HStack { ProgressView(); Text("Loading municipalities…") }
                } else if visitedCountries.isEmpty {
                    Text("No municipalities visited yet.").foregroundStyle(.secondary)
                }
                ForEach(visitedCountries) { country in
                    if let m = municipalities[country.code] {
                        countryRow(country, visited: m.visited, total: m.total)
                    }
                }
            } header: {
                Text("Municipalities per Country")
            } footer: {
                Text("Countries are counted as soon as you have an activity there. Postcodes are only available where their boundaries are open data. In the United Kingdom and Ireland, local authorities count as municipalities; in Andorra and San Marino, parishes and castelli.")
            }

            totals(title: String(localized: "This Year (\(String(year)))"),
                   activities: store.activities.filter { $0.startDate.map { Calendar.current.component(.year, from: $0) == year } ?? false })
            totals(title: String(localized: "All Time"), activities: store.activities)
        }
        .navigationTitle("Statistics")
    }

    // MARK: Rows

    private func eddington(_ e: Eddington, symbol: String, title: String,
                           detail: (Eddington) -> Text) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                detail(e)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(e.number.formatted())
                .font(.title2.bold())
                .monospacedDigit()
        }
    }

    private func countryRow(_ country: Country, visited: Int, total: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(country.flag) \(country.name)")
                Spacer()
                Text("\(visited) / \(total)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: Double(visited), total: Double(max(total, 1)))
                .tint(.green)
            Text((Double(visited) / Double(max(total, 1))).formatted(.percent.precision(.fractionLength(1))))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    // MARK: Totals per sport

    private struct Total {
        var count = 0
        var meters = 0.0
        var seconds = 0.0
    }

    @ViewBuilder
    private func totals(title: String, activities: [Activity]) -> some View {
        let bySport = Dictionary(grouping: activities, by: \.sport).mapValues { list in
            list.reduce(into: Total()) {
                $0.count += 1
                $0.meters += $1.distance
                $0.seconds += $1.movingTime ?? $1.elapsedTime ?? 0
            }
        }
        let all = bySport.values.reduce(into: Total()) {
            $0.count += $1.count
            $0.meters += $1.meters
            $0.seconds += $1.seconds
        }
        Section(title) {
            if activities.isEmpty {
                Text("No activities.").foregroundStyle(.secondary)
            } else {
                ForEach(bySport.sorted { $0.value.meters > $1.value.meters }, id: \.key) { sport, total in
                    totalRow(Label(Sport.name(sport), systemImage: Sport.symbol(sport)), total)
                }
                totalRow(Label("Total", systemImage: "sum").bold(), all)
            }
        }
    }

    private func totalRow(_ label: some View, _ total: Total) -> some View {
        LabeledContent {
            VStack(alignment: .trailing, spacing: 2) {
                Text(Measurement(value: total.meters / 1000, unit: UnitLength.kilometers)
                    .formatted(.measurement(width: .abbreviated, usage: .asProvided,
                                            numberFormatStyle: .number.precision(.fractionLength(0)))))
                    .monospacedDigit()
                Text(detail(total))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        } label: {
            label
        }
    }

    private func detail(_ total: Total) -> String {
        var parts = [String(localized: "\(total.count) activities")]
        if total.seconds > 0 {
            parts.append(Duration.seconds(total.seconds).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))
        }
        return parts.joined(separator: " · ")
    }
}
