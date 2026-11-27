// The iPhone's Activity card on Home (Dylan, 2026-11-24: more than steps
// from Health; he likes graphs over words, 2026-11-21): the three rings,
// a week of steps as bars, then small tiles with a sparkline each for
// resting heart rate, heart rate variability and weight, and plain
// numbers for cardio fitness, walking heart rate and flights.
import SwiftUI
import JarvisKit

struct ActivityCard: View {
    @ObservedObject var sync: ActivitySync
    /// Yesterday's steps from Jarvis, shown until he allows more.
    let fallbackSteps: Int?
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// The rings' colours, Apple's order: Move, Exercise, Stand.
    static let move = Color(red: 0.98, green: 0.36, blue: 0.45)
    static let exercise = Color(red: 0.62, green: 0.93, blue: 0.29)
    static let stand = Color(red: 0.36, green: 0.86, blue: 0.95)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "figure.walk")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.glacier)
                Text("Activity").font(.subheadline.weight(.semibold))
                Spacer()
                if sync.asked {
                    Text("Details  ›").font(.caption).foregroundStyle(Theme.frostDim)
                }
            }
            if !sync.asked {
                askRow
            } else if let glance = sync.glance, !glance.isEmpty {
                content(glance)
            } else if sync.glance != nil {
                Text("Nothing from Apple Health yet today.").font(.subheadline).foregroundStyle(Theme.frostDim)
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel()
        .task { await sync.refresh() }
    }

    /// Before he's allowed it: yesterday's steps from Jarvis and one button.
    private var askRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let fallbackSteps {
                Text("\(fallbackSteps.formatted()) steps yesterday").font(.headline).monospacedDigit()
            }
            Text("See your rings, heart, fitness and weight from Apple Health. It stays on this phone.")
                .font(.subheadline)
                .foregroundStyle(Theme.frostDim)
                .fixedSize(horizontal: false, vertical: true)
            Button("Show more") { Task { await sync.allow() } }
                .buttonStyle(.borderedProminent)
                .tint(Theme.glacier)
                .foregroundStyle(Theme.basalt)
                .frame(minHeight: 44)
        }
    }

    @ViewBuilder
    private func content(_ glance: ActivityGlance) -> some View {
        HStack(alignment: .center, spacing: 18) {
            ActivityRings(rings: [
                ActivityGlance.fill(glance.moveKcal, goal: glance.moveGoal) ?? 0,
                ActivityGlance.fill(glance.exerciseMin, goal: glance.exerciseGoal ?? 30) ?? 0,
                ActivityGlance.fill(glance.standHours, goal: glance.standGoal ?? 12) ?? 0,
            ], colors: [Self.move, Self.exercise, Self.stand])
            .frame(width: 92, height: 92)
            VStack(alignment: .leading, spacing: 6) {
                ringLine(glance.moveKcal, goal: glance.moveGoal, unit: "kcal", tint: Self.move)
                ringLine(glance.exerciseMin, goal: glance.exerciseGoal ?? 30, unit: "min", tint: Self.exercise)
                ringLine(glance.standHours, goal: glance.standGoal ?? 12, unit: "hr", tint: Self.stand)
            }
            Spacer(minLength: 0)
        }
        if glance.steps.count >= 2 {
            StepBars(steps: glance.steps)
        }
        let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: sizeClass == .regular ? 3 : 2)
        LazyVGrid(columns: columns, spacing: 10) {
            if let last = glance.restingHR.last {
                trendTile("Resting heart", value: "\(Int(last.rounded())) bpm", note: ActivityGlance.change(glance.restingHR, unit: " bpm"), line: glance.restingHR, tint: Theme.rose, symbol: "heart.fill")
            }
            if let last = glance.hrv.last {
                trendTile("Heart variability", value: "\(Int(last.rounded())) ms", note: ActivityGlance.change(glance.hrv, unit: " ms"), line: glance.hrv, tint: Theme.glacier, symbol: "waveform.path.ecg")
            }
            if let last = glance.weightKg.last {
                trendTile("Weight", value: ActivityGlance.pounds(last), note: ActivityGlance.weightChange(glance.weightKg), line: glance.weightKg, tint: Theme.ember, symbol: "scalemass.fill")
            }
            if let vo2 = glance.vo2Max {
                trendTile("Cardio fitness", value: String(format: "%.1f", vo2), note: "VO₂ max", line: [], tint: Theme.moss, symbol: "lungs.fill")
            }
            if let walking = glance.walkingHR {
                trendTile("Walking heart", value: "\(Int(walking.rounded())) bpm", note: "Today's average", line: [], tint: Theme.rose, symbol: "figure.walk")
            }
            if let flights = glance.flights, flights > 0 {
                trendTile("Flights", value: ActivityGlance.whole(flights), note: "Climbed today", line: [], tint: Theme.moss, symbol: "figure.stairs")
            }
        }
    }

    /// "412 / 600 kcal" in the ring's colour.
    private func ringLine(_ value: Double?, goal: Double?, unit: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Text(value.map { ActivityGlance.whole($0) } ?? "–")
                .font(.headline.weight(.bold))
                .foregroundStyle(tint)
                .monospacedDigit()
            if let goal {
                Text("/ \(ActivityGlance.whole(goal)) \(unit)").font(.footnote).foregroundStyle(Theme.frostDim)
            } else {
                Text(unit).font(.footnote).foregroundStyle(Theme.frostDim)
            }
        }
    }

    /// A small tile: icon and name, the number, a note, and a sparkline.
    private func trendTile(_ title: String, value: String, note: String?, line: [Double], tint: Color, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.frostDim)
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .monospacedDigit()
            if let note {
                Text(note).font(.caption2).foregroundStyle(Theme.frostFaint).lineLimit(1)
            }
            let points = ActivityGlance.normalized(line)
            if !points.isEmpty {
                Sparkline(values: points, tint: tint).frame(height: 22)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.04)))
        .accessibilityElement(children: .combine)
    }
}

/// Three nested rings, outermost first, each filled 0…1.
struct ActivityRings: View {
    let rings: [Double]
    let colors: [Color]

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let line = side * 0.11
            ZStack {
                ForEach(Array(rings.enumerated()), id: \.offset) { index, fill in
                    let inset = CGFloat(index) * (line + 3)
                    Circle()
                        .stroke(colors[index].opacity(0.2), lineWidth: line)
                        .padding(inset + line / 2)
                    Circle()
                        .trim(from: 0, to: max(0.001, fill))
                        .stroke(colors[index], style: StrokeStyle(lineWidth: line, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(inset + line / 2)
                }
            }
            .frame(width: side, height: side)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Activity rings")
    }
}

/// Seven days of steps as bars, today brightest, with the day's count.
struct StepBars: View {
    let steps: [Double]

    var body: some View {
        let top = max(steps.max() ?? 1, 1)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Steps").font(.caption.weight(.semibold)).foregroundStyle(Theme.frostDim)
                Spacer()
                if let today = steps.last {
                    Text("\(ActivityGlance.whole(today)) today").font(.caption).foregroundStyle(Theme.frostDim).monospacedDigit()
                }
            }
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, value in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Theme.moss.opacity(index == steps.count - 1 ? 1 : 0.45))
                        .frame(height: max(3, 44 * CGFloat(value / top)))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 44, alignment: .bottom)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Steps this week")
    }
}
