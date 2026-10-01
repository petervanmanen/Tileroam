import Foundation
import WidgetKit

/// Values shared with the widget through the app group.
enum WidgetData {
    static let appGroup = "group.nl.petervanmanen.Tileroam"

    static func save(cycling: Eddington, running: Eddington) {
        guard let defaults = UserDefaults(suiteName: appGroup) else { return }
        let old = defaults.integer(forKey: "eddington.cycling")
        let oldNeeded = defaults.integer(forKey: "eddington.cycling.needed")
        defaults.set(cycling.number, forKey: "eddington.cycling")
        defaults.set(cycling.daysNeeded, forKey: "eddington.cycling.needed")
        defaults.set(running.number, forKey: "eddington.running")
        defaults.set(running.daysNeeded, forKey: "eddington.running.needed")
        defaults.set(Date.now, forKey: "eddington.updated")
        if old != cycling.number || oldNeeded != cycling.daysNeeded {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
