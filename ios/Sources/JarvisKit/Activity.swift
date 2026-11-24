// The iPhone's Activity card: more than steps from Apple Health (Dylan,
// 2026-11-24: "the health section on iphone app only pulls my steps…
// maybe theres more that can be pulled?"). Pure numbers and words here,
// read on the phone by App/ActivitySync.swift; nothing is sent anywhere.
import Foundation

/// What the card shows. Every number is optional: Health may have none.
public struct ActivityGlance: Equatable, Sendable {
    /// Today's Move ring: active energy burned and his goal, in kcal.
    public var moveKcal: Double?
    public var moveGoal: Double?
    /// Today's Exercise ring, in minutes, and its goal (30 by default).
    public var exerciseMin: Double?
    public var exerciseGoal: Double?
    /// Today's Stand ring, in hours, and its goal (12 by default).
    public var standHours: Double?
    public var standGoal: Double?
    /// The last 7 days, oldest first; today last (so far today).
    public var steps: [Double] = []
    /// Daily resting heart rate, bpm, oldest first (days with none left out).
    public var restingHR: [Double] = []
    /// Daily average heart rate variability (SDNN), ms, oldest first.
    public var hrv: [Double] = []
    /// Body weight readings over the last 30 days, kg, oldest first.
    public var weightKg: [Double] = []
    /// The latest cardio fitness reading, mL/kg/min.
    public var vo2Max: Double?
    /// Today's walking heart rate average, bpm.
    public var walkingHR: Double?
    /// Flights climbed today.
    public var flights: Double?

    public init() {}

    /// True when Health gave nothing at all (show a short line instead).
    public var isEmpty: Bool {
        moveKcal == nil && exerciseMin == nil && standHours == nil && steps.isEmpty && restingHR.isEmpty
            && hrv.isEmpty && weightKg.isEmpty && vo2Max == nil && walkingHR == nil && flights == nil
    }

    /// How full a ring is (0…1, capped), or nil without a value or goal.
    public static func fill(_ value: Double?, goal: Double?) -> Double? {
        guard let value, let goal, goal > 0 else { return nil }
        return min(1, max(0, value / goal))
    }

    /// Values scaled to 0…1 for a sparkline, with a little headroom so a
    /// flat week doesn't sit on the floor. Fewer than 2 values: empty.
    public static func normalized(_ values: [Double]) -> [Double] {
        guard values.count >= 2, let low = values.min(), let high = values.max() else { return [] }
        let span = high - low
        guard span > 0 else { return values.map { _ in 0.5 } }
        return values.map { 0.1 + 0.8 * ($0 - low) / span }
    }

    /// "↓ 3 vs last week": the latest against the average of the ones
    /// before it, rounded; nil with fewer than 3 values or no change.
    public static func change(_ values: [Double], unit: String = "") -> String? {
        guard values.count >= 3, let last = values.last else { return nil }
        let before = values.dropLast()
        let average = before.reduce(0, +) / Double(before.count)
        let delta = (last - average).rounded()
        guard delta != 0 else { return nil }
        let arrow = delta > 0 ? "↑" : "↓"
        return "\(arrow) \(Int(abs(delta)))\(unit) vs week"
    }

    /// Kilograms as pounds with one decimal: "162.4 lb".
    public static func pounds(_ kg: Double) -> String {
        String(format: "%.1f lb", kg * 2.204_622_6)
    }

    /// "1.2 lb down in 30 days" from the first and last readings.
    public static func weightChange(_ kg: [Double]) -> String? {
        guard kg.count >= 2, let first = kg.first, let last = kg.last else { return nil }
        let lb = (last - first) * 2.204_622_6
        guard abs(lb) >= 0.1 else { return "Steady over 30 days" }
        return String(format: "%.1f lb %@ in 30 days", abs(lb), lb < 0 ? "down" : "up")
    }

    /// A whole number with a thousands separator: "8,412".
    public static func whole(_ value: Double) -> String {
        let format = NumberFormatter()
        format.numberStyle = .decimal
        format.maximumFractionDigits = 0
        format.locale = Locale(identifier: "en_US")
        return format.string(from: NSNumber(value: value.rounded())) ?? "\(Int(value.rounded()))"
    }
}
