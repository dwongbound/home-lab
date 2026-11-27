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

/// One day of activity for the Activity screen (Dylan, 2026-11-26: details
/// when the card is tapped, by day like Diet and Sleep). Read on the phone
/// from Health; nothing is sent anywhere.
public struct ActivityDay: Equatable, Sendable, Identifiable {
    /// "2026-11-26" on the phone's clock.
    public let day: String
    public var moveKcal: Double?
    public var moveGoal: Double?
    public var exerciseMin: Double?
    public var exerciseGoal: Double?
    public var standHours: Double?
    public var standGoal: Double?
    public var steps: Double?
    public var flights: Double?
    public var restingHR: Double?
    public var hrv: Double?
    public var walkingHR: Double?
    /// Steps in each hour, 24 of them, once the day is opened; empty before.
    public var hourlySteps: [Double] = []

    public var id: String { day }

    public init(day: String) { self.day = day }

    /// Move, Exercise and Stand as 0…1 (Exercise 30 min and Stand 12 h by default).
    public var rings: [Double] {
        [ActivityGlance.fill(moveKcal, goal: moveGoal) ?? 0,
         ActivityGlance.fill(exerciseMin, goal: exerciseGoal ?? 30) ?? 0,
         ActivityGlance.fill(standHours, goal: standGoal ?? 12) ?? 0]
    }

    /// True when Health had anything for the day.
    public var recorded: Bool {
        moveKcal != nil || exerciseMin != nil || standHours != nil || steps != nil
    }

    /// How many of the three rings closed.
    public var ringsClosed: Int { rings.filter { $0 >= 1 }.count }

    /// "2026-11-26" for a date on the given calendar.
    public static func key(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// The start of that day, or nil for a bad key.
    public static func date(_ key: String, calendar: Calendar = .current) -> Date? {
        let bits = key.split(separator: "-").compactMap { Int($0) }
        guard bits.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: bits[0], month: bits[1], day: bits[2]))
    }

    /// "Today", "Yesterday", else "Tuesday, Nov 24".
    public static func heading(_ key: String, now: Date = Date(), calendar: Calendar = .current) -> String {
        guard let date = date(key, calendar: calendar) else { return key }
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) { return "Yesterday" }
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = calendar.timeZone
        format.dateFormat = "EEEE, MMM d"
        return format.string(from: date)
    }

    /// "Tu" and "24" for the week row.
    public static func weekday(_ key: String, calendar: Calendar = .current) -> String {
        guard let date = date(key, calendar: calendar) else { return "" }
        return ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"][calendar.component(.weekday, from: date) - 1]
    }

    public static func dayNumber(_ key: String) -> String {
        guard let last = key.split(separator: "-").last, let n = Int(last) else { return "" }
        return "\(n)"
    }

    /// The last `count` day keys ending today, oldest first.
    public static func keys(count: Int, now: Date = Date(), calendar: Calendar = .current) -> [String] {
        let today = calendar.startOfDay(for: now)
        return (0..<count).reversed().compactMap { back in
            calendar.date(byAdding: .day, value: -back, to: today).map { key($0, calendar: calendar) }
        }
    }

    /// Average steps over the recorded days, rounded; nil with none.
    public static func averageSteps(_ days: [ActivityDay]) -> Double? {
        let steps = days.compactMap(\.steps)
        guard !steps.isEmpty else { return nil }
        return (steps.reduce(0, +) / Double(steps.count)).rounded()
    }
}
