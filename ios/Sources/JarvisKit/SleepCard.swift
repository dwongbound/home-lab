// What every sleep surface shows (Home on iPhone and iPad, the detail
// screen, the iPad kiosk slide and the TV slide), worked out once so they
// all say the same thing. Apple Health style: the score large with its band,
// time asleep, bedtime and wake, one stage bar, the score's three parts,
// vitals only when they exist, and the week's trend.
//
// Words follow Jarvis: the band is his (never worked out here); "Jarvis's
// estimate" when the score is his; a part he couldn't count yet reads "Not
// enough nights yet", never 0. Nothing null is ever drawn as 0 or a dash.
import Foundation

public struct SleepCard: Equatable, Sendable {
    /// What there is to show.
    public enum Kind: Equatable, Sendable {
        /// Last night, in full.
        case night
        /// An older Jarvis: only minutes asleep (cloud.health.sleep).
        case minutesOnly
        /// Nothing for last night (the trend may still show).
        case noNight
    }

    public struct StageShare: Equatable, Sendable {
        /// deep, core, rem, awake or unspecified.
        public let stage: String
        public let label: String
        public let fraction: Double
    }

    public struct Part: Equatable, Sendable, Identifiable {
        public var id: String { label }
        public let label: String
        /// nil: not counted yet.
        public let value: Double?
        public let outOf: Double
        /// "32 of 50", or "Not enough nights yet".
        public let words: String
    }

    public struct Vital: Equatable, Sendable, Identifiable {
        public var id: String { label }
        public let label: String
        public let value: String
        public let symbol: String
    }

    public struct TrendBar: Equatable, Sendable, Identifiable {
        public var id: String { night }
        public let night: String
        /// "Th": the morning's weekday.
        public let day: String
        public let score: Int?
        public let isLast: Bool
    }

    public let kind: Kind
    public let score: Int?
    /// "great", "good", "fair", "poor" (colour), and its word.
    public let band: String?
    public let bandWord: String?
    /// "Jarvis's estimate" when the score is his.
    public let estimate: String?
    /// "7h 12m".
    public let asleep: String?
    /// "Short" under 6 hours, "On target" from 7.
    public let asleepNote: String?
    /// "11:20 PM", "6:58 AM".
    public let bedtime: String?
    public let wake: String?
    public let stages: [StageShare]
    public let parts: [Part]
    public let vitals: [Vital]
    /// Oldest on the left, last night highlighted.
    public let trend: [TrendBar]
    /// "Avg 7h 02m" over the trend's nights with a time.
    public let trendAverage: String?
    /// "Last night", or "Thursday night" for an older latest night.
    public let whenWords: String?
    /// Plain words when there's no night at all.
    public let emptyWords: String?

    /// Whether there's anything to show at all.
    public var isEmpty: Bool { kind == .noNight && trend.isEmpty }

    public static let stageOrder = ["deep", "core", "rem", "unspecified", "awake"]

