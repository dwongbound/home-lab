// Jarvis on the Home Screen and Lock Screen (Dylan, 2026-11-21: "can we
// build widgets for ipad and iphone"). Jarvis (what needs him, what's
// running), Today (what's next and the weather), Calories, Sleep, Home and,
// on the iPad, one board of all of it. They read what the app last saw
// (JarvisKit WidgetGlance in the app group): orange = needs him, blue =
// Jarvis working. Never money. A tap opens the app.
//
// Each view takes its size as a value (not only from the environment), so
// the app's debug gallery (-widgetGallery) can draw every one for
// screenshots from the same code.
import JarvisKit
import SwiftUI
import WidgetKit

enum WidgetLook {
    /// Night sky in dark mode, paper in light mode.
    private static func both(_ dark: UIColor, _ light: UIColor) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
    static let sky = both(UIColor(red: 0.06, green: 0.09, blue: 0.15, alpha: 1), UIColor(red: 0.97, green: 0.97, blue: 0.99, alpha: 1))
    static let frost = both(UIColor(white: 0.95, alpha: 1), UIColor(white: 0.08, alpha: 1))
    static let dim = both(UIColor(white: 0.95, alpha: 0.62), UIColor(white: 0.08, alpha: 0.6))
    static let faint = both(UIColor(white: 0.95, alpha: 0.4), UIColor(white: 0.08, alpha: 0.38))
    /// The empty part of a ring or bar.
    static let track = both(UIColor(white: 1, alpha: 0.12), UIColor(white: 0, alpha: 0.09))
    static let orange = Color(red: 1.0, green: 0.58, blue: 0.24)
    static let blue = Color(red: 0.40, green: 0.70, blue: 1.0)
    static let accent = Color(red: 0.62, green: 0.58, blue: 0.95)
    static let green = Color(red: 0.35, green: 0.85, blue: 0.55)
    static func stage(_ key: String) -> Color {
        switch key {
        case "deep": return Color(red: 0.21, green: 0.20, blue: 0.64)
        case "core": return Color(red: 0.20, green: 0.47, blue: 0.96)
        case "rem": return Color(red: 0.36, green: 0.78, blue: 0.98)
        case "awake": return Color(red: 1.0, green: 0.50, blue: 0.40)
        default: return Color(red: 0.45, green: 0.62, blue: 0.80)
        }
    }
    static func band(_ band: String?) -> Color {
        switch band {
        case "great": return green
        case "good": return Color(red: 0.36, green: 0.78, blue: 0.98)
        case "fair": return Color(red: 1.0, green: 0.80, blue: 0.30)
        case "poor": return Color(red: 1.0, green: 0.50, blue: 0.40)
        default: return accent
        }
    }
}

private typealias Look = WidgetLook

struct GlanceEntry: TimelineEntry {
    let date: Date
    let glance: WidgetGlance?
}

struct GlanceProvider: TimelineProvider {
    private func read() -> WidgetGlance? {
        WidgetGlance.decode(UserDefaults(suiteName: WidgetGlance.appGroup)?.data(forKey: WidgetGlance.key))
    }

    func placeholder(in context: Context) -> GlanceEntry { GlanceEntry(date: Date(), glance: nil) }

    func getSnapshot(in context: Context, completion: @escaping (GlanceEntry) -> Void) {
        completion(GlanceEntry(date: Date(), glance: read()))
    }

    /// An entry every 15 minutes for four hours, so "next" moves on with
    /// the day; the app's next snapshot replaces them all.
    func getTimeline(in context: Context, completion: @escaping (Timeline<GlanceEntry>) -> Void) {
        let glance = read()
        let now = Date()
        let entries = (0..<16).map { GlanceEntry(date: now.addingTimeInterval(Double($0) * 900), glance: glance) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(4 * 3600))))
    }
}

// MARK: Shared pieces

private func timeLabel(_ item: WidgetGlance.Item, now: Date) -> String {
    if item.allDay { return "All day" }
    if item.start <= now { return "Now" }
    return item.start.formatted(date: .omitted, time: .shortened)
}

