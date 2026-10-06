import SwiftUI

/// Statistics: countries and municipalities visited, Eddington numbers, climbs, badges and totals
/// per sport. Each category is one row until tapped.
struct StatisticsView: View {
    @Environment(ActivityStore.self) private var store
    /// The categories the user opened; all start closed, as one small row each.
    @State private var expanded: Set<String> = []
    @State private var shownBadge: Badge?

    private var year: Int { Calendar.current.component(.year, from: .now) }

    var body: some View {
        let municipalities = store.regionCounts(.municipalities)
        let visitedCountries = Country.sortedByName.filter { (municipalities[$0.code]?.visited ?? 0) > 0 }
        let thisYear = store.activities.filter { $0.startDate.map { Calendar.current.component(.year, from: $0) == year } ?? false }
        List {
            category("overview", "Overview", summary: String(localized: "\(store.tiles(.explorer).count) tiles")) {
                // All countries of the world with activities (issue #38), not only those with municipalities.
                LabeledContent("Countries visited", value: store.worldCountries.count.formatted())
                LabeledContent("Municipalities visited", value: store.visitedMunicipalities.count.formatted())
                LabeledContent("Postcodes visited", value: store.visitedPostcodes.count.formatted())
                LabeledContent("Boscafés visited", value: store.boscafeVisits.count.formatted())
                LabeledContent("Ferries taken", value: store.ferryCrossings.count.formatted())
                LabeledContent("Klompenpaden walked", value: store.klompenpadenWalked.formatted())
                LabeledContent("Mountain bike routes ridden", value: store.mtbRoutesRidden.formatted())
                LabeledContent(TileZoom.explorer.title, value: store.tiles14.count.formatted())
            }

            category("eddington", "Eddington Number", summary: store.eddingtonCycling.number.formatted()) {
                eddington(store.eddingtonCycling, symbol: "bicycle", title: String(localized: "Cycling")) { e in
                    Text("\(e.daysNeeded) more rides of at least \(e.number + 1) km to reach \(e.number + 1)")
                }
                eddington(store.eddingtonWalking, symbol: "figure.walk", title: String(localized: "Walking")) { e in
                    Text("\(e.daysNeeded) more walks of at least \(e.number + 1) km to reach \(e.number + 1)")
                }
                eddington(store.eddingtonRunning, symbol: "figure.run", title: String(localized: "Running")) { e in
                    Text("\(e.daysNeeded) more runs of at least \(e.number + 1) km to reach \(e.number + 1)")
                }
            } footer: {
                Text("The largest number E such that you covered at least E km on at least E days. Walking includes hikes.")
            }

            if ClimbData.index != nil {
                category("climbs", "Climbs", summary: store.climbed.count.formatted()) {
                    let climbed = store.climbed.keys.compactMap { store.climbs[$0] }
                    LabeledContent("Climbs climbed", value: store.climbed.count.formatted())
                    ForEach(Climb.Category.allCases.reversed(), id: \.self) { category in
                        let count = climbed.count { $0.cat == category }
                        if count > 0 { LabeledContent(category.title, value: count.formatted()) }
                    }
                    NavigationLink("All Climbs") { ClimbsView() }
                } footer: {
                    Text("Climbs are found from elevation data along the roads; Cat 4 to HC as on Strava, and short steep hills. Gradients of short hills are often lower than signposted.")
                }
            }

            category("badges", "Badges", summary: String(localized: "\(store.badges.count) of \(Badge.allCases.count)")) {
                badgeGrid
            } footer: {
                Text("Badges in colour are yours; tap one to see what it takes. Indoor and virtual activities count too.")
            }

            category("municipalities", "Municipalities per Country", summary: store.visitedMunicipalities.count.formatted()) {
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
            } footer: {
                Text("Countries are counted as soon as you have an activity there. Postcodes are only available where their boundaries are open data. In the United Kingdom and Ireland, local authorities count as municipalities; in Andorra and San Marino, parishes and castelli.")
            }

            category("year", "This Year (\(String(year)))", summary: kilometres(thisYear)) {
                totals(thisYear)
            }
            category("all", "All Time", summary: kilometres(store.activities)) {
                totals(store.activities)
            }
        }
        .navigationTitle("Statistics")
        #if DEBUG
        // Screenshots: -StatisticsOpen "badges climbs" opens those categories.
        .onAppear {
            if let open = UserDefaults.standard.string(forKey: "StatisticsOpen") { expanded = Set(open.split(separator: " ").map(String.init)) }
        }
        #endif
    }

