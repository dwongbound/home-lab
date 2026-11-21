// The PC's pieces, drawn (Dylan, 2026-11-21: "i like these graphs and
// stuff vs words"): a ring per gauge, coloured by who holds what when
// Jarvis says, a sparkline of the last samples, and a stacked bar with a
// legend for the breakdowns. Home's System panel, its drawer, the iPad
// kiosk and the TV all use these; `scale` sizes them (1 on a phone, about
// 2 on the TV) and the ink comes from SleepInk like the sleep pieces.
// Shared with the TV target (project.yml).
import SwiftUI
import JarvisKit

enum SystemStyle {
    /// Colours by NAME (SystemBreakdown.colorSlot): the same holder is
    /// the same colour on Home, in the drawer and on the TV, and no two
    /// share one. "Everything else" grey, free space the empty track,
    /// reclaimable memory a light wash of its colour.
    static let palette: [Color] = [
        Color(red: 0.40, green: 0.70, blue: 1.00),
        Color(red: 0.62, green: 0.58, blue: 0.95),
        Color(red: 0.91, green: 0.69, blue: 0.42),
        Color(red: 0.58, green: 0.84, blue: 0.68),
        Color(red: 0.94, green: 0.57, blue: 0.60),
        Color(red: 0.45, green: 0.85, blue: 0.85),
        Color(red: 0.98, green: 0.84, blue: 0.40),
        Color(red: 0.80, green: 0.55, blue: 0.90),
        Color(red: 0.70, green: 0.88, blue: 0.40),
        Color(red: 0.55, green: 0.62, blue: 0.85),
        Color(red: 1.00, green: 0.66, blue: 0.80),
        Color(red: 0.40, green: 0.78, blue: 0.62),
    ]
    static let other = Color.gray.opacity(0.75)

    static func color(_ slice: SystemSlice, in breakdown: SystemBreakdown, track: Color) -> Color {
        if slice.isFree { return track }
        guard let slot = breakdown.colorSlot(slice, slots: palette.count) else { return other }
        return slice.isReclaimable ? palette[slot].opacity(0.38) : palette[slot]
    }

    /// A gauge's own colour when it has no breakdown.
    static func tint(_ kind: SystemGauge.Kind) -> Color {
        switch kind {
        case .gpu: return palette[0]
        case .ram: return palette[1]
        case .disk: return palette[2]
        case .cpu: return palette[3]
        }
    }
}

/// A ring filled to how full the gauge is; with a breakdown, the fill is
/// split into its holders' colours. The percent in the middle.
struct SystemRing: View {
    @Environment(\.sleepInk) private var ink
    let gauge: SystemGauge
    var breakdown: SystemBreakdown? = nil
    var scale: CGFloat = 1
    var size: CGFloat = 64