/// "as of 3:40 PM" once what the widget shows is more than an hour old.
private struct AsOf: View {
    let glance: WidgetGlance?
    let now: Date
    var body: some View {
        if let glance, now.timeIntervalSince(glance.updated) > 3600 {
            Text("as of \(glance.updated.formatted(date: .omitted, time: .shortened))").font(.caption2).foregroundStyle(Look.faint)
        }
    }
}

private struct Header: View {
    let title: String
    let symbol: String
    var tint: Color = Look.accent
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(title).foregroundStyle(Look.dim)
        }
        .font(.caption.weight(.semibold))
        .lineLimit(1)
    }
}

private struct Empty: View {
    let words: String
    var body: some View {
        Text(words).font(.footnote).foregroundStyle(Look.dim)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private let openOnce = "Open Jarvis once to fill this in."

/// Reads the widget's size and hands it to the view.
struct FamilyReader<Content: View>: View {
    @Environment(\.widgetFamily) private var family
    @ViewBuilder let content: (WidgetFamily) -> Content
    var body: some View { content(family) }
}

// MARK: Jarvis

struct GlanceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "JarvisGlance", provider: GlanceProvider()) { entry in
            FamilyReader { GlanceView(entry: entry, family: $0) }
                .containerBackground(Look.sky, for: .widget)
                .widgetURL(URL(string: "jarvis://notices"))
        }
        .configurationDisplayName("Jarvis")
        .description("What needs you and what Jarvis is working on.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

struct GlanceView: View {
    let entry: GlanceEntry
    let family: WidgetFamily

    var body: some View {
        let g = entry.glance
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "circle.hexagongrid.fill").font(.caption)
                    Text("\(g?.unread ?? 0)").font(.title3.weight(.bold)).monospacedDigit()
                }
            }
            .widgetAccentable()
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text("Jarvis").font(.headline).widgetAccentable()
                // Two short lines rather than one long one, so nothing is cut.
                ForEach(g?.lockLines ?? ["Open Jarvis once"], id: \.self) { Text($0).lineLimit(1) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            VStack(alignment: .leading, spacing: 8) {
                Header(title: "Jarvis", symbol: "circle.hexagongrid.fill")
                if let g {
                    if family == .systemMedium {
                        // Counts down the left, the newest notices beside them.
                        HStack(alignment: .top, spacing: 18) {
                            VStack(alignment: .leading, spacing: 6) {
                                count(g.unread, "new", Look.orange, lit: g.unread > 0)
                                count(g.running, "running", Look.blue, lit: g.running > 0)
                            }
                            let titles = g.notices ?? g.newestNotice.map { [$0] } ?? []
                            VStack(alignment: .leading, spacing: 7) {
                                if titles.isEmpty {
                                    Text("Nothing needs you.").font(.subheadline).foregroundStyle(Look.dim)
                                }
                                ForEach(Array(titles.prefix(3).enumerated()), id: \.offset) { index, title in
                                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                                        Circle().fill(index == 0 && g.needsYou ? Look.orange : Look.faint).frame(width: 5, height: 5)
                                        Text(title).font(.subheadline).foregroundStyle(index == 0 ? Look.frost : Look.dim).lineLimit(2)
                                    }
                                }
                            }
                            .padding(.top, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        HStack(spacing: 18) {
                            count(g.unread, "new", Look.orange, lit: g.unread > 0)
                            count(g.running, "running", Look.blue, lit: g.running > 0)
                        }
                        if g.needsYou {
                            Text("Something needs you").font(.caption).foregroundStyle(Look.orange).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    AsOf(glance: g, now: entry.date)
                } else {
                    Empty(words: openOnce)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func count(_ n: Int, _ word: String, _ tint: Color, lit: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(n)").font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(lit ? tint : Look.faint)
            Text(word).font(.caption).foregroundStyle(Look.dim)
        }
    }
}

// MARK: Today

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "JarvisToday", provider: GlanceProvider()) { entry in
            FamilyReader { TodayWidgetView(entry: entry, family: $0) }
                .containerBackground(Look.sky, for: .widget)
                .widgetURL(URL(string: "jarvis://today"))
        }
        .configurationDisplayName("Today")
        .description("What's next today, and the weather.")
        .supportedFamilies([.systemMedium, .systemLarge, .accessoryRectangular])
    }
}

struct TodayWidgetView: View {
    let entry: GlanceEntry
    let family: WidgetFamily

    var body: some View {
        let limit = family == .systemLarge ? 8 : family == .accessoryRectangular ? 2 : 4
        let items = entry.glance?.upcoming(at: entry.date, limit: limit) ?? []
        if family == .accessoryRectangular {
            VStack(alignment: .leading, spacing: 1) {
                if items.isEmpty { Text("Nothing else today").font(.headline) }
                // The next one gets the time on its own line and the title the
                // full width under it; the one after shares a line.
                if let next = items.first {
                    Text(timeLabel(next, now: entry.date)).font(.headline).widgetAccentable()
                    Text(next.title).lineLimit(1)
                }
                if items.count > 1 {
                    Text("\(timeLabel(items[1], now: entry.date))  \(items[1].title)").lineLimit(1).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: family == .systemLarge ? 11 : 6) {
                HStack {
                    Header(title: "Today", symbol: "calendar")
                    Spacer()
                    if let weather = entry.glance?.weather {
                        Text(weather).font(.caption).foregroundStyle(Look.dim).lineLimit(1)
                    }
                }
                if entry.glance == nil {
                    Empty(words: openOnce)
                } else if items.isEmpty {
                    Empty(words: "Nothing else today.")
                } else {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(timeLabel(item, now: entry.date))
                                .font(.footnote.weight(.semibold)).monospacedDigit()
                                .foregroundStyle(index == 0 ? Look.accent : Look.dim)
                                .frame(width: 68, alignment: .leading)
                            Text(item.title).font(.subheadline).foregroundStyle(Look.frost).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    AsOf(glance: entry.glance, now: entry.date)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

// MARK: Calories

struct CaloriesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "JarvisCalories", provider: GlanceProvider()) { entry in
            FamilyReader { CaloriesWidgetView(entry: entry, family: $0) }
                .containerBackground(Look.sky, for: .widget)
                .widgetURL(URL(string: "jarvis://diet"))
        }
        .configurationDisplayName("Calories")
        .description("Calories left today, and protein.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

struct CaloriesWidgetView: View {
    let entry: GlanceEntry
    let family: WidgetFamily

    var body: some View {
        let food = entry.glance?.food
        let eaten = food.map { max(0, $0.goal - $0.left) } ?? 0
        let progress = food.map { $0.goal > 0 ? min(1, eaten / $0.goal) : 0 } ?? 0
        if family == .accessoryCircular {
            Gauge(value: progress) { Image(systemName: "fork.knife") } currentValueLabel: {
                Text(food.map { "\(Int($0.left.rounded()))" } ?? "–")
            }
            .gaugeStyle(.accessoryCircularCapacity)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Header(title: "Calories", symbol: "fork.knife", tint: Look.green)
                if let food {
                    HStack {
                        Spacer()
                        ZStack {
                            Circle().stroke(Look.track, lineWidth: 9)
                            Circle().trim(from: 0, to: progress)
                                .stroke(food.left >= 0 ? Look.green : Look.orange, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            VStack(spacing: 0) {
                                Text("\(Int(abs(food.left).rounded()))").font(.title3.weight(.bold)).monospacedDigit().foregroundStyle(Look.frost)
                                Text(food.left >= 0 ? "left" : "over").font(.caption2).foregroundStyle(Look.dim)
                            }
                        }
                        .frame(width: 84, height: 84)
                        Spacer()
                    }
                    if let protein = food.protein {
                        Text("Protein \(Int(protein.rounded()))" + (food.proteinGoal.map { " of \(Int($0.rounded())) g" } ?? " g"))
                            .font(.caption).foregroundStyle(Look.dim).lineLimit(1)
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    Empty(words: "Nothing logged yet today.")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

// MARK: Sleep

struct SleepWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "JarvisSleep", provider: GlanceProvider()) { entry in
            FamilyReader { SleepWidgetView(entry: entry, family: $0) }
                .containerBackground(Look.sky, for: .widget)
                .widgetURL(URL(string: "jarvis://sleep"))
        }
        .configurationDisplayName("Sleep")
        .description("Last night's sleep score, time asleep and the week.")
        // Home Screen only, and hidden while the phone is locked.
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct SleepWidgetView: View {
    let entry: GlanceEntry
    let family: WidgetFamily

    var body: some View {
        Group {
            if let sleep = entry.glance?.sleep {
                VStack(alignment: .leading, spacing: 8) {
                    Header(title: sleep.when ?? "Sleep", symbol: "bed.double.fill")
                    HStack(spacing: 14) {
                        ring(sleep)
                        if family == .systemMedium {
                            VStack(alignment: .leading, spacing: 8) {
                                if let asleep = sleep.asleep {
                                    Text(asleep).font(.title2.weight(.bold)).monospacedDigit().foregroundStyle(Look.frost)
                                }
                                bar(sleep.stages)
                                week(entry.glance?.sleepWeek ?? [])
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: family == .systemSmall ? .center : .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Header(title: "Sleep", symbol: "bed.double.fill")
                    Empty(words: "No sleep recorded yet.")
                }
            }
        }
        .privacySensitive()
    }

    private func ring(_ sleep: WidgetGlance.Sleep) -> some View {
        let tint = Look.band(sleep.band)
        return ZStack {
            Circle().stroke(Look.track, lineWidth: 8)
            if let score = sleep.score {
                Circle().trim(from: 0, to: CGFloat(score) / 100)
                    .stroke(tint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            VStack(spacing: 0) {
                Text(sleep.score.map(String.init) ?? sleep.asleep ?? "").font(.title2.weight(.bold)).monospacedDigit().foregroundStyle(Look.frost)
                if family == .systemSmall, sleep.score != nil, let asleep = sleep.asleep {
                    Text(asleep).font(.caption2).foregroundStyle(Look.dim)
                } else if let word = sleep.bandWord {
                    Text(word).font(.caption2.weight(.semibold)).foregroundStyle(tint)
                }
            }
        }
        .frame(width: 88, height: 88)
    }

    private func bar(_ shares: [WidgetGlance.Sleep.Share]) -> some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(Array(shares.enumerated()), id: \.offset) { _, share in
                    Rectangle().fill(Look.stage(share.stage))
                        .frame(width: max(2, (geo.size.width - CGFloat(shares.count) * 2) * share.fraction))
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: 7)
    }

    private func week(_ scores: [Int?]) -> some View {
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(Array(scores.enumerated()), id: \.offset) { index, score in
                RoundedRectangle(cornerRadius: 2)
                    .fill(index == scores.count - 1 ? Look.accent : Look.faint)
                    .frame(width: 9, height: max(3, 26 * CGFloat(score ?? 0) / 100))
            }
        }
        .frame(height: 26, alignment: .bottom)
    }
}

// MARK: Home

struct HomeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "JarvisHome", provider: GlanceProvider()) { entry in
            FamilyReader { HomeWidgetView(entry: entry, family: $0) }
                .containerBackground(Look.sky, for: .widget)
                .widgetURL(URL(string: "jarvis://home"))
        }
        .configurationDisplayName("Home")
        .description("The room's temperature, the thermostat and what's on.")
        .supportedFamilies([.systemMedium])
    }
}

struct HomeWidgetView: View {
    let entry: GlanceEntry
    let family: WidgetFamily

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Header(title: "Home", symbol: "house.fill")
            if let home = entry.glance?.home {
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(home.temperature ?? "–").font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(Look.frost)
                        if let thermostat = home.thermostat {
                            Text(thermostat).font(.caption).foregroundStyle(Look.dim).lineLimit(1)
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(home.lightsOn) of \(home.lights) lights on").font(.caption.weight(.semibold)).foregroundStyle(Look.frost)
                        ForEach(home.on, id: \.self) { name in
                            Text(name).font(.caption).foregroundStyle(Look.dim).lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 0)
                AsOf(glance: entry.glance, now: entry.date)
            } else {
                Empty(words: entry.glance == nil ? openOnce : "Home isn't connected.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: iPad board

struct BoardWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "JarvisBoard", provider: GlanceProvider()) { entry in
            BoardView(entry: entry)
                .containerBackground(Look.sky, for: .widget)
        }
        .configurationDisplayName("Jarvis board")
        .description("Today, Home and Jarvis together, for the iPad.")
        .supportedFamilies([.systemExtraLarge])
    }
}

struct BoardView: View {
    let entry: GlanceEntry
    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            TodayWidgetView(entry: entry, family: .systemLarge)
            Rectangle().fill(Look.track).frame(width: 1)
            VStack(spacing: 14) {
                GlanceView(entry: entry, family: .systemMedium)
                Rectangle().fill(Look.track).frame(height: 1)
                HomeWidgetView(entry: entry, family: .systemMedium)
            }
        }
    }
}

// MARK: System

/// The PC as rings (Dylan, 2026-11-21: "i like these graphs and stuff vs
/// words"): GPU, memory, disk and CPU, the same colours as the app's
/// System panel. Small: four rings two by two; medium: in a row with the
/// amounts.
struct SystemWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "JarvisSystem", provider: GlanceProvider()) { entry in
            FamilyReader { SystemWidgetView(entry: entry, family: $0) }
                .containerBackground(Look.sky, for: .widget)
                .widgetURL(URL(string: "jarvis://system"))
        }
        .configurationDisplayName("System")
        .description("The PC's graphics card, memory, disk and processor.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct SystemWidgetView: View {
    let entry: GlanceEntry
    let family: WidgetFamily

    static func tint(_ kind: String) -> Color {
        switch kind {
        case "gpu": return Color(red: 0.40, green: 0.70, blue: 1.00)
        case "ram": return Color(red: 0.62, green: 0.58, blue: 0.95)
        case "disk": return Color(red: 0.91, green: 0.69, blue: 0.42)
        default: return Color(red: 0.58, green: 0.84, blue: 0.68)
        }
    }

    var body: some View {
        let gauges = entry.glance?.system ?? []
        VStack(alignment: .leading, spacing: 8) {
            Header(title: "System", symbol: "desktopcomputer")
            if gauges.isEmpty {
                Empty(words: entry.glance == nil ? openOnce : "No readings from the PC.")
            } else if family == .systemMedium {
                HStack(alignment: .top, spacing: 6) {
                    ForEach(gauges, id: \.kind) { gauge in
                        VStack(spacing: 4) {
                            ring(gauge, size: 54)
                            Text(gauge.title).font(.caption.weight(.semibold)).foregroundStyle(Look.frost)
                            Text(gauge.amount).font(.caption2).monospacedDigit().foregroundStyle(Look.dim).lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                Spacer(minLength: 0)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(gauges.prefix(4), id: \.kind) { gauge in
                        VStack(spacing: 2) {
                            ring(gauge, size: 44)
                            Text(gauge.title).font(.system(size: 10, weight: .semibold)).foregroundStyle(Look.dim)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func ring(_ gauge: WidgetGlance.Gauge, size: CGFloat) -> some View {
        ZStack {
            Circle().stroke(Look.track, lineWidth: 5)
            Circle().trim(from: 0, to: CGFloat(gauge.percent) / 100)
                .stroke(SystemWidgetView.tint(gauge.kind), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(gauge.percent)%").font(.system(size: size * 0.26, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(Look.frost)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(gauge.title) \(gauge.percent) percent")
    }
}
