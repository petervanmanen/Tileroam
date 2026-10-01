import SwiftUI

@main
struct TileroamApp: App {
    @State private var store = ActivityStore()
    @State private var plan = PlanStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(plan)
        }
    }
}
