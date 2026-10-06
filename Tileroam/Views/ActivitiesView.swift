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

struct TrappistCard: View {
    let trappist: Trappist
    let visits: [Date]

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let icon = trappist.icon {
                Image(uiImage: icon)
                    .resizable()
                    .scaledToFit()
                    .padding(4)
                    .frame(width: 52, height: 52)
                    .background(.white, in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(trappist.name).font(.headline).lineLimit(2)
                Text("\(trappist.abbey) · \(trappist.place)").font(.subheadline).foregroundStyle(.secondary)
                if let last = visits.first {
                    Text(String(localized: "Visited \(visits.count) times, last on \(last.formatted(date: .abbreviated, time: .omitted))"))
                        .font(.footnote).foregroundStyle(.green)
                } else {
                    Text("Not visited yet: ride within 200 m of the brewery").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct BoscafeCard: View {
    let boscafe: Boscafe
    let visits: [Date]

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(boscafe.emoji)
                .font(.system(size: 30))
                .frame(width: 52, height: 52)
                .background(.white, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(boscafe.name).font(.headline).lineLimit(2)
                Text(boscafe.place).font(.subheadline).foregroundStyle(.secondary)
                if let last = visits.first {
                    Text(String(localized: "Visited \(visits.count) times, last on \(last.formatted(date: .abbreviated, time: .omitted))"))
                        .font(.footnote).foregroundStyle(.green)
                } else {
                    Text("Not visited yet: ride or walk within 200 m of the boscafé").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct KlompenpadCard: View {
    let path: Klompenpad
    /// Share of the main route walked (0…1).
    let progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: progress >= KlompenpadMatcher.done ? "checkmark.circle.fill" : "shoeprints.fill")
                    .foregroundStyle(progress >= KlompenpadMatcher.done ? Color.green : .secondary)
                Text(path.name).font(.headline).lineLimit(1)
                Spacer()
                if let link = path.link {
                    Link("klompenpaden.nl", destination: link).font(.footnote)
                }
            }
            Text("From \(path.start) · \(path.lengthsText)").font(.subheadline).foregroundStyle(.secondary)
            ProgressView(value: min(progress, 1))
                .tint(progress >= KlompenpadMatcher.done ? .green : .orange)
            Text(progress >= KlompenpadMatcher.done ? String(localized: "Walked")
                 : progress > 0 ? String(localized: "\(Int((progress * 100).rounded()))% of the route walked")
                 : String(localized: "Not walked yet"))
                .font(.footnote)
                .foregroundStyle(progress >= KlompenpadMatcher.done ? .green : .secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct MTBRouteCard: View {
    let route: MTBRoute
    /// Share of the route ridden (0…1).
    let progress: Double

    var body: some View {
        let done = progress >= KlompenpadMatcher.done
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: done ? "checkmark.circle.fill" : "bicycle")
                    .foregroundStyle(done ? Color.green : .secondary)
                Text(route.name).font(.headline).lineLimit(2)
                Spacer()
                if let link = route.link {
                    Link("OpenStreetMap", destination: link).font(.footnote)
                }
            }
            Text("\(route.networkTitle) · \(Measurement(value: route.length / 1000, unit: UnitLength.kilometers).formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0)))))")
                .font(.subheadline).foregroundStyle(.secondary)
            ProgressView(value: min(progress, 1))
                .tint(done ? .green : .orange)
            HStack {
                Text(done ? String(localized: "Ridden")
                     : progress > 0 ? String(localized: "\(Int((progress * 100).rounded()))% of the route ridden")
                     : String(localized: "Not ridden yet"))
                    .font(.footnote)
                    .foregroundStyle(done ? .green : .secondary)
                Spacer()
                if let website = route.websiteLink {
                    Link("Website", destination: website).font(.footnote)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}
