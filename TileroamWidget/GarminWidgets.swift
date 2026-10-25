import SwiftUI
import WidgetKit

// MARK: - Timeline

struct GarminEntry: TimelineEntry {
    enum State { case ready(GarminHealth), notConnected, invalidKey, unavailable }

    let date: Date
    let state: State

    static let placeholder = GarminEntry(date: .now, state: .ready(GarminHealth(
        sleep: .init(date: GarminHealthStore.day(.now), seconds: 7 * 3600 + 32 * 60, score: 84),
        steps: .init(date: GarminHealthStore.day(.now), count: 6_240, goal: 8_000),
        bodyBattery: .init(level: 72, time: .now), fetched: .now)))
}

/// One fetch for all Garmin widgets: they ask at about the same time, and Garmin is asked once.
actor GarminLoader {
    static let shared = GarminLoader()
    private var running: Task<Result<GarminHealth, GarminHealthStore.Failure>, Never>?

    func current() async -> Result<GarminHealth, GarminHealthStore.Failure> {
        if let running { return await running.value }
        let task = Task { await GarminHealthStore.current() }
        running = task
        defer { running = nil }
        return await task.value
    }
}

struct GarminProvider: TimelineProvider {
    func placeholder(in context: Context) -> GarminEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (GarminEntry) -> Void) {
        if context.isPreview, GarminHealthStore.cached == nil { return completion(.placeholder) }
        Task { completion(await Self.entry()) }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<GarminEntry>) -> Void) {
        Task {
            let entry = await Self.entry()
            // Steps and Body Battery change during the day: ask again in 20 minutes (WidgetKit
            // spaces it out further when it wants to). Without a key, the app reloads the widgets.
            let policy: TimelineReloadPolicy = if case .notConnected = entry.state { .never } else { .after(.now + 20 * 60) }
            completion(Timeline(entries: [entry], policy: policy))
        }
    }

    static func entry() async -> GarminEntry {
        switch await GarminLoader.shared.current() {
        case .success(let health): GarminEntry(date: .now, state: .ready(health))
        case .failure(.notConnected): GarminEntry(date: .now, state: .notConnected)
        case .failure(.invalidKey): GarminEntry(date: .now, state: .invalidKey)
        case .failure(.unavailable): GarminEntry(date: .now, state: .unavailable)
        }
    }
}

// MARK: - Views

/// The common frame of the Garmin widgets: the numbers, or what's missing.
struct GarminWidgetView<Content: View>: View {
    @Environment(\.widgetFamily) private var family
    let entry: GarminEntry
    let title: LocalizedStringKey
    let symbol: String
    @ViewBuilder let content: (GarminHealth) -> Content

