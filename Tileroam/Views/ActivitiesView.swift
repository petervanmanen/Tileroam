import SwiftUI

/// All activities, newest first and grouped by month, with their duration, distance and average
/// power (from a power meter) or else average speed.
struct ActivitiesView: View {
    @Environment(ActivityStore.self) private var store
    @State private var toDelete: Activity?

    /// Months, newest first, each with its activities newest first. Activities without a date
    /// come last.
    private var months: [(title: String, activities: [Activity])] {
        let sorted = Self.newestFirst(store.activities)
        var result = [(title: String, activities: [Activity])]()
        for activity in sorted {
            let title = activity.startDate.map { $0.formatted(.dateTime.month(.wide).year()) }
                ?? String(localized: "Without date")
            if result.last?.title == title {
                result[result.count - 1].activities.append(activity)
            } else {
                result.append((title, [activity]))
            }
        }
        return result
    }

    static func newestFirst(_ activities: [Activity]) -> [Activity] {
        activities.sorted { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }
    }

    var body: some View {
        let months = months
        List {
            ForEach(months, id: \.title) { month in
                Section {
                    ForEach(month.activities) { activity in
                        ActivityRow(activity: activity)
                            .swipeActions {
                                Button("Delete", role: .destructive) { toDelete = activity }
                            }
                    }
                } header: {
                    Text(month.title)
                }
            }
        }
        .overlay {
            if store.activities.isEmpty {
                ContentUnavailableView("No Activities", systemImage: "list.bullet",
                                       description: Text("Add .fit files in Settings, or connect Strava."))
            }
        }
        .navigationTitle("Activities")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(toDelete.map { String(localized: "Delete “\($0.name)”?") } ?? "",
                            isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }),
                            titleVisibility: .visible, presenting: toDelete) { activity in
            Button("Delete Activity", role: .destructive) {
                Task { await store.delete(activity) }
            }
        } message: { _ in
            Text("It's deleted from Tileroam on this device and from iCloud, so your other devices remove it too. It stays on Strava and wherever you imported it from.")
        }
    }
}

private struct ActivityRow: View {
    let activity: Activity

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: Sport.symbol(activity.sport))
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(activity.name).font(.headline).lineLimit(1)
                    if activity.isVirtual == true {
                        Text("Indoor")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                    }
                }
                if let date = activity.startDate {
                    Text(date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(ActivityFormat.details(activity))
                    .font(.subheadline.monospacedDigit())
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// "1:23:45 · 42.3 km · 215 W" (or "· 28.4 km/h" without power).
enum ActivityFormat {
    static func details(_ a: Activity) -> String {
        var parts = [String]()
        if let duration = a.duration, duration > 0 { parts.append(self.duration(duration)) }
        if a.distance > 0 { parts.append(distance(a.distance)) }
        if let power = a.averagePower, power > 0 {
            parts.append(Measurement(value: power, unit: UnitPower.watts)
                .formatted(.measurement(width: .abbreviated, numberFormatStyle: .number.precision(.fractionLength(0)))))
        } else if let speed = a.averageSpeed {
            parts.append(Measurement(value: speed, unit: UnitSpeed.metersPerSecond).converted(to: .kilometersPerHour)
                .formatted(.measurement(width: .abbreviated, usage: .asProvided,
                                        numberFormatStyle: .number.precision(.fractionLength(1)))))
        }
        return parts.joined(separator: " · ")
    }

    /// "1:23:45", or "42:10" under an hour.
    static func duration(_ seconds: Double) -> String {
        Duration.seconds(seconds.rounded())
            .formatted(.time(pattern: seconds >= 3600 ? .hourMinuteSecond : .minuteSecond))
    }

    static func distance(_ meters: Double) -> String {
        Measurement(value: meters / 1000, unit: UnitLength.kilometers)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided,
                                    numberFormatStyle: .number.precision(.fractionLength(1))))
    }
}

