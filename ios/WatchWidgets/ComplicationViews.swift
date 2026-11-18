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

