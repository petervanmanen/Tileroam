import MapKit
import SwiftUI

/// Chooses where a planned route starts: the current location, a recent place, or a searched
/// address or place (or long-press the map: "Start Here"). With `kind: .end`, where it ends: back at
/// the start (a round trip) or a place (point to point, issue #50).
struct StartPicker: View {
    enum Kind { case start, end }
    var kind: Kind = .start
    @Environment(PlanStore.self) private var plan
    @Environment(\.dismiss) private var dismiss
    @State private var search = PlaceSearch()
    @State private var isResolving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                if search.query.isEmpty {
                    if kind == .start {
                        Section {
                            choice(selected: plan.start == nil) {
                                Label { Text("My Location") } icon: { Image(systemName: "location.fill").foregroundStyle(.tint) }
                            } action: {
                                plan.setStart(nil)
                                dismiss()
                            }
                        } footer: {
                            Text("Or long-press the map and choose Start Here. You can drag the green flag to move it.")
                        }
                    } else {
                        Section {
                            choice(selected: plan.end == nil) {
                                Label { Text("Back to Start") } icon: {
                                    Image(systemName: "arrow.triangle.turn.up.right.circle").foregroundStyle(.tint)
                                }
                            } action: {
                                plan.setEnd(nil)
                                dismiss()
                            }
                        } footer: {
                            Text("A round trip, or choose a place below to ride from the start to there; or long-press the map and choose End Here. You can drag the checkered flag to move it.")
                        }
                    }
                    if !plan.recentStarts.isEmpty {
                        Section("Recent") {
                            ForEach(plan.recentStarts, id: \.self) { start in
                                choice(selected: (kind == .start ? plan.start : plan.end) == start) {
                                    Label { Text(start.name) } icon: { Image(systemName: "clock").foregroundStyle(.secondary) }
                                } action: {
                                    set(start)
                                    dismiss()
                                }
                                .swipeActions {
                                    Button("Remove", role: .destructive) { plan.removeRecentStart(start) }
                                }
                            }
                        }
                    }
                } else {
                    ForEach(search.results, id: \.self) { result in
                        Button {
                            choose(result)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(result.title)
                                if !result.subtitle.isEmpty {
                                    Text(result.subtitle).font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .disabled(isResolving)
                    }
                }
                if let error {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            }
            .searchable(text: $search.query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search for an address or place")
            .navigationTitle(kind == .start ? String(localized: "Starting Point") : String(localized: "End Point"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        #if DEBUG
        // Screenshots: -StartSearch "text" fills in the search field.
        .onAppear { if let text = UserDefaults.standard.string(forKey: "StartSearch") { search.query = text } }
        #endif
    }

    private func choice(selected: Bool, @ViewBuilder label: () -> some View, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                label()
                Spacer()
                if selected {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func set(_ place: StartPoint) {
        if kind == .start { plan.setStart(place) } else { plan.setEnd(place) }
    }

    private func choose(_ result: MKLocalSearchCompletion) {
        isResolving = true
        error = nil
        Task {
            defer { isResolving = false }
            if let place = try? await search.resolve(result) {
                set(place)
                dismiss()
            } else {
                error = String(localized: "This place couldn't be found. Try another search.")
            }
        }
    }
}