    /// From the snapshot's `sleep`, falling back to `cloud.health.sleep`'s
    /// minutes when an older Jarvis sends no slice. `today` is the night
    /// key for last night (the Pacific date of this morning).
    public init(summary: SleepSummary?, fallbackAsleepMinutes: Int?, today: String) {
        let last = summary?.last
        let trendNights = Array((summary?.trend ?? []).prefix(7).reversed())
        trend = trendNights.map { night in
            TrendBar(night: night.night, day: Self.weekday(night.night), score: night.score, isLast: night.night == trendNights.last?.night)
        }
        let times = trendNights.compactMap(\.asleep)
        trendAverage = times.isEmpty ? nil : "Avg " + Self.hours(times.reduce(0, +) / Double(times.count))

        // The latest recorded night is always the one shown (Dylan,
        // 2026-11-21: at 3 AM, not yet asleep, it's still the night before):
        // "Last night" when it's this morning's or yesterday morning's,
        // else its weekday ("Thursday night"), never an empty state just
        // because the clock moved on.
        if let last {
            kind = .night
            whenWords = (last.night == today || last.night == Self.dayBefore(today)) ? "Last night" : Self.weekdayName(last.night) + " night"
            score = last.score
            band = last.scoreBand
            bandWord = last.scoreBand.map { $0.prefix(1).uppercased() + $0.dropFirst() }
            estimate = last.score != nil && last.scoreSource == "jarvis" ? "Jarvis's estimate" : nil
            let asleepMinutes = last.minutes?.asleep
            asleep = asleepMinutes.map(Self.hours)
            asleepNote = asleepMinutes.flatMap(Self.durationNote)
            bedtime = last.bedtime.map(Self.clock)
            wake = last.wake.map(Self.clock)
            stages = Self.shares(last.minutes)
            parts = Self.parts(last.scoreParts)
            vitals = Self.vitals(last.vitals)
            emptyWords = nil
        } else if summary == nil, let minutes = fallbackAsleepMinutes {
            kind = .minutesOnly
            whenWords = "Last night"
            score = nil; band = nil; bandWord = nil; estimate = nil
            asleep = Self.hours(Double(minutes))
            asleepNote = Self.durationNote(Double(minutes))
            bedtime = nil; wake = nil; stages = []; parts = []; vitals = []
            emptyWords = nil
        } else {
            kind = .noNight
            whenWords = nil
            score = nil; band = nil; bandWord = nil; estimate = nil
            asleep = nil; asleepNote = nil; bedtime = nil; wake = nil
            stages = []; parts = []; vitals = []
            emptyWords = "No sleep recorded yet"
        }
    }

    /// "2026-11-20" → "Friday".
    public static func weekdayName(_ night: String) -> String {
        guard let w = SleepNights.window(night) else { return night }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = SleepNights.zone
        f.dateFormat = "EEEE"
        return f.string(from: w.start)
    }

    /// "2026-11-21" → "2026-11-20".
    public static func dayBefore(_ night: String) -> String? {
        guard let w = SleepNights.window(night) else { return nil }
        return SleepNights.key(w.start)
    }

    // MARK: Pieces (also used by the detail screen's list of nights)

    /// 432 → "7h 12m"; under an hour, "45m".
    public static func hours(_ minutes: Double) -> String {
        let total = Int(minutes.rounded())
        let h = total / 60, m = total % 60
        return h == 0 ? "\(m)m" : String(format: "%dh %02dm", h, m)
    }

    /// Under 6 hours is short, 7 or more on target (Jarvis's rule).
    public static func durationNote(_ minutes: Double) -> String? {
        if minutes < 6 * 60 { return "Short" }
        if minutes >= 7 * 60 { return "On target" }
        return nil
    }

    /// "11:20 PM" on the Pacific clock.
    public static func clock(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = SleepNights.zone
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }

    /// "2026-11-20" → "Fr".
    public static func weekday(_ night: String) -> String {
        guard let w = SleepNights.window(night) else { return "" }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = SleepNights.zone
        let index = calendar.component(.weekday, from: w.end) - 1
        return ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"][index]
    }

    /// "Thu, Nov 20" for a night.
    public static func dayTitle(_ night: String) -> String {
        guard let w = SleepNights.window(night) else { return night }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = SleepNights.zone
        f.dateFormat = "EEE, MMM d"
        return f.string(from: w.end)
    }

    /// The stage bar: deep, core, REM, then asleep-unspecified and awake,
    /// as shares of the night; nil minutes and zero stages left out.
    public static func shares(_ minutes: SleepDay.Minutes?) -> [StageShare] {
        guard let m = minutes else { return [] }
        let pieces: [(String, String, Double?)] = [
            ("deep", "Deep", m.deep), ("core", "Core", m.core), ("rem", "REM", m.rem),
            ("unspecified", "Asleep", m.unspecified), ("awake", "Awake", m.awake),
        ]
        let present = pieces.compactMap { p -> (String, String, Double)? in
            guard let v = p.2, v > 0 else { return nil }
            return (p.0, p.1, v)
        }
        let total = present.reduce(0) { $0 + $1.2 }
        guard total > 0 else { return [] }
        return present.map { StageShare(stage: $0.0, label: $0.1, fraction: $0.2 / total) }
    }