    var body: some View {
        switch entry.state {
        case .ready(let health):
            content(health)
        default:
            if family == .accessoryCircular {
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: symbol)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Label(title, systemImage: symbol).font(.caption.bold()).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Text(message).font(family == .systemSmall ? .footnote : .caption2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var message: LocalizedStringKey {
        switch entry.state {
        case .invalidKey: "Garmin didn't accept the key: connect again in Tileroam."
        case .unavailable: "Garmin Connect can't be reached right now."
        default: "Connect Garmin in Tileroam's settings."
        }
    }
}

/// A big number with a title, for the small home screen widget.
private struct BigNumber<Detail: View>: View {
    let title: LocalizedStringKey
    let symbol: String
    let value: String
    let color: Color
    @ViewBuilder let detail: () -> Detail

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol).font(.caption.bold()).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(value)
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundStyle(color)
            detail().font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum GarminFormat {
    /// "7 h 32 min".
    static func duration(_ seconds: Int) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    /// Garmin's colours for the sleep score: excellent 90+, good 80+, fair 60+, poor.
    static func sleepColor(_ score: Int) -> Color {
        switch score {
        case 90...: .blue
        case 80..<90: .teal
        case 60..<80: .orange
        default: .red
        }
    }

    static func batteryColor(_ level: Int) -> Color {
        switch level {
        case 76...: .blue
        case 51...75: .teal
        case 26...50: .orange
        default: .red
        }
    }
}

// MARK: - Sleep

struct GarminSleepView: View {
    @Environment(\.widgetFamily) private var family
    let entry: GarminEntry

    var body: some View {
        GarminWidgetView(entry: entry, title: "Sleep", symbol: "bed.double.fill") { health in
            if let sleep = health.sleep {
                let duration = GarminFormat.duration(sleep.seconds)
                switch family {
                case .accessoryCircular:
                    if let score = sleep.score {
                        Gauge(value: Double(score), in: 0...100) {
                            Image(systemName: "bed.double.fill")
                        } currentValueLabel: {
                            Text(score.formatted())
                        }
                        .gaugeStyle(.accessoryCircular)
                    } else {
                        ZStack {
                            AccessoryWidgetBackground()
                            Text(duration).font(.caption2.bold()).multilineTextAlignment(.center).minimumScaleFactor(0.6)
                        }
                    }
                case .accessoryRectangular:
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Sleep", systemImage: "bed.double.fill").font(.caption.bold())
                        if let score = sleep.score {
                            Text("Score \(score)").font(.title3.bold())
                        }
                        Text(duration).font(.caption)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                case .accessoryInline:
                    if let score = sleep.score {
                        Label("\(score) · \(duration)", systemImage: "bed.double.fill")
                    } else {
                        Label(duration, systemImage: "bed.double.fill")
                    }
                default:
                    BigNumber(title: "Sleep", symbol: "bed.double.fill",
                              value: sleep.score?.formatted() ?? duration,
                              color: sleep.score.map(GarminFormat.sleepColor) ?? .indigo) {
                        if sleep.score != nil { Text(duration) }
                        if sleep.date != GarminHealthStore.day(entry.date) { Text("Last night with data") }
                    }
                }
            } else {
                GarminNoData(title: "Sleep", symbol: "bed.double.fill", message: "No sleep from last night yet.")
            }
        }
    }
}

// MARK: - Steps

struct GarminStepsView: View {
    @Environment(\.widgetFamily) private var family
    let entry: GarminEntry

    var body: some View {
        GarminWidgetView(entry: entry, title: "Steps", symbol: "figure.walk") { health in
            // Steps from another day are none today.
            let steps = health.steps.flatMap { $0.date == GarminHealthStore.day(entry.date) ? $0 : nil }
            let count = steps?.count ?? 0
            let goal = steps?.goal ?? 0
            switch family {
            case .accessoryCircular:
                if goal > 0 {
                    Gauge(value: Double(min(count, goal)), in: 0...Double(goal)) {
                        Image(systemName: "figure.walk")
                    } currentValueLabel: {
                        Text(count.formatted(.number.notation(.compactName)))
                    }
                    .gaugeStyle(.accessoryCircular)
                } else {
                    ZStack {
                        AccessoryWidgetBackground()
                        VStack(spacing: 0) {
                            Image(systemName: "figure.walk").font(.caption2)
                            Text(count.formatted(.number.notation(.compactName))).font(.title3.bold()).minimumScaleFactor(0.6)
                        }
                    }
                }
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Label("Steps", systemImage: "figure.walk").font(.caption.bold())
                    Text(count.formatted()).font(.title2.bold())
                    if goal > 0 { Text("Goal \(goal.formatted())").font(.caption2) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            case .accessoryInline:
                Label(count.formatted(), systemImage: "figure.walk")
            default:
                BigNumber(title: "Steps", symbol: "figure.walk", value: count.formatted(),
                          color: goal > 0 && count >= goal ? .green : .primary) {
                    if goal > 0 {
                        ProgressView(value: Double(min(count, goal)), total: Double(goal)).tint(.green)
                        Text("Goal \(goal.formatted())")
                    }
                }
            }
        }
    }
}

// MARK: - Body Battery

struct GarminBodyBatteryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: GarminEntry

    var body: some View {
        GarminWidgetView(entry: entry, title: "Body Battery", symbol: "bolt.heart.fill") { health in
            if let battery = health.bodyBattery {
                let color = GarminFormat.batteryColor(battery.level)
                switch family {
                case .accessoryCircular:
                    Gauge(value: Double(battery.level), in: 0...100) {
                        Image(systemName: "bolt.heart.fill")
                    } currentValueLabel: {
                        Text(battery.level.formatted())
                    }
                    .gaugeStyle(.accessoryCircular)
                case .accessoryRectangular:
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Body Battery", systemImage: "bolt.heart.fill").font(.caption.bold())
                        Text(battery.level.formatted()).font(.title2.bold())
                        if let time = battery.time { Text(time, style: .time).font(.caption2) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                case .accessoryInline:
                    Label(battery.level.formatted(), systemImage: "bolt.heart.fill")
                default:
                    BigNumber(title: "Body Battery", symbol: "bolt.heart.fill", value: battery.level.formatted(), color: color) {
                        ProgressView(value: Double(battery.level), total: 100).tint(color)
                        if let time = battery.time { Text(time, style: .time) }
                    }
                }
            } else {
                GarminNoData(title: "Body Battery", symbol: "bolt.heart.fill", message: "No Body Battery yet today.")
            }
        }
    }
}

/// Connected, but Garmin has no number (yet).
private struct GarminNoData: View {
    @Environment(\.widgetFamily) private var family
    let title: LocalizedStringKey
    let symbol: String
    let message: LocalizedStringKey

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: symbol)
            }
        case .accessoryInline:
            Label("–", systemImage: symbol)
        default:
            VStack(alignment: .leading, spacing: 4) {
                Label(title, systemImage: symbol).font(.caption.bold()).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(message).font(.footnote).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Widgets

/// The sizes of the Garmin widgets: none in builds without Garmin, so they aren't in the gallery.
private var garminFamilies: [WidgetFamily] {
    GarminHealthStore.isOffered ? [.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline] : []
}

struct GarminSleepWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "GarminSleepWidget", provider: GarminProvider()) { entry in
            GarminSleepView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Sleep")
        .description("Last night's sleep score and duration from Garmin Connect.")
        .supportedFamilies(garminFamilies)
    }
}

struct GarminStepsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "GarminStepsWidget", provider: GarminProvider()) { entry in
            GarminStepsView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Steps")
        .description("Today's steps from Garmin Connect.")
        .supportedFamilies(garminFamilies)
    }
}

struct GarminBodyBatteryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "GarminBodyBatteryWidget", provider: GarminProvider()) { entry in
            GarminBodyBatteryView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Body Battery")
        .description("Your current Body Battery from Garmin Connect.")
        .supportedFamilies(garminFamilies)
    }
}
