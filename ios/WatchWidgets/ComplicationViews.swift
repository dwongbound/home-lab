// The complications' drawing, shared by the complications and the Watch
// app's debug gallery (screenshots without a real watch face).
import SwiftUI
import WidgetKit
import JarvisKit

/// One moment's complication data.
struct JarvisEntry: TimelineEntry {
    let date: Date
    let data: ComplicationData?
}

/// The orb as a complication glyph: a glowing core in a ring of dots.
struct OrbGlyph: View {
    var body: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { i in
                Circle()
                    .frame(width: 3, height: 3)
                    .offset(y: -11)
                    .rotationEffect(.degrees(Double(i) * 45))
                    .opacity(i % 2 == 0 ? 1 : 0.5)
            }
            Circle()
                .fill(.blue.gradient)
                .frame(width: 12, height: 12)
        }
        .widgetAccentable()
    }
}

struct NeedsView: View {
    let entry: JarvisEntry
    let family: WidgetFamily

    var body: some View {
        let data = entry.data
        let stale = data?.isStale(now: entry.date) ?? true
        let count = stale ? "–" : "\(data?.needCount ?? 0)"
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text(count).font(.title2.weight(.bold)).foregroundStyle(.orange)
                    Text("need").font(.system(size: 9, weight: .semibold))
                }
            }
        case .accessoryCorner:
            Text(count)
                .font(.title3.weight(.bold))
                .foregroundStyle(.orange)
                .widgetLabel("Need you")
        case .accessoryInline:
            Text(data?.summary(now: entry.date) ?? "Open Jarvis to update")
        default:
            VStack(alignment: .leading, spacing: 2) {
                Label("Jarvis", systemImage: "circle.hexagongrid.fill")
                    .font(.headline)
                    .widgetAccentable()
                HStack(spacing: 6) {
                    Circle().fill(.orange).frame(width: 7, height: 7)
                    Text(stale ? "Open Jarvis to update" : "\(data?.needCount ?? 0) need you")
                }
                if !stale, let running = data?.runningCount, running > 0 {
                    HStack(spacing: 6) {
                        Circle().fill(.blue).frame(width: 7, height: 7)
                        Text("\(running) running")
                    }
                }
            }
            .font(.caption)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct NextView: View {
    let entry: JarvisEntry
    let family: WidgetFamily

    var body: some View {
        let next = entry.data?.nextLine(now: entry.date)
        switch family {
        case .accessoryInline:
            Text(next.map { "\($0.title) · \($0.time)" } ?? "Nothing else today")
        default:
            VStack(alignment: .leading, spacing: 2) {
                Text("Next up").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Text(next?.title ?? "Nothing else today").font(.headline).lineLimit(2).widgetAccentable()
                if let time = next?.time { Text(time).font(.caption) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}


/// Calories left today: a ring of eaten against the goal with the number
/// left inside; "570 left" over "1,180 of 1,750" (and protein) in the wide
/// size; "570 kcal left" inline. Over the goal it says "120 over". Old or
/// missing numbers say "Open Jarvis to update".
struct CaloriesView: View {
    let entry: JarvisEntry
    let family: WidgetFamily

    var body: some View {
        let food = entry.data?.calories(now: entry.date)
        switch family {
        case .accessoryCircular:
            if let food {
                Gauge(value: food.fraction) {
                    Text("kcal")
                } currentValueLabel: {
                    Text(food.left >= 0 ? "\(Int(food.left.rounded()))" : "+\(Int((-food.left).rounded()))")
                        .font(.system(size: 13, weight: .bold).monospacedDigit())
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(food.left >= 0 ? .green : .orange)
            } else {
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "fork.knife").font(.title3)
                }
            }
        case .accessoryCorner:
            Image(systemName: "fork.knife")
                .widgetLabel(food.map { "\($0.leftWords.replacingOccurrences(of: " left", with: " kcal left"))" } ?? "Open Jarvis")
        case .accessoryInline:
            Text(food.map { $0.leftWords.replacingOccurrences(of: " left", with: " kcal left").replacingOccurrences(of: " over", with: " kcal over") } ?? "Open Jarvis to update")
        default:
            VStack(alignment: .leading, spacing: 2) {
                Label("Calories", systemImage: "fork.knife").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                if let food {
                    Text(food.leftWords).font(.headline).widgetAccentable()
                    Text(food.ofGoalWords).font(.caption)
                    if let protein = food.proteinWords { Text("Protein \(protein)").font(.caption2).foregroundStyle(.secondary) }
                } else {
                    Text("Open Jarvis to update").font(.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: The second set (Dylan, 2026-11-26: "do sleep score ring, claude
// usage, number of jobs running, diet ring, and next event")

/// A score's band colour, as on the phone's Sleep card.
private func sleepTint(_ score: Int) -> Color {
    switch score {
    case 85...: return Color(red: 0.35, green: 0.85, blue: 0.55)
    case 70..<85: return Color(red: 0.36, green: 0.78, blue: 0.98)
    case 55..<70: return Color(red: 1.0, green: 0.80, blue: 0.30)
    default: return Color(red: 1.0, green: 0.50, blue: 0.40)
    }
}

/// Sleep score: a ring filled to last night's score, coloured by its band.
struct SleepScoreView: View {
    let entry: JarvisEntry
    let family: WidgetFamily

    var body: some View {
        let sleep = entry.data?.sleep
        switch family {
        case .accessoryCircular:
            if let sleep {
                Gauge(value: Double(sleep.score), in: 0...100) {
                    Image(systemName: "bed.double.fill")
                } currentValueLabel: {
                    Text("\(sleep.score)").font(.system(size: 15, weight: .bold).monospacedDigit())
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(sleepTint(sleep.score))
            } else {
                ZStack { AccessoryWidgetBackground(); Image(systemName: "bed.double.fill").font(.title3) }
            }
        case .accessoryCorner:
            Text(sleep.map { "\($0.score)" } ?? "–")
                .font(.title3.weight(.bold))
                .foregroundStyle(sleep.map { sleepTint($0.score) } ?? .secondary)
                .widgetLabel(sleep?.asleep.map { "Slept \($0)" } ?? "Sleep")
        case .accessoryInline:
            Text(sleep.map { "Sleep \($0.score)" + ($0.asleep.map { " · \($0)" } ?? "") } ?? "No sleep score yet")
        default:
            HStack(spacing: 10) {
                if let sleep {
                    Gauge(value: Double(sleep.score), in: 0...100) { EmptyView() } currentValueLabel: {
                        Text("\(sleep.score)").font(.system(size: 14, weight: .bold).monospacedDigit())
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .tint(sleepTint(sleep.score))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Last night").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    Text(sleep.map { "Score \($0.score)" } ?? "No score yet").font(.headline).widgetAccentable()
                    if let asleep = sleep?.asleep { Text("\(asleep) asleep").font(.caption) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Claude usage: the session limit as a ring; the wide size adds the week.
struct ClaudeUsageView: View {
    let entry: JarvisEntry
    let family: WidgetFamily
    private let tint = Color(red: 0.91, green: 0.69, blue: 0.42)

    var body: some View {
        let use = entry.data?.claude(now: entry.date)
        let session = use?.session ?? use?.weekly
        switch family {
        case .accessoryCircular:
            if let session {
                Gauge(value: Double(session), in: 0...100) {
                    Text(use?.session != nil ? "5h" : "wk")
                } currentValueLabel: {
                    Text("\(session)%").font(.system(size: 12, weight: .bold).monospacedDigit())
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(session >= 80 ? .orange : tint)
            } else {
                ZStack { AccessoryWidgetBackground(); Image(systemName: "sparkle").font(.title3) }
            }
        case .accessoryCorner:
            Image(systemName: "sparkle")
                .widgetLabel(session.map { "Claude \($0)%" } ?? "Claude")
        case .accessoryInline:
            Text(use.map { u in ["Claude", u.session.map { "\($0)% session" }, u.weekly.map { "\($0)% week" }].compactMap { $0 }.joined(separator: " · ") } ?? "Claude usage: open Jarvis")
        default:
            VStack(alignment: .leading, spacing: 4) {
                Label("Claude", systemImage: "sparkle").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                if let use {
                    bar("Session", use.session)
                    bar("Week", use.weekly)
                } else {
                    Text("Open Jarvis to update").font(.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func bar(_ name: String, _ pct: Int?) -> some View {
        if let pct {
            HStack(spacing: 6) {
                Text(name).font(.caption2).frame(width: 46, alignment: .leading)
                Gauge(value: Double(pct), in: 0...100) { EmptyView() }
                    .gaugeStyle(.accessoryLinearCapacity)
                    .tint(pct >= 80 ? .orange : tint)
                Text("\(pct)%").font(.caption2.monospacedDigit())
            }
        }
    }
}

/// Jobs running: Jarvis's blue count; the wide size names the first few.
struct JobsView: View {
    let entry: JarvisEntry
    let family: WidgetFamily
    private let blue = Color(red: 0.40, green: 0.70, blue: 1.0)

    var body: some View {
        let jobs = entry.data?.jobs(now: entry.date)
        let count = jobs.map { "\($0.count)" } ?? "–"
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text(count).font(.title2.weight(.bold)).foregroundStyle(blue)
                    Text("jobs").font(.system(size: 9, weight: .semibold))
                }
            }
        case .accessoryCorner:
            Text(count).font(.title3.weight(.bold)).foregroundStyle(blue).widgetLabel("Running")
        case .accessoryInline:
            Text(jobs.map { $0.count == 0 ? "Jarvis is idle" : "\($0.count) running" + ($0.names.first.map { ": \($0)" } ?? "") } ?? "Open Jarvis to update")
        default:
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Circle().fill(blue).frame(width: 7, height: 7)
                    Text(jobs.map { $0.count == 0 ? "Nothing running" : "\($0.count) running" } ?? "Open Jarvis to update").font(.headline).widgetAccentable()
                }
                ForEach(Array((jobs?.names ?? []).prefix(2).enumerated()), id: \.offset) { _, name in
                    Text(name).font(.caption).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Diet ring: calories outside, protein inside (the phone's layered ring),
/// what's left in the middle.
struct DietRingView: View {
    let entry: JarvisEntry
    let family: WidgetFamily

    var body: some View {
        let food = entry.data?.calories(now: entry.date)
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                if let food {
                    let protein = food.protein.flatMap { p in food.proteinGoal.map { g in g > 0 ? min(1, p / g) : 0 } } ?? 0
                    Circle().stroke(.white.opacity(0.18), lineWidth: 4).padding(3)
                    Circle().trim(from: 0, to: food.fraction)
                        .stroke(food.left >= 0 ? Color.green : Color.orange, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90)).padding(3)
                    Circle().stroke(.white.opacity(0.18), lineWidth: 4).padding(9)
                    Circle().trim(from: 0, to: protein)
                        .stroke(Color(red: 0.56, green: 0.77, blue: 0.92), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90)).padding(9)
                        .widgetAccentable()
                    Text(food.left >= 0 ? "\(Int(food.left.rounded()))" : "+\(Int((-food.left).rounded()))")
                        .font(.system(size: 10, weight: .bold).monospacedDigit())
                } else {
                    Image(systemName: "fork.knife").font(.title3)
                }
            }
        default:
            CaloriesView(entry: entry, family: family)
        }
    }
}

/// Next event for the round slots: the time, under a calendar mark.
struct NextCircleView: View {
    let entry: JarvisEntry
    let family: WidgetFamily

    var body: some View {
        let next = entry.data?.nextLine(now: entry.date)
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 1) {
                    Image(systemName: "calendar").font(.system(size: 11, weight: .semibold)).widgetAccentable()
                    Text(next.map { $0.time.replacingOccurrences(of: " AM", with: "").replacingOccurrences(of: " PM", with: "") } ?? "–")
                        .font(.system(size: 13, weight: .bold).monospacedDigit())
                        .minimumScaleFactor(0.6)
                }
            }
        case .accessoryCorner:
            Image(systemName: "calendar").widgetLabel(next.map { "\($0.time) \($0.title)" } ?? "Nothing else today")
        default:
            NextView(entry: entry, family: family)
        }
    }
}
