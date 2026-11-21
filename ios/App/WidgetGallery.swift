// Every widget drawn at its real size from sample data, for screenshots
// (`-widgetGallery`, debug builds only). The same views the widgets use.
#if DEBUG
import JarvisKit
import SwiftUI
import WidgetKit

struct WidgetGallery: View {
    private let filled: WidgetGlance? = DemoSnapshot.snapshot.map {
        var g = WidgetGlance.from($0)
        // Made-up food for the picture when the sample day has none.
        if g.food == nil { g.food = WidgetGlance.Food(left: 640, goal: 2100, protein: 96, proteinGoal: 150) }
        return g
    }
    private let page = ProcessInfo.processInfo.arguments.firstIndex(of: "-galleryPage").flatMap { i in
        ProcessInfo.processInfo.arguments.dropFirst(i + 1).first.flatMap(Int.init)
    } ?? 0

    private func tile<V: View>(_ title: String, _ w: CGFloat, _ h: CGFloat, @ViewBuilder _ content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            content()
                .padding(16)
                .frame(width: w, height: h)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(WidgetLook.sky))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.08)))
        }
    }

    private func lock<V: View>(_ title: String, _ w: CGFloat, _ h: CGFloat, @ViewBuilder _ content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            content()
                .frame(width: w, height: h)
                .foregroundStyle(.white)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.10)))
        }
    }

    var body: some View {
        let e = GlanceEntry(date: DemoSnapshot.now, glance: filled)
        let none = GlanceEntry(date: Date(), glance: nil)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                switch page {
                case 1:
                    tile("Today · large", 364, 382) { TodayWidgetView(entry: e, family: .systemLarge) }
                    HStack(spacing: 16) {
                        tile("Calories · small", 170, 170) { CaloriesWidgetView(entry: e, family: .systemSmall) }
                        tile("Sleep · small", 170, 170) { SleepWidgetView(entry: e, family: .systemSmall) }
                    }
                case 2:
                    HStack(spacing: 16) {
                        lock("Jarvis · lock", 76, 76) { GlanceView(entry: e, family: .accessoryCircular) }
                        lock("Calories · lock", 76, 76) { CaloriesWidgetView(entry: e, family: .accessoryCircular) }
                        lock("Jarvis · lock", 172, 76) { GlanceView(entry: e, family: .accessoryRectangular).padding(.horizontal, 8) }
                    }
                    lock("Today · lock", 172, 76) { TodayWidgetView(entry: e, family: .accessoryRectangular).padding(.horizontal, 8) }
                    Text("Empty states").font(.headline).foregroundStyle(.white)
                    HStack(spacing: 16) {
                        tile("Jarvis · small", 170, 170) { GlanceView(entry: none, family: .systemSmall) }
                        tile("Sleep · small", 170, 170) { SleepWidgetView(entry: none, family: .systemSmall) }
                    }
                    tile("Today · medium", 364, 170) { TodayWidgetView(entry: none, family: .systemMedium) }
                case 3:
                    tile("Jarvis board · iPad extra large", 715, 334) { BoardView(entry: e) }
                default:
                    HStack(spacing: 16) {
                        tile("Jarvis · small", 170, 170) { GlanceView(entry: e, family: .systemSmall) }
                        tile("Calories · small", 170, 170) { CaloriesWidgetView(entry: e, family: .systemSmall) }
                    }
                    tile("Jarvis · medium", 364, 170) { GlanceView(entry: e, family: .systemMedium) }
                    tile("Today · medium", 364, 170) { TodayWidgetView(entry: e, family: .systemMedium) }
                    tile("Sleep · medium", 364, 170) { SleepWidgetView(entry: e, family: .systemMedium) }
                    tile("Home · medium", 364, 170) { HomeWidgetView(entry: e, family: .systemMedium) }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(red: 0.13, green: 0.15, blue: 0.2).ignoresSafeArea())
    }
}
#endif