    /// The score's parts; a null part reads "Not enough nights yet".
    public static func parts(_ parts: SleepDay.Parts?) -> [Part] {
        guard let p = parts else { return [] }
        func part(_ label: String, _ value: Double?, _ outOf: Double) -> Part {
            Part(label: label, value: value, outOf: outOf,
                 words: value.map { "\(Int($0.rounded())) of \(Int(outOf))" } ?? "Not enough nights yet")
        }
        return [part("Duration", p.duration, 50), part("Consistency", p.consistency, 30), part("Interruptions", p.interruptions, 20)]
    }

    /// Vitals that exist, in one or two words each.
    public static func vitals(_ v: SleepDay.Vitals?) -> [Vital] {
        guard let v else { return [] }
        var out: [Vital] = []
        if let avg = v.heartRate?.avg {
            let low = v.heartRate?.min.map { ", low \(Int($0.rounded()))" } ?? ""
            out.append(Vital(label: "Heart rate", value: "\(Int(avg.rounded())) bpm\(low)", symbol: "heart.fill"))
        }
        if let hrv = v.hrvMs ?? v.hrvRmssdMs {
            out.append(Vital(label: "HRV", value: "\(Int(hrv.rounded())) ms", symbol: "waveform.path.ecg"))
        }
        if let breaths = v.respiratoryRate {
            out.append(Vital(label: "Breathing", value: String(format: "%.1f /min", breaths), symbol: "lungs.fill"))
        }
        if let avg = v.spo2?.avg {
            let low = v.spo2?.min.map { ", low \(Int($0.rounded()))%" } ?? ""
            out.append(Vital(label: "Oxygen", value: "\(Int(avg.rounded()))%\(low)", symbol: "drop.fill"))
        }
        if let delta = v.wristTempDeltaC {
            out.append(Vital(label: "Wrist temp", value: String(format: "%@%.1f°C", delta >= 0 ? "+" : "−", abs(delta)), symbol: "thermometer.medium"))
        }
        return out
    }
}

/// When the carousels (TV, iPad kiosk) and Home show sleep. With Jarvis's
/// `sleep` slice, sleep has its own slide and the "You" slide keeps only
/// steps; an older Jarvis keeps the old "You" slide with minutes asleep.
public enum SleepSlide {
    public static func shows(_ snapshot: Snapshot) -> Bool {
        snapshot.sleep != nil
    }

    public static func showsYou(_ snapshot: Snapshot) -> Bool {
        if snapshot.sleep != nil { return snapshot.health?.yesterday?.steps != nil }
        return snapshot.health?.sleep?.asleepMin != nil || snapshot.health?.yesterday?.steps != nil
    }

    /// The card for a snapshot, last night being this morning's date.
    public static func card(_ snapshot: Snapshot, now: Date = Date()) -> SleepCard {
        SleepCard(summary: snapshot.sleep, fallbackAsleepMinutes: snapshot.health?.sleep?.asleepMin, today: SleepNights.key(now))
    }
}

/// A sideways swipe in a drawer with a date row (Diet, Sleep): left is the
/// next day, right the one before; nil for a drag that's mostly vertical or
/// too short, which belongs to the list's scroll.
public enum DaySwipe {
    public static func step(width w: CGFloat, height h: CGFloat) -> Int? {
        guard abs(w) >= 50, abs(w) > abs(h) * 1.3 else { return nil }
        return w < 0 ? 1 : -1
    }
}
