// The Diet screen's data and arithmetic (Dylan, 2026-11-18: "Can you
// recreate this page for my diet?", from a food-log app's Today screen,
// redrawn in Jarvis's own look). Read-only: one day's goals, totals and
// items, and the week's calorie rings. The page server passes Jarvis's
// numbers through GET /api/jarvis/nutrition/day and /week; every number may
// be null, and a missing goal hides its target and bar. Days and hours are
// Pacific time, like Jarvis.
import Foundation

/// Calories, protein, fat and carbs; any of them may be missing.
public struct Macros: Decodable, Equatable, Sendable {
    public var calories: Double?
    public var protein: Double?
    public var fat: Double?
    public var carbs: Double?

    public init(calories: Double? = nil, protein: Double? = nil, fat: Double? = nil, carbs: Double? = nil) {
        self.calories = calories; self.protein = protein; self.fat = fat; self.carbs = carbs
    }

    enum CodingKeys: String, CodingKey { case calories, protein, fat, carbs }

    /// Each number read leniently: null, missing or not a number reads as nil.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        calories = Diet.number(c, .calories)
        protein = Diet.number(c, .protein)
        fat = Diet.number(c, .fat)
        carbs = Diet.number(c, .carbs)
    }
}

/// One thing eaten.
public struct FoodItem: Decodable, Identifiable, Equatable, Sendable {
    public let id: String
    /// When it was logged (ISO 8601, Pacific offset).
    public let at: String
    public let name: String
    /// "1 bowl"; nil when the meal had several items.
    public let portion: String?
    public let macros: Macros

    public init(id: String, at: String, name: String, portion: String? = nil, macros: Macros) {
        self.id = id; self.at = at; self.name = name; self.portion = portion; self.macros = macros
    }

    enum CodingKeys: String, CodingKey { case id, at, name, portion }

    /// Needs an id and a name; the id may come as a number.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let text = try? c.decode(String.self, forKey: .id) {
            id = text
        } else {
            id = String(try c.decode(Int.self, forKey: .id))
        }
        at = ((try? c.decodeIfPresent(String.self, forKey: .at)) ?? nil) ?? ""
        name = try c.decode(String.self, forKey: .name)
        let portion = ((try? c.decodeIfPresent(String.self, forKey: .portion)) ?? nil)?.trimmingCharacters(in: .whitespaces)
        self.portion = (portion?.isEmpty ?? true) ? nil : portion
        macros = try Macros(from: decoder)
    }
}

/// One day: goals, totals and what was eaten, in time order.
public struct NutritionDay: Decodable, Equatable, Sendable {
    public let date: String
    public let goals: Macros
    public let totals: Macros
    /// Active energy from Health, when known.
    public let burned: Double?
    public let items: [FoodItem]

    public init(date: String, goals: Macros, totals: Macros, burned: Double? = nil, items: [FoodItem]) {
        self.date = date; self.goals = goals; self.totals = totals; self.burned = burned; self.items = items
    }

    enum CodingKeys: String, CodingKey { case date, goals, totals, items }
    enum TotalsKeys: String, CodingKey { case burned }

    /// Reads what's there; a bad item is skipped, not fatal.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = ((try? c.decodeIfPresent(String.self, forKey: .date)) ?? nil) ?? ""
        goals = ((try? c.decodeIfPresent(Macros.self, forKey: .goals)) ?? nil) ?? Macros()
        let items = (((try? c.decodeIfPresent([Maybe].self, forKey: .items)) ?? nil) ?? []).compactMap(\.item)
        self.items = items
        // Totals as sent; any that's missing is added up from the items.
        let sent = ((try? c.decodeIfPresent(Macros.self, forKey: .totals)) ?? nil) ?? Macros()
        let added = Diet.totals(items)
        totals = Macros(calories: sent.calories ?? added.calories, protein: sent.protein ?? added.protein, fat: sent.fat ?? added.fat, carbs: sent.carbs ?? added.carbs)
        if let t = try? c.nestedContainer(keyedBy: TotalsKeys.self, forKey: .totals) {
            burned = Diet.number(t, .burned)
        } else {
            burned = nil
        }
    }

    /// One item that may or may not decode.
    private struct Maybe: Decodable {
        let item: FoodItem?
        init(from decoder: Decoder) throws { item = try? FoodItem(from: decoder) }
    }

    /// Nothing logged.
    public var isEmpty: Bool { items.isEmpty }
}

