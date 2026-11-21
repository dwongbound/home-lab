// The orb as a widget (Dylan, 2026-11-21: "i want one with the jarvis orb
// thats dynamic is that possible?"). A prototype to answer that honestly.
//
// A widget can't run the app's orb: WidgetKit draws each timeline entry
// once, as a still picture, and never runs code on the Home Screen. So the
// orb here is a still sphere whose points and dots are at a new turn in
// each entry: a burst of entries 3 s apart after each refresh, then rest.
// Measured on the simulator (iOS 27.2, screen recordings): the entries
// land on time, but each step is a one-frame jump, not an animated turn,
// with or without an explicit animation; a Canvas, plain offset views and
// a clock-driven ProgressView ring all only change at entries.
//
// What the dots mean is the app's: orange for each unread notice, blue for
// each job Jarvis is running. No private API is used.
import JarvisKit
import SwiftUI
import WidgetKit

struct OrbEntry: TimelineEntry {
    let date: Date
    let glance: WidgetGlance?
    /// Which turn of the orb this entry shows.
    let step: Int
}

struct OrbProvider: TimelineProvider {
    /// Seconds between the burst's entries, how many, and the rest after.
    static let burstSpacing: Double = 3
    static let burstCount = 20
    static let restMinutes: Double = 15

    private func read() -> WidgetGlance? {
        let glance = WidgetGlance.decode(UserDefaults(suiteName: WidgetGlance.appGroup)?.data(forKey: WidgetGlance.key))
        #if DEBUG
        // Simulator prototype: dots to look at before the app group works.
        if glance == nil { return WidgetGlance(updated: Date(), unread: 3, needsYou: true, running: 1, agenda: [], sleep: nil) }
        #endif
        return glance
    }

    func placeholder(in context: Context) -> OrbEntry { OrbEntry(date: Date(), glance: nil, step: 0) }

    func getSnapshot(in context: Context, completion: @escaping (OrbEntry) -> Void) {
        completion(OrbEntry(date: Date(), glance: read(), step: 0))
    }

    /// A burst of entries a few seconds apart (the turn), then one resting
    /// entry; the system asks again after the rest. Entries cost nothing
    /// against the refresh budget; each getTimeline call does.
    func getTimeline(in context: Context, completion: @escaping (Timeline<OrbEntry>) -> Void) {
        let glance = read()
        let now = Date()
        var entries = (0..<OrbProvider.burstCount).map {
            OrbEntry(date: now.addingTimeInterval(Double($0) * OrbProvider.burstSpacing), glance: glance, step: $0)
        }
        entries.append(OrbEntry(date: now.addingTimeInterval(Double(OrbProvider.burstCount) * OrbProvider.burstSpacing), glance: glance, step: OrbProvider.burstCount))
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(OrbProvider.restMinutes * 60))))
    }
}

struct OrbWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "JarvisOrb", provider: OrbProvider()) { entry in
            // Always the night sky: the orb is light on dark, like the app.
            FamilyReader { OrbWidgetView(entry: entry, family: $0) }
                .environment(\.colorScheme, .dark)
                .containerBackground(Color(red: 0.06, green: 0.09, blue: 0.15), for: .widget)
                .widgetURL(URL(string: "jarvis://notices"))
        }
        .configurationDisplayName("Jarvis orb")
        .description("The orb, with a dot for each notice and each job.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct OrbWidgetView: View {
    let entry: OrbEntry
    let family: WidgetFamily

    var body: some View {
        let g = entry.glance
        if family == .systemMedium {
            HStack(spacing: 16) {
                orb.frame(width: 120, height: 120)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Jarvis").font(.caption.weight(.semibold)).foregroundStyle(WidgetLook.dim)
                    ForEach(g?.lockLines ?? ["Open Jarvis once"], id: \.self) { line in
                        Text(line).font(.subheadline.weight(.semibold)).foregroundStyle(WidgetLook.frost)
                    }
                    if let newest = g?.newestNotice {
                        Text(newest).font(.caption).foregroundStyle(WidgetLook.dim).lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
        } else {
            orb.padding(4)
        }
    }

    /// The sphere, its mesh turned to this entry's step, and the dots.
    private var orb: some View {
        let unread = entry.glance?.unread ?? 0
        let running = entry.glance?.running ?? 0
        return OrbPicture(turn: Double(entry.step) * 0.35, unread: unread, running: running, needsYou: entry.glance?.needsYou ?? false)
    }
}

/// A drawn orb: a soft sphere, points on a globe turned by `turn`
/// radians, and orbiting dots. Each point and dot is its own view placed
/// with an offset, because WidgetKit animates a view's position, size and
/// opacity between entries but not a Canvas or a custom Animatable (tried
/// first: every step was a one-frame jump).
struct OrbPicture: View {
    let turn: Double
    let unread: Int
    let running: Int
    let needsYou: Bool

    private struct Point: Identifiable { let id: Int; let x: Double; let y: Double; let z: Double }

    /// The globe's points at this turn, in unit coordinates.
    private var points: [Point] {
        var out: [Point] = []
        var id = 0
        for lat in stride(from: -60.0, through: 60.0, by: 30.0) {
            for lon in stride(from: 0.0, to: 360.0, by: 36.0) {
                let la = lat * .pi / 180, lo = lon * .pi / 180 + turn
                let x0 = cos(la) * sin(lo), y0 = sin(la), z0 = cos(la) * cos(lo)
                // Tilted toward the viewer, so the rings curve.
                let tilt = 0.35
                out.append(Point(id: id, x: x0, y: y0 * cos(tilt) - z0 * sin(tilt), z: y0 * sin(tilt) + z0 * cos(tilt)))
                id += 1
            }
        }
        return out
    }

    var body: some View {
        GeometryReader { geo in
            let r = min(geo.size.width, geo.size.height) / 2
            let glow = needsYou ? Color(red: 1, green: 0.58, blue: 0.24) : Color(red: 0.62, green: 0.58, blue: 0.95)
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [glow.opacity(0.55), glow.opacity(0.05)], center: .center, startRadius: 0, endRadius: r * 0.6))
                    .frame(width: r * 1.1, height: r * 1.1)
                ForEach(points) { p in
                    let size = 2.4 + 2.6 * max(0, p.z)
                    Circle()
                        .fill(Color.white.opacity(0.25 + 0.55 * max(0, p.z)))
                        .frame(width: size, height: size)
                        .offset(x: p.x * r * 0.86, y: -p.y * r * 0.86)
                }
                let kinds = Array(repeating: true, count: min(unread, 12)) + Array(repeating: false, count: min(running, 6))
                ForEach(Array(kinds.enumerated()), id: \.offset) { i, isNotice in
                    let a = Double(i) / Double(max(kinds.count, 1)) * 2 * .pi + turn * 1.6
                    let color = isNotice ? Color(red: 1, green: 0.58, blue: 0.24) : Color(red: 0.40, green: 0.70, blue: 1.0)
                    ZStack {
                        Circle().fill(color.opacity(0.25)).frame(width: 14, height: 14)
                        Circle().fill(color).frame(width: 7, height: 7)
                    }
                    .offset(x: cos(a) * r * 0.97, y: sin(a) * r * 0.36)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Jarvis: \(unread) new, \(running) running")
    }
}
