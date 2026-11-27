// Pieces of Home's Money card (Dylan 2026-11-26: no net worth, metrics he'd
// actually keep an eye on). Phone and iPad only; Money never shows on the
// TV, Watch or kiosk.
import SwiftUI
import JarvisKit

/// The month's spending as a ring against the budget, with a small tick
/// where it should be by today, then what's left a day and how it compares
/// with last month by now.
struct MonthSpendHeadline: View {
    let spending: Money.Spending
    var now = Date()

    private var budget: Double { spending.budget ?? 0 }
    private var over: Bool { budget > 0 && spending.thisMonth > budget }
    private var fill: Double { budget > 0 ? min(1, spending.thisMonth / budget) : 0 }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            if budget > 0 { ring.frame(width: 84, height: 84) }
            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(TodayWording.dollars(spending.thisMonth))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(over ? Theme.rose : Theme.frost)
                    Text(budget > 0 ? "spent of \(TodayWording.dollars(budget))" : "spent this month")
                        .font(.caption).foregroundStyle(Theme.frostDim)
                }
                if let ahead = spending.aheadOfPace(now: now) {
                    paceLine(ahead)
                }
                if let perDay = spending.leftPerDay(now: now) {
                    Text("\(TodayWording.dollars(perDay)) a day left")
                        .font(.subheadline.weight(.semibold)).monospacedDigit()
                }
                if let last = spending.lastMonthToDate {
                    Text(Self.versusLast(spending.thisMonth - last))
                        .font(.caption).foregroundStyle(Theme.frostFaint)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    /// The budget ring: the fill is what's spent, the white tick is where
    /// an even month would be by today.
    private var ring: some View {
        let pace = budget > 0 ? min(1, (spending.pace(now: now) ?? 0) / budget) : 0
        return ZStack {
            Circle().stroke(Color.white.opacity(0.1), lineWidth: 10)
            Circle()
                .trim(from: 0, to: max(0.001, fill))
                .stroke(over ? Theme.rose : Theme.glacier, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            // Where spending would be by today on an even month.
            Capsule().fill(Color.white.opacity(0.85))
                .frame(width: 3, height: 16)
                .offset(y: -37)
                .rotationEffect(.degrees(360 * pace))
            Text("\(Int((spending.thisMonth / max(budget, 1) * 100).rounded()))%")
                .font(.subheadline.weight(.semibold)).monospacedDigit()
        }
    }

    /// "On pace", "$120 ahead of pace" (rose) or "$80 under pace" (green).
    private func paceLine(_ ahead: Double) -> some View {
        let tint: Color
        let words: String
        if abs(ahead) < 25 {
            tint = Theme.frostDim
            words = "On pace"
        } else if ahead > 0 {
            tint = Theme.rose
            words = "\(TodayWording.dollars(ahead)) ahead of pace"
        } else {
            tint = Theme.moss
            words = "\(TodayWording.dollars(-ahead)) under pace"
        }
        return Label(words, systemImage: ahead > 25 ? "arrow.up.right" : "checkmark")
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
    }

    /// "$140 more than last month by now" or "$90 less than …".
    static func versusLast(_ difference: Double) -> String {
        if abs(difference) < 1 { return "Same as last month by now" }
        let word = difference > 0 ? "more" : "less"
        return "\(TodayWording.dollars(abs(difference))) \(word) than last month by now"
    }
}

/// One category: name, a bar against its budget (or the biggest category
/// when it has none), and the dollars; rose once past its budget.
struct CategoryBar: View {
    let category: Money.Category
    let top: Double

    private var budget: Double { category.budget ?? 0 }
    private var over: Bool { budget > 0 && category.spent > budget }
    private var fill: Double {
        if budget > 0 { return min(1, category.spent / budget) }
        return min(1, category.spent / max(top, 1))
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(category.name).font(.caption).foregroundStyle(Theme.frostDim)
                .lineLimit(1).frame(width: 92, alignment: .leading)
            Capsule().fill(Color.white.opacity(0.08)).frame(height: 6)
                .overlay(alignment: .leading) {
                    GeometryReader { area in
                        Capsule().fill(over ? Theme.rose : Theme.glacier.opacity(budget > 0 ? 1 : 0.6))
                            .frame(width: area.size.width * fill)
                    }
                }
            Text(budget > 0 ? "\(TodayWording.dollars(category.spent))/\(TodayWording.dollars(budget))" : TodayWording.dollars(category.spent))
                .font(.caption).monospacedDigit()
                .foregroundStyle(over ? Theme.rose : Theme.frostDim)
        }
        .accessibilityElement(children: .combine)
    }
}
