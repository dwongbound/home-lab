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
        // A realistic day for the Today widgets: made-up items after now.
        let now = DemoSnapshot.now
        let day = Calendar.current.startOfDay(for: now)
        let extra = [("Team sync", 0.75), ("Gym", 2.0), ("Lunch", 3.5), ("Dentist", 5.0), ("Groceries pickup", 7.0), ("Call the plumber", 8.5), ("Dinner", 10.0)]
        for (title, hours) in extra where g.agenda.count < 8 {
            let start = Calendar.current.date(byAdding: .minute, value: Int(hours * 60), to: now) ?? now
            guard Calendar.current.isDate(start, inSameDayAs: day) else { continue }
            g.agenda.append(WidgetGlance.Item(title: title, start: start, end: nil, allDay: false))
        }
        g.agenda.sort { $0.start < $1.start }
        if (g.notices ?? []).count < 3 { g.notices = (g.notices ?? []) + ["Approve: renew the domain", "Marketplace deal watch found 2 listings", "Weekly backup finished"].prefix(3 - (g.notices ?? []).count) }
        return g
    }
    private let page = ProcessInfo.processInfo.arguments.firstIndex(of: "-galleryPage").flatMap { i in
        ProcessInfo.processInfo.arguments.dropFirst(i + 1).first.flatMap(Int.init)
    } ?? 0

    private func tile<V: View>(_ title: String, _ w: CGFloat, _ h: CGFloat, @ViewBuilder _ content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption2).foregroundStyle(scheme == .light ? Color.black.opacity(0.55) : Color.white.opacity(0.6))
            content()
                .padding(16)
                .frame(width: w, height: h)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(WidgetLook.sky))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.08)))
        }
    }

    private func lock<V: View>(_ title: String, _ w: CGFloat, _ h: CGFloat, @ViewBuilder _ content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption2).foregroundStyle(scheme == .light ? Color.black.opacity(0.55) : Color.white.opacity(0.6))
            content()
                .frame(width: w, height: h)
                .foregroundStyle(.white)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.10)))
        }
    }

    private func tinted<V: View>(_ title: String, _ w: CGFloat, _ h: CGFloat, @ViewBuilder _ content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption2).foregroundStyle(.white.opacity(0.7))
            content()
                .environment(\.colorScheme, .dark)
                .grayscale(1)
                .colorMultiply(Color(red: 1.0, green: 0.85, blue: 0.6))
                .padding(16)
                .frame(width: w, height: h)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.black.opacity(0.35)))
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
                        tile("Sleep · small", 170, 170) { SleepWidgetView(entry: e, family: .systemSmall) }
                        tile("Calories · small", 170, 170) { CaloriesWidgetView(entry: e, family: .systemSmall) }
                    }
                    tile("Sleep · medium", 364, 170) { SleepWidgetView(entry: e, family: .systemMedium) }
                case 2:
                    Text("Lock Screen").font(.headline).foregroundStyle(.white)
                    HStack(spacing: 16) {
                        lock("Jarvis", 76, 76) { GlanceView(entry: e, family: .accessoryCircular) }
                        lock("Calories", 76, 76) { CaloriesWidgetView(entry: e, family: .accessoryCircular) }
                    }
                    HStack(spacing: 16) {
                        lock("Jarvis", 172, 76) { GlanceView(entry: e, family: .accessoryRectangular).padding(.horizontal, 8) }
                        lock("Today", 172, 76) { TodayWidgetView(entry: e, family: .accessoryRectangular).padding(.horizontal, 8) }
                    }
                    Text("Empty states").font(.headline).foregroundStyle(.white)
                    HStack(spacing: 16) {
                        tile("Jarvis · small", 170, 170) { GlanceView(entry: none, family: .systemSmall) }
                        tile("Sleep · small", 170, 170) { SleepWidgetView(entry: none, family: .systemSmall) }
                    }
                    tile("Today · medium", 364, 170) { TodayWidgetView(entry: none, family: .systemMedium) }
                case 3:
                    tile("Jarvis board · iPad extra large", 715, 334) { BoardView(entry: e) }
                case 5:
                    HStack(spacing: 16) {
                        tile("System · small", 170, 170) { SystemWidgetView(entry: e, family: .systemSmall) }
                    }
                    tile("System · medium", 364, 170) { SystemWidgetView(entry: e, family: .systemMedium) }
                case 4:
                    // The tinted Home Screen, approximated: iOS draws the real
                    // one itself (monochrome over the wallpaper, in his tint).
                    HStack(spacing: 16) {
                        tinted("Jarvis · small", 170, 170) { GlanceView(entry: e, family: .systemSmall) }
                        tinted("Calories · small", 170, 170) { CaloriesWidgetView(entry: e, family: .systemSmall) }
                    }
                    tinted("Jarvis · medium", 364, 170) { GlanceView(entry: e, family: .systemMedium) }
                    tinted("Today · medium", 364, 170) { TodayWidgetView(entry: e, family: .systemMedium) }
                    tinted("Home · medium", 364, 170) { HomeWidgetView(entry: e, family: .systemMedium) }
                default:
                    HStack(spacing: 16) {
                        tile("Jarvis · small", 170, 170) { GlanceView(entry: e, family: .systemSmall) }
                        tile("Calories · small", 170, 170) { CaloriesWidgetView(entry: e, family: .systemSmall) }
                    }
                    tile("Jarvis · medium", 364, 170) { GlanceView(entry: e, family: .systemMedium) }
                    tile("Today · medium", 364, 170) { TodayWidgetView(entry: e, family: .systemMedium) }
                    tile("Home · medium", 364, 170) { HomeWidgetView(entry: e, family: .systemMedium) }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(background.ignoresSafeArea())
        .environment(\.colorScheme, scheme)
        .preferredColorScheme(scheme)
    }

    /// `-galleryLight`: everything in light mode.
    private let scheme: ColorScheme = ProcessInfo.processInfo.arguments.contains("-galleryLight") ? .light : .dark
    private var background: some View {
        Group {
            if page == 4 {
                LinearGradient(colors: [Color(red: 0.35, green: 0.22, blue: 0.12), Color(red: 0.12, green: 0.08, blue: 0.1)], startPoint: .top, endPoint: .bottom)
            } else if scheme == .light {
                Color(red: 0.85, green: 0.88, blue: 0.93)
            } else {
                Color(red: 0.13, green: 0.15, blue: 0.2)
            }
        }
    }
}
#endif
