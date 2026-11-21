// The pieces every sleep surface is drawn from (Home on iPhone and iPad,
// the detail screen, the iPad kiosk and the TV), in Apple Health's style:
// a score ring, one stage bar in the system sleep colours, the score's
// parts as short bars, small vital tiles and a 7 night trend. What they
// show comes from JarvisKit SleepCard. `scale` sizes them for the screen:
// 1 on a phone, about 1.6 on the kiosk, 2.4 on a TV across the room.
//
// Plain fills only (no blur, nothing animating), so they cost nothing on
// the iPad's lighter path. Shared with the TV target (project.yml).
import SwiftUI
import JarvisKit

/// The text colours the pieces draw with: frost on the app's night sky,
/// the TV's lamp palette by day (dark ink on paper).
struct SleepInk {
    var ink: Color = Theme.frost
    var dim: Color = Theme.frostDim
    var faint: Color = Theme.frostFaint
    /// The empty part of a ring or bar.
    var track: Color = Color.white.opacity(0.10)
}

private struct SleepInkKey: EnvironmentKey {
    static let defaultValue = SleepInk()
}

extension EnvironmentValues {
    var sleepInk: SleepInk {
        get { self[SleepInkKey.self] }
        set { self[SleepInkKey.self] = newValue }
    }
}

enum SleepStyle {
    /// Apple Health's sleep stage colours.
    static func color(_ stage: String) -> Color {
        switch stage {
        case "deep": return Color(red: 0.21, green: 0.20, blue: 0.64)
        case "core": return Color(red: 0.20, green: 0.47, blue: 0.96)
        case "rem": return Color(red: 0.36, green: 0.78, blue: 0.98)
        case "awake": return Color(red: 1.00, green: 0.50, blue: 0.40)
        default: return Color(red: 0.45, green: 0.62, blue: 0.80)
        }
    }

    /// The score's band, as Jarvis named it.
    static func band(_ band: String?) -> Color {
        switch band {
        case "great": return Color(red: 0.35, green: 0.85, blue: 0.55)
        case "good": return Color(red: 0.36, green: 0.78, blue: 0.98)
        case "fair": return Color(red: 1.00, green: 0.80, blue: 0.30)
        case "poor": return Color(red: 1.00, green: 0.50, blue: 0.40)
        default: return Color(red: 0.62, green: 0.58, blue: 0.95)
        }
    }

    /// The sleep accent, for icons and titles.
    static let accent = Color(red: 0.62, green: 0.58, blue: 0.95)
}

/// The score, large, in a ring that fills to it, with its band under it.
struct SleepScoreRing: View {
    @Environment(\.sleepInk) private var colors
    let card: SleepCard
    var scale: CGFloat = 1

