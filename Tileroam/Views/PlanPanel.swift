import SwiftUI

/// Bottom panel of the route planning mode.
struct PlanPanel: View {
    @Environment(ActivityStore.self) private var store
    @Environment(PlanStore.self) private var plan
    @AppStorage("tileZoom") private var tileZoom: TileZoom = .explorer
    let onOpenGPX: () -> Void
    @State private var showStartPicker = false
    @State private var showEndPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let route = plan.route {
                routeContent(route)
            } else {
                selectionContent
            }
            if plan.isWorking, let status = plan.status {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(status).font(.footnote)
                    Spacer(minLength: 4)
                    Button("Stop", role: .cancel) { plan.stopPlanning() }
                        .font(.footnote)
                }
            }
            if let error = plan.error {
                Label(error, systemImage: plan.waitingForWiFi != nil ? "wifi" : "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .symbolRenderingMode(.multicolor)
                if plan.waitingForWiFi != nil {
                    Button("Download Anyway") { Task { await plan.downloadAnyway(with: store) } }
                        .font(.footnote)
                }
            }
            if let message = plan.message {
                Label(message, systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.green)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .sheet(isPresented: $showStartPicker) {
            StartPicker()
                .environment(store).environment(plan)
        }
        .sheet(isPresented: $showEndPicker) {
            StartPicker(kind: .end)
                .environment(store).environment(plan)
        }
        #if DEBUG
        // Screenshots: -ShowStartPicker YES opens the starting point picker.
        .onAppear { if UserDefaults.standard.bool(forKey: "ShowStartPicker") { showStartPicker = true } }
        #endif
    }

    /// "Start: My Location"; opens the starting point picker.
    private var startButton: some View {
        Button {
            showStartPicker = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: plan.start == nil ? "location.fill" : "flag.fill")
                    .foregroundStyle(plan.start == nil ? Color.accentColor : .green)
                if let start = plan.start {
                    Text("Start: \(start.name)").lineLimit(1)
                } else {
                    Text("Start: My Location")
                }
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .font(.subheadline)
        }
        .buttonStyle(.plain)
        .disabled(plan.isWorking)
        .accessibilityHint("Choose where the route starts")
    }

    /// "End: Back to Start" (a round trip) or "End: <place>" (point to point); opens the picker.
    private var endButton: some View {
        Button {
            showEndPicker = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: plan.end == nil ? "arrow.triangle.turn.up.right.circle" : "flag.checkered")
                    .foregroundStyle(plan.end == nil ? Color.secondary : .red)
                if let end = plan.end {
                    Text("End: \(end.name)").lineLimit(1)
                } else {
                    Text("End: Back to Start")
                }
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .font(.subheadline)
        }
        .buttonStyle(.plain)
        .disabled(plan.isWorking)
        .accessibilityHint("Choose a round trip or where the route ends")
    }

    private var selectionContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(plan.selectionSummary).font(.headline)
            startButton
            endButton
            Group {
                if plan.end == nil {
                    Text("Tap unvisited tiles, municipalities or postcodes to add them. The route starts and ends at the starting point; long-press the map to start or end there.")
                } else {
                    Text("Tap unvisited tiles, municipalities or postcodes to add them. The route goes from the start to the end; drag the flags to move them.")
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            HStack {
                Button {
                    Task { await plan.plan(with: store) }
                } label: {
                    Label("Plan Route", systemImage: "bicycle")
                }
                .buttonStyle(.borderedProminent)
                .disabled((plan.selected.isEmpty && plan.end == nil) || plan.isWorking)
                Button("Open GPX…", action: onOpenGPX)
                    .buttonStyle(.bordered)
                    .disabled(plan.isWorking)
                Spacer()
                if !plan.selected.isEmpty {
                    Button("Clear", role: .destructive) { plan.clear() }
                        .disabled(plan.isWorking)
                }
            }
        }
    }

    @ViewBuilder
    private func routeContent(_ route: PlannedRoute) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(route.name).font(.headline).lineLimit(1)
                Spacer()
                Button {
                    plan.closeRoute()
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .accessibilityLabel("Close route")
            }
            Text(details(route))
                .font(.subheadline.monospacedDigit())
            Label("New: \(route.coverage.summary(tileZoom))", systemImage: "sparkles")
                .font(.subheadline)
                .foregroundStyle(.orange)
            if !route.missed.isEmpty {
                Label("Not reached: \(route.missed.formatted(.list(type: .and)))", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if route.source == .planned {
                startButton
                endButton
            }
            if plan.routeIsOutdated {
                Text("Selection changed – plan again to include it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        HStack {
            if route.source == .planned {
                if let url = plan.gpxURL {
                    ShareLink(item: url) {
                        Label("Share GPX", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                }
                Button {
                    Task { await plan.saveToFolder() }
                } label: {
                    Label("Save Route", systemImage: "folder")
                }
                .buttonStyle(.bordered)
                if plan.routeIsOutdated {
                    Button("Replan") { Task { await plan.plan(with: store) } }
                        .buttonStyle(.bordered)
                        .disabled(plan.isWorking || (plan.selected.isEmpty && plan.end == nil))
                }
            } else {
                Button("Open Another GPX…", action: onOpenGPX)
                    .buttonStyle(.bordered)
            }
        }
    }

    private func details(_ route: PlannedRoute) -> String {
        var parts = [Measurement(value: route.distance / 1000, unit: UnitLength.kilometers)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(1))))]
        if let duration = route.duration {
            parts.append(Duration.seconds(duration).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))
        }
        if !route.stops.isEmpty { parts.append(String(localized: "\(route.stops.count) stops")) }
        return parts.joined(separator: " · ")
    }
}
