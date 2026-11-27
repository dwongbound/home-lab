// Today's food as a card, the same on Home, the iPad kiosk and the Apple TV
// (Dylan, 2026-11-26: "Diet should just show like the other ones like
// sleep"): layered rings for calories, protein, fat and carbs, what's left, then the macros as
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

    /// The calorie colour; the macros use the same colours as their bars.
    private static let calories = Color(red: 0.98, green: 0.36, blue: 0.45)

    /// Fat and carbs goals as the Diet screen reads them: Jarvis's, else
    /// the cut's 55 g and 175 g.
    private var fatGoal: Double? { nutrition.fatGoal ?? DietGoals.defaultFat }
    private var carbsGoal: Double? { nutrition.carbsGoal ?? DietGoals.defaultCarbs }

    /// All four rings, always (Dylan, 2026-11-27: it showed calories alone
    /// when Jarvis sent no fat or carbs goal). Nothing eaten yet is an
    /// empty track; protein with no goal stays an empty track too.
    private var rings: [(fill: Double, tint: Color)] {
        func fill(_ value: Double?, _ goal: Double?) -> Double {
            guard let goal, goal > 0 else { return 0 }
            return min(1, (value ?? 0) / goal)
        }
        return [
            (fill(nutrition.eaten, nutrition.goal), over ? Theme.rose : Self.calories),
            (fill(nutrition.protein, nutrition.proteinGoal), Theme.glacier),
            (fill(nutrition.fat, fatGoal), Theme.ember),
            (fill(nutrition.carbs, carbsGoal), Theme.moss),
        ]
    }

    var body: some View {
        HStack(alignment: .center, spacing: 18 * scale) {
            // Layered rings, outside in: calories, protein, fat, carbs
            // (Dylan, 2026-11-26: "a layered ring not just calories").
            ZStack {
                ForEach(Array(rings.enumerated()), id: \.offset) { index, ring in
                    let line = 8 * scale
                    let inset = CGFloat(index) * (line + 2 * scale) + line / 2
                    Circle().stroke(ring.tint.opacity(0.2), lineWidth: line).padding(inset)
                    Circle()
                        .trim(from: 0, to: ring.fill)
                        .stroke(ring.tint, style: StrokeStyle(lineWidth: line, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(inset)
                }
            }
            .frame(width: 92 * scale, height: 92 * scale)
            VStack(alignment: .leading, spacing: 7 * scale) {
                HStack(alignment: .firstTextBaseline, spacing: 6 * scale) {
                    Text(ActivityGlance.whole(abs(nutrition.left)))
                        .font(.system(size: 22 * scale, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(over ? Theme.rose : ink)
                    Text(over ? "kcal over" : "kcal left").font(.system(size: 13 * scale)).foregroundStyle(dim)
                }
                macro("Protein", nutrition.protein ?? 0, nutrition.proteinGoal, Theme.glacier)
                macro("Fat", nutrition.fat ?? 0, fatGoal, Theme.ember)
                macro("Carbs", nutrition.carbs ?? 0, carbsGoal, Theme.moss)
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
