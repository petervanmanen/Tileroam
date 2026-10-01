import SwiftUI
import WidgetKit

struct EddingtonEntry: TimelineEntry {
    let date: Date
    let cycling: Int
    let cyclingNeeded: Int
    let running: Int
    let runningNeeded: Int

    static let placeholder = EddingtonEntry(date: .now, cycling: 64, cyclingNeeded: 7, running: 21, runningNeeded: 3)

    static func load() -> EddingtonEntry {
        let d = UserDefaults(suiteName: "group.nl.petervanmanen.Tileroam")
        return EddingtonEntry(date: .now,
                              cycling: d?.integer(forKey: "eddington.cycling") ?? 0,
                              cyclingNeeded: d?.integer(forKey: "eddington.cycling.needed") ?? 1,
                              running: d?.integer(forKey: "eddington.running") ?? 0,
                              runningNeeded: d?.integer(forKey: "eddington.running.needed") ?? 1)
    }
}

struct EddingtonProvider: TimelineProvider {
    func placeholder(in context: Context) -> EddingtonEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (EddingtonEntry) -> Void) {
        completion(context.isPreview ? .placeholder : .load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<EddingtonEntry>) -> Void) {
        // The app reloads the timeline when the number changes.
        completion(Timeline(entries: [.load()], policy: .never))
    }
}

struct EddingtonWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: EddingtonEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "bicycle").font(.caption2)
                    Text(entry.cycling.formatted()).font(.title3.bold()).minimumScaleFactor(0.6)
                }
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label("Eddington", systemImage: "bicycle").font(.caption.bold())
                Text(entry.cycling.formatted()).font(.title2.bold())
                Text("\(entry.cyclingNeeded)× \(entry.cycling + 1) km to go").font(.caption2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .systemMedium:
            HStack(spacing: 16) {
                number(entry.cycling, label: "Cycling", symbol: "bicycle",
                       detail: Text("\(entry.cyclingNeeded) more rides of \(entry.cycling + 1) km"))
                Divider()
                number(entry.running, label: "Running", symbol: "figure.run",
                       detail: Text("\(entry.runningNeeded) more runs of \(entry.running + 1) km"))
                Spacer(minLength: 0)
            }
        default:
            VStack(alignment: .leading, spacing: 4) {
                Label("Eddington", systemImage: "bicycle")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(entry.cycling.formatted())
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(.green)
                Text("\(entry.cyclingNeeded) more rides of \(entry.cycling + 1) km")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func number(_ value: Int, label: LocalizedStringKey, symbol: String, detail: Text) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(label, systemImage: symbol).font(.caption.bold()).foregroundStyle(.secondary)
            Text(value.formatted())
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(.green)
            detail
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

struct EddingtonWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "EddingtonWidget", provider: EddingtonProvider()) { entry in
            EddingtonWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Eddington Number")
        .description("Your cycling Eddington number: E rides of at least E km.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

@main
struct TileroamWidgetBundle: WidgetBundle {
    var body: some Widget {
        EddingtonWidget()
        TilesWidget()
    }
}
