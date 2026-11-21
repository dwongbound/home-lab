// Sleep as Jarvis tells it back (Dylan, 2026-11-20: "get better sleep info
// on the sleep and health related curosels on tv and app and ipad"): the
// snapshot's `sleep` slice (last night and a 7 night trend) for Home, the
// iPad kiosk and the TV, and GET /api/jarvis/health/sleep for the detail
// screen. The wire names are the CodingKeys below, in one place.
//
// Any number can be null and nothing null is ever shown as 0: every field
// decodes on its own, and a field that's missing or the wrong shape is nil.
import Foundation

/// One night as Jarvis keeps it.
public struct SleepDay: Decodable, Sendable, Identifiable, Equatable {
    public var id: String { night }
    /// The Pacific date of the morning he woke, "2026-11-20".
    public var night: String
    public var bedtime: Date?
    public var wake: Date?
    public var minutes: Minutes?
    /// Awakenings of 5 minutes or more.
    public var interruptions: Int?
    public var vitals: Vitals?
    /// 0 to 100.
    public var score: Int?
    /// "jarvis" (his estimate) or "apple".
    public var scoreSource: String?
    /// "great", "good", "fair" or "poor", as Jarvis judged it.
    public var scoreBand: String?
    public var scoreParts: Parts?
    /// In time order; empty when the night's detail is gone (or in the snapshot).
    public var stages: [Stage] = []

    public struct Minutes: Decodable, Sendable, Equatable {
        public var asleep, inBed, awake, deep, rem, core, unspecified: Double?
        enum CodingKeys: String, CodingKey { case asleep, inBed, awake, deep, rem, core, unspecified }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            func n(_ k: CodingKeys) -> Double? { (try? c.decodeIfPresent(Double.self, forKey: k)) ?? nil }
            asleep = n(.asleep); inBed = n(.inBed); awake = n(.awake); deep = n(.deep); rem = n(.rem); core = n(.core); unspecified = n(.unspecified)
        }
        public init(asleep: Double? = nil, inBed: Double? = nil, awake: Double? = nil, deep: Double? = nil, rem: Double? = nil, core: Double? = nil, unspecified: Double? = nil) {
            self.asleep = asleep; self.inBed = inBed; self.awake = awake; self.deep = deep; self.rem = rem; self.core = core; self.unspecified = unspecified
        }
    }

    /// An average and a low (heart rate, oxygen).
    public struct Pair: Decodable, Sendable, Equatable {
        public var avg: Double?
        public var min: Double?
        enum CodingKeys: String, CodingKey { case avg, min }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            avg = (try? c.decodeIfPresent(Double.self, forKey: .avg)) ?? nil
            min = (try? c.decodeIfPresent(Double.self, forKey: .min)) ?? nil
        }
        public init(avg: Double?, min: Double?) { self.avg = avg; self.min = min }
    }

    public struct Vitals: Decodable, Sendable, Equatable {
        public var heartRate: Pair?
        public var hrvMs, hrvRmssdMs, respiratoryRate: Double?
        public var spo2: Pair?
        public var wristTempC, wristTempDeltaC, breathingDisturbances: Double?
        enum CodingKeys: String, CodingKey { case heartRate, hrvMs, hrvRmssdMs, respiratoryRate, spo2, wristTempC, wristTempDeltaC, breathingDisturbances }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            func n(_ k: CodingKeys) -> Double? { (try? c.decodeIfPresent(Double.self, forKey: k)) ?? nil }
            heartRate = (try? c.decodeIfPresent(Pair.self, forKey: .heartRate)) ?? nil
            spo2 = (try? c.decodeIfPresent(Pair.self, forKey: .spo2)) ?? nil
            hrvMs = n(.hrvMs); hrvRmssdMs = n(.hrvRmssdMs); respiratoryRate = n(.respiratoryRate)
            wristTempC = n(.wristTempC); wristTempDeltaC = n(.wristTempDeltaC); breathingDisturbances = n(.breathingDisturbances)
        }
        public init() {}
    }

    /// Why the score is what it is: duration of 50, consistency of 30 and
    /// interruptions of 20 (a null part isn't counted yet).
    public struct Parts: Decodable, Sendable, Equatable {
        public var duration, consistency, interruptions: Double?
        enum CodingKeys: String, CodingKey { case duration, consistency, interruptions }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            duration = (try? c.decodeIfPresent(Double.self, forKey: .duration)) ?? nil
            consistency = (try? c.decodeIfPresent(Double.self, forKey: .consistency)) ?? nil
            interruptions = (try? c.decodeIfPresent(Double.self, forKey: .interruptions)) ?? nil
        }
        public init(duration: Double?, consistency: Double?, interruptions: Double?) {
            self.duration = duration; self.consistency = consistency; self.interruptions = interruptions
        }
    }

    public struct Stage: Decodable, Sendable, Equatable {
        public var stage: String
        public var start: Date
        public var end: Date
    }

    enum CodingKeys: String, CodingKey {
        case night, bedtime, wake, minutes, interruptions, vitals, score, scoreSource, scoreBand, scoreParts, stages
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        night = try c.decode(String.self, forKey: .night)
        bedtime = ((try? c.decodeIfPresent(String.self, forKey: .bedtime)) ?? nil).flatMap(ISODate.parse)
        wake = ((try? c.decodeIfPresent(String.self, forKey: .wake)) ?? nil).flatMap(ISODate.parse)
        minutes = (try? c.decodeIfPresent(Minutes.self, forKey: .minutes)) ?? nil
        interruptions = (try? c.decodeIfPresent(Int.self, forKey: .interruptions)) ?? nil
        vitals = (try? c.decodeIfPresent(Vitals.self, forKey: .vitals)) ?? nil
        score = ((try? c.decodeIfPresent(Double.self, forKey: .score)) ?? nil).map { Int($0.rounded()) }
        scoreSource = (try? c.decodeIfPresent(String.self, forKey: .scoreSource)) ?? nil
        scoreBand = (try? c.decodeIfPresent(String.self, forKey: .scoreBand)) ?? nil
        scoreParts = (try? c.decodeIfPresent(Parts.self, forKey: .scoreParts)) ?? nil
        struct RawStage: Decodable { let stage: String?; let start: String?; let end: String? }
        let raw = ((try? c.decodeIfPresent([RawStage].self, forKey: .stages)) ?? nil) ?? []
        stages = raw.compactMap { r in
            guard let stage = r.stage, let start = r.start.flatMap(ISODate.parse), let end = r.end.flatMap(ISODate.parse), end > start else { return nil }
            return Stage(stage: stage, start: start, end: end)
        }
    }

    public init(night: String, bedtime: Date? = nil, wake: Date? = nil, minutes: Minutes? = nil, interruptions: Int? = nil,
                vitals: Vitals? = nil, score: Int? = nil, scoreSource: String? = nil, scoreBand: String? = nil,
                scoreParts: Parts? = nil, stages: [Stage] = []) {
        self.night = night; self.bedtime = bedtime; self.wake = wake; self.minutes = minutes; self.interruptions = interruptions
        self.vitals = vitals; self.score = score; self.scoreSource = scoreSource; self.scoreBand = scoreBand
        self.scoreParts = scoreParts; self.stages = stages
    }
}

