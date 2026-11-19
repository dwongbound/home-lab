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

    enum CodingKeys: String, CodingKey { case calories, protein, fat, carbs, fatGoal, carbsGoal }

    /// Each number read leniently: null, missing or not a number reads as nil.
    /// A goals object may name fat and carbs as fatGoal and carbsGoal.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        calories = Diet.number(c, .calories)
        protein = Diet.number(c, .protein)
        fat = Diet.number(c, .fat) ?? Diet.number(c, .fatGoal)
        carbs = Diet.number(c, .carbs) ?? Diet.number(c, .carbsGoal)
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
    /// True when the meal was logged from a photo (a thumbnail shows).
    public let hasPhoto: Bool

    public init(id: String, at: String, name: String, portion: String? = nil, macros: Macros, hasPhoto: Bool = false) {
        self.id = id; self.at = at; self.name = name; self.portion = portion; self.macros = macros; self.hasPhoto = hasPhoto
    }

    enum CodingKeys: String, CodingKey { case id, at, name, portion, hasPhoto }

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
        hasPhoto = ((try? c.decodeIfPresent(Bool.self, forKey: .hasPhoto)) ?? nil) ?? false
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
    /// Grams of protein eaten (nil when nothing was logged).
    public let protein: Double?
    public let proteinGoal: Double?
    /// Grams of fat and carbs eaten and their goals, when Jarvis sends them.
    public var fat: Double? = nil
    public var carbs: Double? = nil
    public var fatGoal: Double? = nil
    public var carbsGoal: Double? = nil
    public var id: String { date }

    public init(date: String, calories: Double?, goal: Double?, protein: Double? = nil, proteinGoal: Double? = nil) {
        self.date = date; self.calories = calories; self.goal = goal; self.protein = protein; self.proteinGoal = proteinGoal
    }

    enum CodingKeys: String, CodingKey { case date, calories, goal, protein, proteinGoal, fat, fatGoal, carbs, carbsGoal }

    /// Reads leniently; only the date is needed.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(String.self, forKey: .date)
        calories = Diet.number(c, .calories)
        goal = Diet.number(c, .goal)
        protein = Diet.number(c, .protein)
        proteinGoal = Diet.number(c, .proteinGoal)
        fat = Diet.number(c, .fat)
        carbs = Diet.number(c, .carbs)
        fatGoal = Diet.number(c, .fatGoal)
        carbsGoal = Diet.number(c, .carbsGoal)
    }

    /// The outer ring, calories, 0...1; nil (an empty track) when nothing was logged.
    public var ring: Double? { Diet.fraction(calories, of: goal) }

    /// The inner ring, protein, 0...1 (full when the goal is met); nil for an empty track.
    public var proteinRing: Double? { Diet.fraction(protein, of: proteinGoal) }

    /// The same day with protein filled in from a loaded day, when the
    /// week answer had none (an older Jarvis).
    public func withProtein(from day: NutritionDay?) -> WeekDay {
        guard protein == nil, let day, !day.isEmpty else { return self }
        return WeekDay(date: date, calories: calories ?? day.totals.calories, goal: goal ?? day.goals.calories, protein: day.totals.protein, proteinGoal: proteinGoal ?? day.goals.protein)
    }
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

/// GET /api/jarvis/nutrition/days: up to 14 days, newest first, empty days
/// included, and the date of the first meal ever logged.
public struct NutritionDays: Decodable, Equatable, Sendable {
    public let days: [NutritionDay]
    public let earliest: String?

    public init(days: [NutritionDay], earliest: String?) {
        self.days = days; self.earliest = earliest
    }
}

/// The Diet screen's endless timeline (Dylan, 2026-11-19: "the data should
/// be an infinite timeline … as I scroll it should go back in the past and
/// highlight the date accordingly"; "each entry should get its own slot").
public enum DietTimeline {
    /// One block of the timeline: a day with food, or one or more empty days.
    public enum Block: Equatable, Sendable, Identifiable {
        /// A day: its header carries the totals; each item is its own entry.
        case day(NutritionDay)
        /// One to three empty days each get a slim row of their own.
        case empty(date: String)
        /// More than three empty days in a row collapse into one row,
        /// newest first: `from` is the newest, `to` the oldest.
        case emptyRun(from: String, to: String, count: Int)

        public var id: String {
            switch self {
            case .day(let day): return day.date
            case .empty(let date): return date
            case .emptyRun(let from, _, _): return from
            }
        }

        /// The newest date the block covers.
        public var newest: String { id }
    }

    /// How many empty days in a row stay separate rows.
    public static let longestEmptyRun = 3

    /// The blocks for days newest first: days with food as they are, empty
    /// days as slim rows, runs longer than three collapsed into one.
    public static func blocks(_ days: [NutritionDay]) -> [Block] {
        var out: [Block] = []
        var run: [String] = []
        func flush() {
            if run.count > longestEmptyRun, let first = run.first, let last = run.last {
                out.append(.emptyRun(from: first, to: last, count: run.count))
            } else {
                out.append(contentsOf: run.map { Block.empty(date: $0) })
            }
            run = []
        }
        for day in days {
            if day.isEmpty { run.append(day.date) } else { flush(); out.append(.day(day)) }
        }
        flush()
        return out
    }

    /// The block that holds `date` (for "tap a ring, scroll to that day").
    public static func block(holding date: String, in blocks: [Block]) -> Block? {
        blocks.first { block in
            switch block {
            case .day(let day): return day.date == date
            case .empty(let d): return d == date
            case .emptyRun(let from, let to, _): return date <= from && date >= to
            }
        }
    }

