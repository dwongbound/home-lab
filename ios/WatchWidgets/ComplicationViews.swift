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
