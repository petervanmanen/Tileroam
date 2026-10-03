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
