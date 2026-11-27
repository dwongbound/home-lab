// When each chat message was sent (Dylan, 2026-11-20: "when i drag from
// right to left, i should see the minute time of when the message was sent.
// there should be a light line break with the date in the middle betwen
// messages to indicate days (local time)"). Messages' style: the time as
// "7:32 PM", and day lines reading Today, Yesterday, the weekday for the
// last week, then "Fri, Nov 20" ("…, 2025" in another year). All on the
// device's own clock.
import Foundation

public enum ChatTime {
    /// A history turn's `at`, in whatever form Jarvis wrote it (Dylan,
    /// 2026-11-21: no times showed on his phone, though the demo had them).
    /// ISO 8601 with or without seconds, with any number of fraction digits,
    /// "T" or a space, with an offset or "Z", or with none (then Jarvis's own
    /// clock, Pacific); or a Unix time in seconds or milliseconds. Nil when
    /// it can't be read: that row shows no time rather than a wrong one.
    public static func parse(_ raw: String, zone: TimeZone = TimeZone(identifier: "America/Los_Angeles")!) -> Date? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        if let number = Double(text), number > 1_000_000_000 {
            return Date(timeIntervalSince1970: number > 100_000_000_000 ? number / 1000 : number)
        }
        let pattern = #"^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})(?::(\d{2})(?:[.,](\d+))?)?\s*(Z|[+-]\d{2}:?\d{2})?$"#
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        func group(_ i: Int) -> String? { Range(m.range(at: i), in: text).map { String(text[$0]) } }
        var parts = DateComponents()
        parts.year = Int(group(1)!); parts.month = Int(group(2)!); parts.day = Int(group(3)!)
        parts.hour = Int(group(4)!); parts.minute = Int(group(5)!)
        parts.second = group(6).flatMap(Int.init) ?? 0
        var calendar = Calendar(identifier: .gregorian)
        if let offset = group(8) {
            if offset == "Z" {
                calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            } else {
                let digits = offset.dropFirst().replacingOccurrences(of: ":", with: "")
                let seconds = (Int(digits.prefix(2)) ?? 0) * 3600 + (Int(digits.suffix(2)) ?? 0) * 60
                calendar.timeZone = TimeZone(secondsFromGMT: offset.hasPrefix("-") ? -seconds : seconds)!
            }
        } else {
            calendar.timeZone = zone
        }
        guard var date = calendar.date(from: parts) else { return nil }
        if let fraction = group(7) { date += Double("0." + fraction) ?? 0 }
        return date
    }

    /// "7:32 PM".
    public static func clock(_ date: Date, calendar: Calendar = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = calendar.timeZone
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }

    /// The day line's words for a message sent at `date`.
    public static func dayLabel(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        let startToday = calendar.startOfDay(for: now)
        let startThen = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: startThen, to: startToday).day ?? 99
        if days == 1 { return "Yesterday" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = calendar.timeZone
        if (2...6).contains(days) {
            f.dateFormat = "EEEE"
        } else if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            f.dateFormat = "EEE, MMM d"
        } else {
            f.dateFormat = "EEE, MMM d, yyyy"
        }
        return f.string(from: date)
    }

    /// Where the day lines go: true for the first dated message, and for
    /// each one on a different local day from the dated message before it.
    /// Messages with no time (approval cards) never start a day.
    public static func dayBreaks(_ dates: [Date?], calendar: Calendar = .current) -> [Bool] {
        var last: Date?
        return dates.map { date in
            guard let date else { return false }
            defer { last = date }
            guard let last else { return true }
            return !calendar.isDate(date, inSameDayAs: last)
        }
    }
}