    // MARK: Categories

    /// A category of statistics: one row with its title and a summary, which opens on a tap.
    private func category<Content: View, Footer: View>(
        _ id: String, _ title: LocalizedStringKey, summary: String,
        @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer
    ) -> some View {
        let isOpen = expanded.contains(id)
        return Section {
            Button {
                withAnimation(.snappy) {
                    if isOpen { expanded.remove(id) } else { expanded.insert(id) }
                }
            } label: {
                HStack {
                    Text(title).font(.headline)
                    Spacer()
                    Text(summary).foregroundStyle(.secondary).monospacedDigit()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(summary)
            .accessibilityHint(isOpen ? "Closes this category" : "Opens this category")
            if isOpen { content() }
        } footer: {
            if isOpen { footer() }
        }
    }

    private func category<Content: View>(_ id: String, _ title: LocalizedStringKey, summary: String,
                                         @ViewBuilder content: () -> Content) -> some View {
        category(id, title, summary: summary, content: content) { EmptyView() }
    }

    // MARK: Badges

    private var badgeGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 12, alignment: .top)], spacing: 14) {
            ForEach(Badge.allCases) { badge in
                let count = store.badges[badge] ?? 0
                Button { shownBadge = badge } label: {
                    VStack(spacing: 4) {
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: UIImage(named: badge.imageName) ?? UIImage())
                                .resizable()
                                .scaledToFit()
                                .frame(width: 64, height: 64)
                                .saturation(count > 0 ? 1 : 0)
                                .opacity(count > 0 ? 1 : 0.45)
                            if count > 1 {
                                Text("×\(count)")
                                    .font(.caption2.bold())
                                    .monospacedDigit()
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(.tint, in: Capsule())
                                    .foregroundStyle(.white)
                                    .offset(x: 6, y: -4)
                            }
                        }
                        Text(badge.title)
                            .font(.caption2)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .foregroundStyle(count > 0 ? .primary : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(badge.title)
                .accessibilityValue(count == 0 ? String(localized: "Not earned yet") : String(localized: "Earned \(count) times"))
                .popover(isPresented: Binding(get: { shownBadge == badge }, set: { if !$0 { shownBadge = nil } })) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(badge.title).font(.headline)
                        Text(badge.goal).font(.subheadline)
                        Text(count == 0 ? String(localized: "Not earned yet") : String(localized: "Earned \(count) times"))
                            .font(.footnote)
                            .foregroundStyle(count > 0 ? .green : .secondary)
                        if badge == .globetrotter {
                            Text("\(store.worldCountries.count) of 50 countries so far").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .frame(idealWidth: 260)
                    .presentationCompactAdaptation(.popover)
                }
            }
        }
        .padding(.vertical, 6)
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

    private func kilometres(_ activities: [Activity]) -> String {
        Measurement(value: activities.reduce(0) { $0 + $1.distance } / 1000, unit: UnitLength.kilometers)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0))))
    }

    @ViewBuilder
    private func totals(_ activities: [Activity]) -> some View {
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
        if activities.isEmpty {
            Text("No activities.").foregroundStyle(.secondary)
        } else {
            ForEach(bySport.sorted { $0.value.meters > $1.value.meters }, id: \.key) { sport, total in
                totalRow(Label(Sport.name(sport), systemImage: Sport.symbol(sport)), total)
            }
            totalRow(Label("Total", systemImage: "sum").bold(), all)
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