    /// Whether to load more older days: not past the first meal ever, and
    /// not after 30 empty days in a row when Jarvis doesn't say when that was.
    public static func shouldLoadOlder(loaded days: [NutritionDay], earliest: String?) -> Bool {
        guard let oldest = days.last?.date else { return true }
        if let earliest { return oldest > earliest }
        let trailingEmpty = days.reversed().prefix { $0.isEmpty }.count
        return trailingEmpty < 30
    }

    /// The end date for the next page: the day before the oldest held.
    public static func nextEnd(after days: [NutritionDay]) -> String? {
        days.last.flatMap { Diet.shift($0.date, by: -1) }
    }

    /// An item's time on the rail: "12:10 PM" (Pacific); "" when unreadable.
    public static func timeLabel(_ item: FoodItem) -> String {
        guard let date = Diet.date(item.at) else { return "" }
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US")
        format.timeZone = Diet.timeZone
        format.dateFormat = "h:mm a"
        return format.string(from: date)
    }

    /// A collapsed run's words: "Nothing logged Nov 3 – Nov 9".
    public static func runLabel(from: String, to: String) -> String {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US")
        format.timeZone = Diet.timeZone
        format.dateFormat = "MMM d"
        guard let a = Diet.day(to), let b = Diet.day(from) else { return "Nothing logged" }
        return "Nothing logged \(format.string(from: a)) – \(format.string(from: b))"
    }

    /// The week strip's day for VoiceOver: "Wednesday 18, 2300 of 1750
    /// calories, 127 of 140 grams protein".
    public static func ringLabel(_ day: WeekDay) -> String {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US")
        format.timeZone = Diet.timeZone
        format.dateFormat = "EEEE d"
        let name = Diet.day(day.date).map(format.string(from:)) ?? day.date
        guard let calories = day.calories else { return "\(name), nothing logged" }
        var words = "\(name), \(Diet.whole(calories)) of \(Diet.whole(day.goal)) calories"
        if let protein = day.protein { words += ", \(Diet.whole(protein)) of \(Diet.whole(day.proteinGoal)) grams protein" }
        return words
    }
}

/// Meal photos in the Diet timeline (Dylan, 2026-11-19): a thumbnail on an
/// entry that has one, the full photo on tap. GET
/// /api/jarvis/nutrition/photo/{id}?size=thumb is a ~320 px JPEG; without
/// size it's the full photo. A meal's photo never changes, so both are
/// cached by id and size.
public enum MealPhotos {
    /// True for an id safe to put in the path: letters, digits, "-" and "_".
    public static func isId(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 80 && id.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }

    /// Only an item that says it has a photo, with a safe id, is ever asked for.
    public static func shouldFetch(_ item: FoodItem) -> Bool {
        item.hasPhoto && isId(item.id)
    }

    /// The path under the server, nil for an unsafe id.
    public static func path(id: String) -> String? {
        isId(id) ? "api/jarvis/nutrition/photo/\(id)" : nil
    }

    /// The query: size=thumb for a thumbnail, none for the full photo.
    public static func query(thumb: Bool) -> [String: String] {
        thumb ? ["size": "thumb"] : [:]
    }

    /// The cache key: "<id>-thumb" or "<id>-full".
    public static func cacheKey(id: String, thumb: Bool) -> String {
        "\(id)-\(thumb ? "thumb" : "full")"
    }
}

/// Dylan's daily limits on a cut (2026-11-19): carbs 175 g and fat 55 g,
/// used until Jarvis sends fatGoal and carbsGoal himself.
public enum DietGoals {
    public static let defaultCarbs = 175.0
    public static let defaultFat = 55.0

    /// The day's goals with fat and carbs filled in when Jarvis has none.
    public static func effective(_ goals: Macros) -> Macros {
        Macros(calories: goals.calories, protein: goals.protein, fat: goals.fat ?? defaultFat, carbs: goals.carbs ?? defaultCarbs)
    }

    /// For a limit (fat, carbs): "35 g left", or "12 g over" (over = true).
    /// The one caption under a total in the Diet card, the same shape in
    /// every column (Dylan, 2026-11-19: the card read as two mismatched
    /// pairs): "of 1,750" or "of 55 g" while under; on a limit (calories,
    /// fat and carbs, since he's cutting) past its goal, "120 over" or
    /// "12 g over", flagged so the number and bar turn orange. Protein is a
    /// target, so reaching it is never "over". "no goal" without one.
    public static func caption(eaten: Double?, goal: Double?, unit: String, limit: Bool) -> (words: String, over: Bool) {
        guard let goal, goal > 0 else { return ("no goal", false) }
        let gap = Int(((eaten ?? 0) - goal).rounded())
        let suffix = unit.isEmpty ? "" : " \(unit)"
        if limit, gap > 0 { return ("\(Diet.whole(Double(gap)))\(suffix) over", true) }
        return ("of \(Diet.whole(goal))\(suffix)", false)
    }

    public static func limitLine(eaten: Double?, goal: Double?) -> (words: String, over: Bool)? {
        guard let goal, goal > 0 else { return nil }
        let used = eaten ?? 0
        let gap = Int((goal - used).rounded())
        return gap >= 0 ? ("\(gap) g left", false) : ("\(-gap) g over", true)
    }
}
