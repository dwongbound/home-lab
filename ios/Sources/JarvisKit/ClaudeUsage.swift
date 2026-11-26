// Jarvis's Claude use from snapshot `claudeUsage` (Jarvis GET /claude/usage):
// plan limits (session and weekly, read off his own calls) and tokens per
// day and per kind of work. Dollars cover background jobs only. Shown on the
// app's Claude screen (Dylan 2026-11-26: usage over money where there is one).
import Foundation

public struct ClaudeUsage: Decodable, Sendable, Equatable {
    /// One plan limit: how much of it is used and when it starts over.
    public struct Limit: Decodable, Sendable, Equatable, Identifiable {
        /// "session" or "weekly".
        public let name: String
        /// 0-100.
        public let usedPct: Int
        public let resetsAt: String?
        public var id: String { name }
    }

    /// One kind of work today ("chat", "talk", "nightly"…).
    public struct Kind: Decodable, Sendable, Equatable, Identifiable {
        public let kind: String
        public let usd: Double?
        public let calls: Int?
        public let tokens: Int?
        public var id: String { kind }
    }

    /// One of the last seven days, oldest first.
    public struct Day: Decodable, Sendable, Equatable, Identifiable {
        public let date: String
        public let usd: Double?
        public let tokens: Int?
        public var id: String { date }
    }

    /// Nil until Jarvis has seen his limits (just after a restart) or from an older Jarvis.
    public let limits: [Limit]?
    public let today: [Kind]
    public let days: [Day]

    enum CodingKeys: String, CodingKey { case limits, today, days }

    /// Lists that won't decode read as empty, missing limits as nil.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        limits = (try? c.decodeIfPresent([Limit].self, forKey: .limits)) ?? nil
        today = ((try? c.decodeIfPresent([Kind].self, forKey: .today)) ?? nil) ?? []
        days = ((try? c.decodeIfPresent([Day].self, forKey: .days)) ?? nil) ?? []
    }

    /// The session limit, then the weekly one, whichever Jarvis sent.
    public var rings: [Limit] {
        let order = ["session", "weekly"]
        return (limits ?? []).filter { order.contains($0.name) }.sorted { order.firstIndex(of: $0.name)! < order.firstIndex(of: $1.name)! }
    }

    /// True when any day has a token count, so the bars show tokens; else dollars.
    public var hasTokens: Bool { days.contains { $0.tokens != nil } }

    /// Today's kinds, most tokens (or dollars) first.
    public var kindsByUse: [Kind] {
        today.sorted { ($0.tokens ?? 0, $0.usd ?? 0) > ($1.tokens ?? 0, $1.usd ?? 0) }
    }

    /// "Session", "Weekly".
    public static func limitName(_ name: String) -> String {
        name.prefix(1).uppercased() + name.dropFirst()
    }

    /// "Resets 6:10 PM" today, "Resets Mon 9 AM" later; nil without a time.
    public static func resetWords(_ raw: String?, now: Date = Date(), timeZone: TimeZone = .current) -> String? {
        guard let raw, let date = ISODate.parse(raw) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US")
        format.timeZone = timeZone
        let onTheHour = calendar.component(.minute, from: date) == 0
        let time = onTheHour ? "h a" : "h:mm a"
        format.dateFormat = calendar.isDate(date, inSameDayAs: now) ? time : "EEE " + time
        return "Resets " + format.string(from: date)
    }

    /// "1.2M", "640K", "900".
    public static func tokenWords(_ tokens: Int) -> String {
        if tokens >= 1_000_000 { return String(format: "%.1fM", Double(tokens) / 1_000_000) }
        if tokens >= 1_000 { return "\(tokens / 1_000)K" }
        return "\(tokens)"
    }

    /// "Chat", "Nightly", "Start of day" from Jarvis's kind names.
    public static func kindName(_ kind: String) -> String {
        let words = kind.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }

    /// One letter for a day's bar: "M", "T"….
    public static func dayLetter(_ date: String) -> String {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US")
        format.timeZone = TimeZone(identifier: "UTC")
        format.dateFormat = "yyyy-MM-dd"
        guard let day = format.date(from: date) else { return "" }
        format.dateFormat = "EEEEE"
        return format.string(from: day)
    }
}

/// One Claude project thread from the cloud digest.
public struct ClaudeThread: Decodable, Sendable, Identifiable, Equatable {
    public let id: String
    public let title: String
    /// working, blocked, review_ready, done, failed or stopped.
    public let state: String
    public let lastActivityAt: String?

    /// "Working", "Needs you", "Review", "Done", "Failed", "Stopped".
    public var stateWord: String {
        switch state {
        case "working": return "Working"
        case "blocked": return "Needs you"
        case "review_ready": return "Review"
        case "done": return "Done"
        case "failed": return "Failed"
        default: return "Stopped"
        }
    }
}