/// A tapped climb on the map: what it is and when the user climbed it.
struct ClimbCard: View {
    let climb: Climb
    let climbed: [Date]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: climbed.isEmpty ? "mountain.2" : "checkmark.circle.fill")
                    .foregroundStyle(climbed.isEmpty ? Color.secondary : .green)
                Text(climb.title).font(.headline).lineLimit(1)
                Spacer()
                Text(climb.cat.title)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
            Text(climb.details).font(.subheadline.monospacedDigit())
            Text(String(localized: "Steepest \((climb.max / 100).formatted(.percent.precision(.fractionLength(0)))) · top at \(Int(climb.top)) m"))
                .font(.footnote).foregroundStyle(.secondary)
            if let last = climbed.first {
                Text(String(localized: "Climbed \(climbed.count) times, last on \(last.formatted(date: .abbreviated, time: .omitted))"))
                    .font(.footnote).foregroundStyle(.green)
            } else {
                Text("Not climbed yet").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

/// A tapped place or route of a challenge of the user: what it is, and when the user visited it
/// or how much of it they covered.
struct ChallengeItemCard: View {
    let challenge: CustomChallenge
    let item: ChallengeItem
    let progress: ChallengeProgress

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(item.icon ?? challenge.icon)
                .font(.system(size: 30))
                .frame(width: 52, height: 52)
                .background(.white, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name).font(.headline).lineLimit(2)
                if !details.isEmpty {
                    Text(details).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
                if let difficulty = item.difficulty { DifficultyBadge(difficulty: difficulty) }
                if challenge.isCoverRoutes {
                    let share = progress.coverage[item.id] ?? 0, done = share >= challenge.coverage
                    ProgressView(value: min(share, 1)).tint(done ? .green : .orange)
                    Text(done ? String(localized: "Completed")
                         : share > 0 ? String(localized: "\(Int((share * 100).rounded()))% of the route covered")
                         : String(localized: "Not started yet: cover \(Int((challenge.coverage * 100).rounded()))% of the route"))
                        .font(.footnote)
                        .foregroundStyle(done ? .green : .secondary)
                } else if let visits = progress.visits[item.id], let last = visits.first {
                    Text(challenge.kind == .locations
                         ? String(localized: "Visited \(visits.count) times, last on \(last.formatted(date: .abbreviated, time: .omitted))")
                         : String(localized: "Crossed \(visits.count) times, last on \(last.formatted(date: .abbreviated, time: .omitted))"))
                        .font(.footnote).foregroundStyle(.green)
                } else {
                    Text(challenge.kind == .locations
                         ? String(localized: "Not visited yet: pass within \(Int(challenge.radius)) m")
                         : String(localized: "Not crossed yet: go from one end to the other"))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let link = item.link {
                    Link(link.host(percentEncoded: false) ?? link.absoluteString, destination: link).font(.footnote).lineLimit(1)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    /// "Subtitle · 12 km"
    private var details: String {
        var parts = item.subtitle.map { [$0] } ?? []
        if item.length >= 1000 {
            parts.append(Measurement(value: item.length / 1000, unit: UnitLength.kilometers)
                .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0...1)))))
        } else if item.length > 0 {
            parts.append(Measurement(value: item.length, unit: UnitLength.meters).formatted(.measurement(width: .abbreviated, usage: .road)))
        }
        return parts.joined(separator: " · ")
    }
}

/// A route's difficulty in the usual colours: green, blue, red, black.
struct DifficultyBadge: View {
    let difficulty: ChallengeItem.Difficulty

    var body: some View {
        Text(difficulty.title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Self.color(difficulty), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(difficulty == .veryHard ? 0.6 : 0), lineWidth: 1))
    }

    static func color(_ difficulty: ChallengeItem.Difficulty) -> Color {
        switch difficulty {
        case .easy: .green
        case .moderate: .blue
        case .hard: .red
        case .veryHard: .black
        }
    }
}
