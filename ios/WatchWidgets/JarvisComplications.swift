// Jarvis's Apple Watch complications (Dylan, 2026-11-18: "helpful
// complications as well"). Ask Jarvis (the orb, opens the app to ask),
// Needs you (orange notices, and in the wide size the blue tasks running),
// and Next up (today's next thing). The data comes from the iPhone through
// the Watch app, cached in the App Group (ComplicationStore); stale data
// says so. No money in any of them.
import SwiftUI
import WidgetKit
import JarvisKit

/// Reads the cached data; refreshes every 15 minutes (and whenever the
/// Watch app reloads the timelines after the phone sends new data).
struct JarvisProvider: TimelineProvider {
    func placeholder(in context: Context) -> JarvisEntry {
        JarvisEntry(date: Date(), data: ComplicationData(needCount: 1, runningCount: 1, nextTitle: "Volleyball", nextAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(3600)), updated: Date()))
    }

    func getSnapshot(in context: Context, completion: @escaping (JarvisEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : JarvisEntry(date: Date(), data: ComplicationStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<JarvisEntry>) -> Void) {
        let entry = JarvisEntry(date: Date(), data: ComplicationStore.load())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
    }
}

/// Ask Jarvis: the orb; tapping opens the app ready to ask.
struct AskWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "jarvis.ask", provider: JarvisProvider()) { _ in
            ZStack {
                AccessoryWidgetBackground()
                OrbGlyph()
            }
            .widgetURL(URL(string: "jarvis://ask"))
            .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Ask Jarvis")
        .description("Opens Jarvis ready to ask.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner])
    }
}

/// Needs you: the orange count, and in the wide size tasks running too.
struct NeedsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "jarvis.needs", provider: JarvisProvider()) { entry in
            FamilyReader { family in NeedsView(entry: entry, family: family) }
                .widgetURL(URL(string: "jarvis://notices"))
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Needs you")
        .description("How many things Jarvis needs you for, and what he's working on.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}

/// Next up: today's next thing and when.
struct NextWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "jarvis.next", provider: JarvisProvider()) { entry in
            FamilyReader { family in NextView(entry: entry, family: family) }
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Next up")
        .description("The next thing on today's schedule.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline])
    }
}

/// Calories left today, from Jarvis's meal log.
struct CaloriesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "jarvis.calories", provider: JarvisProvider()) { entry in
            FamilyReader { family in CaloriesView(entry: entry, family: family) }
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Calories left")
        .description("Calories left today against your goal.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}

/// Hands the complication's size to a view that draws for it.
struct FamilyReader<Content: View>: View {
    @Environment(\.widgetFamily) private var family
    @ViewBuilder let content: (WidgetFamily) -> Content
    var body: some View { content(family) }
}

@main
struct JarvisComplications: WidgetBundle {
    var body: some Widget {
        AskWidget()
        NeedsWidget()
        NextWidget()
        CaloriesWidget()
    }
}
