import SwiftUI

@main
struct TileroamApp: App {
    @State private var store = ActivityStore()
    @State private var plan = PlanStore()

    init() {
        SettingsSync.start()
        _ = NetworkMonitor.shared // start watching the network early, for map downloads
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(plan)
                .onOpenURL { url in
                    // Return from the Strava app's authorize screen: tileroam://localhost?code=…
                    guard url.scheme == StravaConfig.callbackScheme else { return }
                    Task { await store.completeStravaLogin(callback: url) }
                }
        }
    }
}
