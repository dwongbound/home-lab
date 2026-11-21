// When each chat message was sent (Dylan, 2026-11-20: "when i drag from
// right to left, i should see the minute time of when the message was sent.
// there should be a light line break with the date in the middle betwen
// messages to indicate days (local time)"). Messages' style: the time as
// "7:32 PM", and day lines reading Today, Yesterday, the weekday for the
// last week, then "Fri, Nov 20" ("…, 2025" in another year). All on the
// device's own clock.
import Foundation

public enum ChatTime {
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