    var body: some View {
        let line = 7 * scale
        ZStack {
            Circle().stroke(ink.track, lineWidth: line)
            ForEach(arcs, id: \.id) { arc in
                Circle().trim(from: arc.from, to: arc.to)
                    .stroke(arc.color, style: StrokeStyle(lineWidth: line, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
            Text(gauge.percentText)
                .font(.system(size: 15 * scale, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(ink.ink)
                .minimumScaleFactor(0.7)
        }
        .frame(width: size * scale, height: size * scale)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(gauge.title) \(gauge.percentText) full, \(gauge.amountText)")
    }

    private struct Arc { let id: String; let from: CGFloat; let to: CGFloat; let color: Color }

    /// One arc per holder, in order, up to how full the gauge is; else one.
    private var arcs: [Arc] {
        guard let breakdown, breakdown.totalGb > 0, breakdown.growsToGb == nil else {
            return [Arc(id: "all", from: 0, to: gauge.fraction, color: SystemStyle.tint(gauge.kind))]
        }
        var at: CGFloat = 0
        var out: [Arc] = []
        for slice in breakdown.slices where !slice.isFree {
            let share = CGFloat(slice.gb / breakdown.totalGb)
            let end = min(CGFloat(gauge.fraction), at + share)
            guard end > at else { break }
            // A hairline gap between holders, so neighbours read apart.
            out.append(Arc(id: slice.id, from: at, to: max(at, end - 0.004), color: SystemStyle.color(slice, in: breakdown, track: ink.track)))
            at = end
        }
        return out
    }
}

/// The last samples as a small line with a soft fill under it (0...1).
struct Sparkline: View {
    let values: [Double]
    var tint: Color
    var scale: CGFloat = 1

    var body: some View {
        GeometryReader { geo in
            if values.count >= 2 {
                let points = values.enumerated().map { i, v in
                    CGPoint(x: geo.size.width * CGFloat(i) / CGFloat(values.count - 1),
                            y: geo.size.height * (1 - CGFloat(v)))
                }
                ZStack {
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: geo.size.height))
                        points.forEach { p.addLine(to: $0) }
                        p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                        p.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [tint.opacity(0.35), tint.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    Path { p in
                        p.move(to: points[0])
                        points.dropFirst().forEach { p.addLine(to: $0) }
                    }
                    .stroke(tint, style: StrokeStyle(lineWidth: 1.6 * scale, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// One gauge: ring, name, amount and its sparkline.
struct SystemGaugeTile: View {
    @Environment(\.sleepInk) private var ink
    let gauge: SystemGauge
    var breakdown: SystemBreakdown? = nil
    var scale: CGFloat = 1
    var ringSize: CGFloat = 64

    var body: some View {
        VStack(spacing: 6 * scale) {
            SystemRing(gauge: gauge, breakdown: breakdown, scale: scale, size: ringSize)
            Text(gauge.title)
                .font(.system(size: 13 * scale, weight: .semibold, design: .rounded))
                .foregroundStyle(ink.ink)
            Text(gauge.amountText)
                .font(.system(size: 11 * scale, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(ink.dim)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Sparkline(values: gauge.history, tint: SystemStyle.tint(gauge.kind), scale: scale)
                .frame(height: 18 * scale)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// A breakdown as one stacked bar and a legend under it.
struct SystemBreakdownBar: View {
    @Environment(\.sleepInk) private var ink
    let breakdown: SystemBreakdown
    var scale: CGFloat = 1
    /// How many legend rows (the rest are still in the bar).
    var legendLimit = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 10 * scale) {
            GeometryReader { geo in
                // Slices too thin to see are left to the legend.
                let shown = breakdown.barSlices
                HStack(spacing: 2 * scale) {
                    ForEach(shown) { slice in
                        Rectangle()
                            .fill(SystemStyle.color(slice, in: breakdown, track: ink.track))
                            .frame(width: max(2, (geo.size.width - CGFloat(shown.count - 1) * 2 * scale) * CGFloat(slice.gb / max(breakdown.barTotal, 0.001))))
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 12 * scale)
            VStack(alignment: .leading, spacing: 7 * scale) {
                ForEach(breakdown.slices.prefix(legendLimit)) { slice in
                    HStack(spacing: 10 * scale) {
                        Circle().fill(slice.isFree ? ink.faint : SystemStyle.color(slice, in: breakdown, track: ink.track))
                            .frame(width: 9 * scale, height: 9 * scale)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(slice.name).font(.system(size: 14 * scale, weight: .medium, design: .rounded)).foregroundStyle(slice.isFree ? ink.dim : ink.ink)
                            if let role = slice.isReclaimable ? [slice.role, "reclaimable"].compactMap { $0 }.joined(separator: " · ") : slice.role {
                                Text(role).font(.system(size: 11 * scale, design: .rounded)).foregroundStyle(ink.dim)
                            }
                        }
                        Spacer(minLength: 8)
                        Text(slice.sizeText).font(.system(size: 14 * scale, design: .rounded)).monospacedDigit().foregroundStyle(ink.dim)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

/// The gauges in a row: three or four across.
struct SystemGaugeRow: View {
    let snapshot: Snapshot
    var scale: CGFloat = 1
    var ringSize: CGFloat = 64

    var body: some View {
        HStack(alignment: .top, spacing: 10 * scale) {
            ForEach(snapshot.systemGauges) { gauge in
                SystemGaugeTile(gauge: gauge, breakdown: snapshot.breakdown(for: gauge.kind), scale: scale, ringSize: ringSize)
            }
        }
    }
}

/// "Checked 10:34 AM": when the PC was read (the snapshot's own time).
/// Orange with its age once it's over a minute old. A fixed slot and
/// monospaced digits, so the header never shifts as it changes.
struct SystemCheckedLabel: View {
    @Environment(\.sleepInk) private var ink
    let generatedAt: String
    var scale: CGFloat = 1

    var body: some View {
        // Re-read every 15 s so the age keeps counting while nothing new comes.
        TimelineView(.periodic(from: .now, by: 15)) { context in
            if let words = SystemChecked.words(generatedAt: generatedAt, now: context.date) {
                Text(words.text)
                    .font(.system(size: 11 * scale, weight: words.stale ? .semibold : .regular, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(words.stale ? Color(red: 1, green: 0.58, blue: 0.24) : ink.dim)
                    .lineLimit(1)
                    .frame(minWidth: 112 * scale, alignment: .trailing)
            }
        }
    }
}