/// One day of the week strip: calories eaten (nil = nothing logged, an
/// empty ring rather than zero) and the goal.
public struct WeekDay: Decodable, Equatable, Sendable, Identifiable {
    public let date: String
    public let calories: Double?
    public let goal: Double?
    public var id: String { date }

    public init(date: String, calories: Double?, goal: Double?) {
        self.date = date; self.calories = calories; self.goal = goal
    }

    enum CodingKeys: String, CodingKey { case date, calories, goal }

    /// Reads leniently; only the date is needed.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(String.self, forKey: .date)
        calories = Diet.number(c, .calories)
        goal = Diet.number(c, .goal)
    }

    /// How full the ring is, 0...1; nil (an empty ring) when nothing was logged.
    public var ring: Double? { Diet.fraction(calories, of: goal) }
}

/// The week, Monday first.
public struct NutritionWeek: Decodable, Equatable, Sendable {
    public let start: String
    public let days: [WeekDay]

    public init(start: String, days: [WeekDay]) {
        self.start = start; self.days = days
    }
}

/// An hour of the timeline with food in it.
public struct DietHour: Identifiable, Equatable, Sendable {
    /// 0...23, Pacific.
    public let hour: Int
    public let items: [FoodItem]
    public var id: Int { hour }

    /// The hour's subtotal.
    public var totals: Macros { Diet.totals(items) }

    /// "9 AM", "12 PM".
    public var label: String { Diet.hourLabel(hour) }
}

public enum Diet {
    /// Dylan's (and Jarvis's) clock.
    public static let timeZone = TimeZone(identifier: "America/Los_Angeles")!