/// The snapshot's `sleep`: last night (no stages) and up to 7 nights of trend.
public struct SleepSummary: Decodable, Sendable, Equatable {
    public var last: SleepDay?
    /// Newest first.
    public var trend: [TrendNight] = []

    public struct TrendNight: Decodable, Sendable, Equatable, Identifiable {
        public var id: String { night }
        public var night: String
        public var score: Int?
        /// Minutes asleep.
        public var asleep: Double?
        enum CodingKeys: String, CodingKey { case night, score, asleep }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            night = try c.decode(String.self, forKey: .night)
            score = ((try? c.decodeIfPresent(Double.self, forKey: .score)) ?? nil).map { Int($0.rounded()) }
            asleep = (try? c.decodeIfPresent(Double.self, forKey: .asleep)) ?? nil
        }
        public init(night: String, score: Int?, asleep: Double?) { self.night = night; self.score = score; self.asleep = asleep }
    }

    enum CodingKeys: String, CodingKey { case last, trend }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        last = (try? c.decodeIfPresent(SleepDay.self, forKey: .last)) ?? nil
        struct Maybe: Decodable { let night: TrendNight?; init(from d: Decoder) throws { night = try? TrendNight(from: d) } }
        trend = (((try? c.decodeIfPresent([Maybe].self, forKey: .trend)) ?? nil) ?? []).compactMap(\.night)
    }

    public init(last: SleepDay?, trend: [TrendNight]) { self.last = last; self.trend = trend }
}

/// GET /api/jarvis/health/sleep: nights newest first, or nil when Jarvis
/// couldn't be asked.
public struct SleepNightsAnswer: Decodable, Sendable {
    public var nights: [SleepDay]?
    enum CodingKeys: String, CodingKey { case nights }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        struct Maybe: Decodable { let day: SleepDay?; init(from d: Decoder) throws { day = try? SleepDay(from: d) } }
        nights = ((try? c.decodeIfPresent([Maybe].self, forKey: .nights)) ?? nil)?.compactMap(\.day)
    }
}

/// POST's answer: ok, a message, and the night as stored.
public struct SleepSendAnswer: Decodable, Sendable {
    public var ok: Bool
    public var message: String?
    public var night: SleepDay?
    enum CodingKeys: String, CodingKey { case ok, message, night }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = (try? c.decodeIfPresent(Bool.self, forKey: .ok)) ?? false
        message = (try? c.decodeIfPresent(String.self, forKey: .message)) ?? nil
        night = (try? c.decodeIfPresent(SleepDay.self, forKey: .night)) ?? nil
    }
}