    var body: some View {
        let tint = SleepStyle.band(card.band)
        ZStack {
            Circle().stroke(colors.track, lineWidth: 9 * scale)
            if let score = card.score {
                Circle()
                    .trim(from: 0, to: CGFloat(max(0, min(100, score))) / 100)
                    .stroke(tint, style: StrokeStyle(lineWidth: 9 * scale, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            VStack(spacing: 0) {
                Text(card.score.map(String.init) ?? card.asleep ?? "")
                    .font(.system(size: (card.score == nil ? 17 : 30) * scale, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                if let word = card.bandWord {
                    Text(word)
                        .font(.system(size: 12 * scale, weight: .semibold, design: .rounded))
                        .foregroundStyle(tint)
                }
            }
            .padding(10 * scale)
        }
        .frame(width: 96 * scale, height: 96 * scale)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.score.map { "Sleep score \($0)" + (card.bandWord.map { ", \($0)" } ?? "") } ?? "Sleep")
    }
}

/// One bar split into the night's stages, with a tiny legend.
struct SleepStageBar: View {
    @Environment(\.sleepInk) private var colors
    let shares: [SleepCard.StageShare]
    var scale: CGFloat = 1
    var legend = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6 * scale) {
            GeometryReader { geo in
                HStack(spacing: 2 * scale) {
                    ForEach(shares, id: \.stage) { share in
                        Rectangle()
                            .fill(SleepStyle.color(share.stage))
                            .frame(width: max(2, (geo.size.width - CGFloat(shares.count - 1) * 2 * scale) * share.fraction))
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 10 * scale)
            if legend {
                HStack(spacing: 12 * scale) {
                    ForEach(shares, id: \.stage) { share in
                        HStack(spacing: 4 * scale) {
                            Circle().fill(SleepStyle.color(share.stage)).frame(width: 7 * scale, height: 7 * scale)
                            Text(share.label)
                                .font(.system(size: 11 * scale, weight: .medium, design: .rounded))
                                .foregroundStyle(colors.dim)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(shares.map { "\($0.label) \(Int(($0.fraction * 100).rounded())) percent" }.joined(separator: ", "))
    }
}

/// The score's three parts as short labelled bars; a part not counted yet
/// says so in words.
struct SleepPartBars: View {
    @Environment(\.sleepInk) private var colors
    let parts: [SleepCard.Part]
    var scale: CGFloat = 1

    var body: some View {
        VStack(spacing: 7 * scale) {
            ForEach(parts) { part in
                HStack(spacing: 10 * scale) {
                    Text(part.label)
                        .font(.system(size: 12 * scale, weight: .medium, design: .rounded))
                        .foregroundStyle(colors.dim)
                        .frame(width: 96 * scale, alignment: .leading)
                    if let value = part.value {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(colors.track)
                                Capsule().fill(SleepStyle.accent)
                                    .frame(width: geo.size.width * CGFloat(max(0, min(1, value / part.outOf))))
                            }
                        }
                        .frame(height: 6 * scale)
                    } else {
                        Spacer(minLength: 0)
                    }
                    Text(part.words)
                        .font(.system(size: 12 * scale, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(part.value == nil ? colors.faint : colors.ink)
                        .fixedSize()
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// Small tiles for the vitals that exist (none when there are none).
struct SleepVitalTiles: View {
    @Environment(\.sleepInk) private var colors
    let vitals: [SleepCard.Vital]
    var scale: CGFloat = 1
    var columns = 2

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8 * scale), count: columns), alignment: .leading, spacing: 8 * scale) {
            ForEach(vitals) { vital in
                VStack(alignment: .leading, spacing: 3 * scale) {
                    Label(vital.label, systemImage: vital.symbol)
                        .font(.system(size: 11 * scale, weight: .medium, design: .rounded))
                        .foregroundStyle(colors.dim)
                    Text(vital.value)
                        .font(.system(size: 15 * scale, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10 * scale)
                .background(RoundedRectangle(cornerRadius: 12 * scale, style: .continuous).fill(colors.track))
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// The week: a small bar per night's score, last night highlighted.
struct SleepTrendBars: View {
    @Environment(\.sleepInk) private var colors
    let trend: [SleepCard.TrendBar]
    var scale: CGFloat = 1

    var body: some View {
        HStack(alignment: .bottom, spacing: 8 * scale) {
            ForEach(trend) { bar in
                VStack(spacing: 4 * scale) {
                    if let score = bar.score {
                        RoundedRectangle(cornerRadius: 3 * scale, style: .continuous)
                            .fill(bar.isLast ? SleepStyle.accent : colors.faint.opacity(0.6))
                            .frame(width: 14 * scale, height: max(4, 44 * scale * CGFloat(score) / 100))
                    } else {
                        // No score that night: a dot, not a zero bar.
                        Circle().fill(colors.faint).frame(width: 5 * scale, height: 5 * scale)
                    }
                    Text(bar.day)
                        .font(.system(size: 10 * scale, weight: bar.isLast ? .bold : .medium, design: .rounded))
                        .foregroundStyle(bar.isLast ? colors.ink : colors.faint)
                }
            }
        }
        .frame(height: 62 * scale, alignment: .bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Last \(trend.count) nights: " + trend.map { "\($0.day) \($0.score.map(String.init) ?? "no score")" }.joined(separator: ", "))
    }
}

/// Score ring beside time asleep and bed and wake times: the card's top.
struct SleepHeadline: View {
    @Environment(\.sleepInk) private var colors
    let card: SleepCard
    var scale: CGFloat = 1
    /// Across the room (the TV): no small captions.
    var tenFeet = false

    var body: some View {
        HStack(spacing: 18 * scale) {
            SleepScoreRing(card: card, scale: scale)
            VStack(alignment: .leading, spacing: 4 * scale) {
                if let asleep = card.asleep {
                    HStack(alignment: .firstTextBaseline, spacing: 8 * scale) {
                        Text(asleep)
                            .font(.system(size: 26 * scale, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .fixedSize()
                        if let note = card.asleepNote {
                            Text(note)
                                .font(.system(size: 12 * scale, weight: .semibold, design: .rounded))
                                .foregroundStyle(note == "Short" ? SleepStyle.color("awake") : SleepStyle.band("great"))
                        }
                    }
                    if !tenFeet { Text("asleep")
                        .font(.system(size: 12 * scale, design: .rounded))
                        .foregroundStyle(colors.dim) }
                }
                if let bed = card.bedtime, let wake = card.wake {
                    Label("\(bed) – \(wake)", systemImage: "bed.double.fill")
                        .lineLimit(1)
                        .fixedSize()
                        .font(.system(size: 13 * scale, weight: .medium, design: .rounded))
                        .foregroundStyle(colors.ink)
                        .labelStyle(.titleAndIcon)
                }
                if !tenFeet, let estimate = card.estimate {
                    Text(estimate)
                        .font(.system(size: 11 * scale, design: .rounded))
                        .foregroundStyle(colors.faint)
                }
            }
            Spacer(minLength: 0)
        }
    }
}
