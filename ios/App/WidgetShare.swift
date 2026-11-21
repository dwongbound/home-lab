// Hands the widgets what to show (JarvisKit WidgetGlance), through the app
// group, and asks them to redraw only when what they'd show changed.
import Foundation
import JarvisKit
import WidgetKit

enum WidgetShare {
    @MainActor private static var last: WidgetGlance?

    @MainActor static func write(_ snapshot: Snapshot) {
        guard let defaults = UserDefaults(suiteName: WidgetGlance.appGroup) else { return }
        let glance = WidgetGlance.from(snapshot)
        defaults.set(glance.encoded(), forKey: WidgetGlance.key)
        // Only a change in what they show (not just the time) redraws them.
        var same = glance
        if let last { same.updated = last.updated }
        if same != last { WidgetCenter.shared.reloadAllTimelines() }
        last = glance
    }
}