    /// A Pacific calendar.
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.firstWeekday = 2
        return calendar
    }

    /// A number field, or nil for null, missing or not a number.
    static func number<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> Double? {
        if let d = try? c.decodeIfPresent(Double.self, forKey: key) { return d.isFinite ? d : nil }
        return nil
    }

    /// The sum of what's there; a total stays nil only when no item has it.
    public static func totals(_ items: [FoodItem]) -> Macros {
        func sum(_ pick: (Macros) -> Double?) -> Double? {
            let values = items.compactMap { pick($0.macros) }
            return values.isEmpty ? nil : values.reduce(0, +)
        }
        return Macros(calories: sum(\.calories), protein: sum(\.protein), fat: sum(\.fat), carbs: sum(\.carbs))
    }

    /// How much of a goal is eaten, 0...1 (full when over); nil without a goal or a value.
    public static func fraction(_ eaten: Double?, of goal: Double?) -> Double? {
        guard let eaten, let goal, goal > 0 else { return nil }
        return min(1, max(0, eaten / goal))
    }

    /// True when eaten is past the goal.
    public static func isOver(_ eaten: Double?, goal: Double?) -> Bool {
        guard let eaten, let goal, goal > 0 else { return false }
        return eaten > goal
    }

    /// An ISO time, with or without fractions of a second.
    public static func date(_ iso: String) -> Date? {
        let plain = ISO8601DateFormatter()
        if let d = plain.date(from: iso) { return d }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: iso)
    }

    /// The Pacific hour (0...23) an item was logged in; nil when unreadable.
    public static func hour(of item: FoodItem) -> Int? {
        date(item.at).map { calendar.component(.hour, from: $0) }
    }

    /// The items grouped by hour, earliest first. Hours with nothing are
    /// left out so the page isn't mostly empty; an item with no readable
    /// time goes in the last group.
    public static func hours(_ items: [FoodItem]) -> [DietHour] {
        var byHour: [Int: [FoodItem]] = [:]
        var unknown: [FoodItem] = []
        for item in items {
            if let hour = hour(of: item) { byHour[hour, default: []].append(item) } else { unknown.append(item) }
        }
        var out = byHour.keys.sorted().map { DietHour(hour: $0, items: byHour[$0] ?? []) }
        if !unknown.isEmpty {
            if let last = out.popLast() {
                out.append(DietHour(hour: last.hour, items: last.items + unknown))
            } else {
                out.append(DietHour(hour: 0, items: unknown))
            }
        }
        return out
    }

    /// "12 AM", "9 AM", "12 PM", "1 PM".
    public static func hourLabel(_ hour: Int) -> String {
        let h = ((hour % 24) + 24) % 24
        let twelve = h % 12 == 0 ? 12 : h % 12
        return "\(twelve) \(h < 12 ? "AM" : "PM")"
    }

    /// The Pacific hour now.
    public static func currentHour(now: Date = Date()) -> Int {
        calendar.component(.hour, from: now)
    }

    /// A day as "YYYY-MM-DD" in Pacific time.
    public static func dayString(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// "YYYY-MM-DD" back to noon that day, Pacific (noon keeps DST edges away).
    public static func day(_ text: String) -> Date? {
        let bits = text.split(separator: "-").compactMap { Int($0) }
        guard bits.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: bits[0], month: bits[1], day: bits[2], hour: 12))
    }

    /// The Monday of the week holding `date`, as "YYYY-MM-DD".
    public static func weekStart(of date: String) -> String? {
        guard let day = day(date) else { return nil }
        let weekday = calendar.component(.weekday, from: day)
        let back = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -back, to: day).map(dayString)
    }

    /// A day moved by `days`.
    public static func shift(_ date: String, by days: Int) -> String? {
        guard let day = day(date) else { return nil }
        return calendar.date(byAdding: .day, value: days, to: day).map(dayString)
    }

    /// "Mo", "Tu"… for a date.
    public static func weekdayInitials(_ date: String) -> String {
        guard let day = day(date) else { return "" }
        return ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"][calendar.component(.weekday, from: day) - 1]
    }

    /// The date's day number, "18".
    public static func dayNumber(_ date: String) -> String {
        guard let last = date.split(separator: "-").last, let n = Int(last) else { return "" }
        return String(n)
    }

    /// The screen's title: "Today", "Yesterday", or "Tue, Nov 18".
    public static func title(_ date: String, now: Date = Date()) -> String {
        let today = dayString(now)
        if date == today { return "Today" }
        if date == shift(today, by: -1) { return "Yesterday" }
        guard let day = day(date) else { return date }
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US")
        format.timeZone = timeZone
        format.dateFormat = "EEE, MMM d"
        return format.string(from: day)
    }

    /// A whole number for the screen: "1052", "—" when missing.
    public static func whole(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(Int(value.rounded()))
    }

    /// "54P 24F 67C", leaving out what's missing.
    public static func macroLine(_ m: Macros) -> String {
        [(m.protein, "P"), (m.fat, "F"), (m.carbs, "C")]
            .compactMap { value, letter in value.map { "\(Int($0.rounded()))\(letter)" } }
            .joined(separator: " ")
    }
}

/// Sample data for the simulator and previews (`-demoDiet`), shaped like
/// the reference screen.
public enum DemoDiet {
    /// A day with lunch at noon and a smoothie at 2 PM, on `date`.
    public static func day(_ date: String) -> NutritionDay {
        let items = [
            FoodItem(id: "1", at: "\(date)T12:20:00-08:00", name: "Chicken Burrito Bowl", portion: "1 bowl", macros: Macros(calories: 675, protein: 54, fat: 24, carbs: 67)),
            FoodItem(id: "2", at: "\(date)T12:20:00-08:00", name: "Taco, Tortilla Or Nacho Chips, Salted", portion: "1 serving", macros: Macros(calories: 236, protein: 4, fat: 10, carbs: 34)),
            FoodItem(id: "3", at: "\(date)T14:05:00-08:00", name: "Strawberry Orange Mango Wellness Smoothie", portion: "1 bottle", macros: Macros(calories: 140, protein: 1, fat: 0, carbs: 34)),
        ]
        return NutritionDay(date: date, goals: Macros(calories: 1750, protein: 140), totals: Diet.totals(items), burned: 312, items: items)
    }

    /// A week with a few days logged and the rest empty.
    public static func week(_ start: String) -> NutritionWeek {
        let eaten: [Double?] = [1620, 1980, 1051, nil, nil, nil, nil]
        let days = (0..<7).map { i in
            WeekDay(date: Diet.shift(start, by: i) ?? start, calories: eaten[i], goal: 1750)
        }
        return NutritionWeek(start: start, days: days)
    }
}
