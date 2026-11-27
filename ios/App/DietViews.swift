// Today's food as a card, the same on Home, the iPad kiosk and the Apple TV
// (Dylan, 2026-11-26: "Diet should just show like the other ones like
// sleep"): a calorie ring with what's left, then protein, fat and carbs as
// bars against their goals. From the snapshot's `nutrition`.
import SwiftUI
import JarvisKit

struct DietHeadline: View {
    let nutrition: Nutrition
    /// 1 on the phone; bigger for across the room.
    var scale: CGFloat = 1
    var ink: Color = Theme.frost
    var dim: Color = Theme.frostDim

    private var over: Bool { nutrition.left < 0 }

    var body: some View {
        HStack(alignment: .center, spacing: 18 * scale) {
            ZStack {
                Circle().stroke(dim.opacity(0.2), lineWidth: 9 * scale)
                Circle()
                    .trim(from: 0, to: nutrition.goal > 0 ? min(1, nutrition.eaten / nutrition.goal) : 0)
                    .stroke(over ? Theme.rose : Theme.moss, style: StrokeStyle(lineWidth: 9 * scale, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text(ActivityGlance.whole(abs(nutrition.left)))
                        .font(.system(size: 20 * scale, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(over ? Theme.rose : ink)
                    Text(over ? "over" : "left").font(.system(size: 11 * scale)).foregroundStyle(dim)
                }
            }
            .frame(width: 84 * scale, height: 84 * scale)
            VStack(alignment: .leading, spacing: 7 * scale) {
                Text("\(ActivityGlance.whole(nutrition.eaten)) of \(ActivityGlance.whole(nutrition.goal)) kcal")
                    .font(.system(size: 15 * scale, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(ink)
                macro("Protein", nutrition.protein, nutrition.proteinGoal, Theme.glacier)
                macro("Fat", nutrition.fat, nutrition.fatGoal, Theme.ember)
                macro("Carbs", nutrition.carbs, nutrition.carbsGoal, Theme.moss)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// One macro: name, a bar against its goal, grams.
    @ViewBuilder
    private func macro(_ name: String, _ value: Double?, _ goal: Double?, _ tint: Color) -> some View {
        if let value {
            HStack(spacing: 8 * scale) {
                Text(name).font(.system(size: 12 * scale)).foregroundStyle(dim).frame(width: 52 * scale, alignment: .leading)
                Capsule().fill(dim.opacity(0.2)).frame(width: 90 * scale, height: 6 * scale)
                    .overlay(alignment: .leading) {
                        Capsule().fill(tint).frame(width: 90 * scale * CGFloat(goal.map { $0 > 0 ? min(1, value / $0) : 0 } ?? 0), height: 6 * scale)
                    }
                Text(goal.map { "\(Int(value.rounded()))/\(Int($0.rounded())) g" } ?? "\(Int(value.rounded())) g")
                    .font(.system(size: 12 * scale))
                    .monospacedDigit()
                    .foregroundStyle(dim)
            }
        }
    }
}
