import MapKit
import SwiftUI

/// Chooses where a planned round trip starts: the current location, a recent starting point, or a
/// searched address or place. Long-pressing the map works too.
struct StartPicker: View {
    @Environment(PlanStore.self) private var plan
    @Environment(\.dismiss) private var dismiss
    @State private var search = PlaceSearch()
    @State private var isResolving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                if search.query.isEmpty {
                    Section {
                        choice(selected: plan.start == nil) {
                            Label { Text("My Location") } icon: { Image(systemName: "location.fill").foregroundStyle(.tint) }
                        } action: {
                            plan.setStart(nil)
                            dismiss()
                        }
                    } footer: {
                        Text("Or long-press the map to start there. You can drag the green flag to move it.")
                    }
                    if !plan.recentStarts.isEmpty {
                        Section("Recent") {
                            ForEach(plan.recentStarts, id: \.self) { start in
                                choice(selected: plan.start == start) {
                                    Label { Text(start.name) } icon: { Image(systemName: "clock").foregroundStyle(.secondary) }
                                } action: {
                                    plan.setStart(start)
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
            .navigationTitle("Starting Point")
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

    private func choose(_ result: MKLocalSearchCompletion) {
        isResolving = true
        error = nil
        Task {
            defer { isResolving = false }
            if let start = try? await search.resolve(result) {
                plan.setStart(start)
                dismiss()
            } else {
                error = String(localized: "This place couldn't be found. Try another search.")
            }
        }
    }
}
