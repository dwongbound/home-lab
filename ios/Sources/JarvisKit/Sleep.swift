// Last night's sleep from Apple Health, as Jarvis takes it (Dylan,
// 2026-11-20: "can i also send and get sleep score from my apple watch and
// more specific sleep details"). The iPhone reads Health (App/SleepSync.swift)
// and hands the samples here as plain values; this file turns one night of
// them into the body Jarvis stores. Pure, so it's tested with made-up
// fixtures and no HealthKit.
//
// A night is the Pacific date of the morning he wakes; its window runs from
// 6 PM the day before to 6 PM that day. Only the main sleep counts: the
// longest run of sleep in the window, never a nap. When the watch and the
// phone both recorded the night, the watch's stages win, so nothing is
// counted twice. Every vital is optional: no samples, no field (never 0).
//
// Read-only and private: nothing here logs or prints a value.
import Foundation

/// Apple Health's sleep values (HKCategoryValueSleepAnalysis).
public enum SleepValue: Int, Sendable, Equatable {
    case inBed = 0, unspecified = 1, awake = 2, core = 3, deep = 4, rem = 5

    /// The stage Jarvis calls it; in bed is not a stage.
    public var stage: String? {
        switch self {
        case .inBed: return nil
        case .unspecified: return "unspecified"
        case .awake: return "awake"
        case .core: return "core"
        case .deep: return "deep"
        case .rem: return "rem"
        }
    }

    public var isAsleep: Bool { self == .unspecified || self == .core || self == .deep || self == .rem }
}

/// Where a sample came from: one app or device writing to Health.
public struct SleepSource: Hashable, Sendable {
    public let id: String
    /// True for an Apple Watch (it writes the stages).
    public let isWatch: Bool
    public init(id: String, isWatch: Bool) { self.id = id; self.isWatch = isWatch }
}

/// One sleep-analysis sample.
public struct SleepStageSample: Sendable, Equatable {
    public let value: SleepValue
    public let start: Date
    public let end: Date
    public let source: SleepSource
    public init(value: SleepValue, start: Date, end: Date, source: SleepSource) {
        self.value = value; self.start = start; self.end = end; self.source = source
    }
}

/// One reading of a vital, in Health's own unit for it (see SleepVitals).
public struct SleepReading: Sendable, Equatable {
    public let value: Double
    public let start: Date
    public let end: Date
    public let source: SleepSource
    public init(value: Double, start: Date, end: Date, source: SleepSource) {
        self.value = value; self.start = start; self.end = end; self.source = source
    }
}

/// The vitals as Health stores them: heart rate in beats a minute, HRV in
/// ms, respiratory rate in breaths a SECOND, oxygen as a 0 to 1 fraction,
/// wrist temperature in °C, breathing disturbances as a count.
public struct SleepVitals: Sendable {
    public var heartRate: [SleepReading] = []
    public var hrvSDNN: [SleepReading] = []
    public var hrvRMSSD: [SleepReading] = []
    public var respiratoryPerSecond: [SleepReading] = []
    public var oxygenFraction: [SleepReading] = []
    public var wristTemperature: [SleepReading] = []
    public var breathingDisturbances: [SleepReading] = []
    public init() {}
}

/// One stage segment of the night.
public struct SleepSegment: Sendable, Equatable {
    public let stage: String
    public let start: Date
    public let end: Date
}

/// One night, ready to send.
public struct SleepNight: Sendable, Equatable {
    public let night: String
    public let inBedStart: Date
    public let inBedEnd: Date
    public let asleepStart: Date
    public let asleepEnd: Date
    public let stages: [SleepSegment]
    public var heartRate: (avg: Double, min: Double)?
    public var hrvMs: Double?
    public var hrvRmssdMs: Double?
    public var respiratoryRate: Double?
    public var spo2: (avg: Double, min: Double)?
    public var wristTempC: Double?
    public var breathingDisturbances: Double?
    public let source: String

    public static func == (a: SleepNight, b: SleepNight) -> Bool {
        a.night == b.night && a.inBedStart == b.inBedStart && a.inBedEnd == b.inBedEnd
            && a.asleepStart == b.asleepStart && a.asleepEnd == b.asleepEnd && a.stages == b.stages
            && a.heartRate?.avg == b.heartRate?.avg && a.heartRate?.min == b.heartRate?.min
            && a.hrvMs == b.hrvMs && a.hrvRmssdMs == b.hrvRmssdMs && a.respiratoryRate == b.respiratoryRate
            && a.spo2?.avg == b.spo2?.avg && a.spo2?.min == b.spo2?.min && a.wristTempC == b.wristTempC
            && a.breathingDisturbances == b.breathingDisturbances && a.source == b.source
    }
}

/// Unit changes from Health's units to Jarvis's.
public enum SleepUnits {
    /// Breaths a second (Health) to breaths a minute (Jarvis).
    public static func breathsPerMinute(perSecond: Double) -> Double { perSecond * 60 }
    /// A 0 to 1 fraction (Health) to percent (Jarvis).
    public static func percent(fraction: Double) -> Double { fraction * 100 }
}

public enum SleepNights {
    /// Dylan's clock: nights are Pacific dates.
    public static let zone = TimeZone(identifier: "America/Los_Angeles")!

    /// Sleep this far apart is two sleeps (a nap and the night); a shorter
    /// gap, like the watch losing contact for a while, is one.
    public static let splitGap: TimeInterval = 90 * 60
    /// The most stages Jarvis takes.
    public static let maxStages = 500

    private static func calendar(_ zone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    /// "2026-11-20" for a date, on the given clock.
    public static func key(_ date: Date, zone: TimeZone = zone) -> String {
        let parts = calendar(zone).dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// A night's window: 6 PM the day before to 6 PM on the night's date.
    public static func window(_ night: String, zone: TimeZone = zone) -> DateInterval? {
        let bits = night.split(separator: "-").compactMap { Int($0) }
        guard bits.count == 3 else { return nil }
        let cal = calendar(zone)
        guard let end = cal.date(from: DateComponents(year: bits[0], month: bits[1], day: bits[2], hour: 18)),
              let dayBefore = cal.date(byAdding: .day, value: -1, to: cal.date(from: DateComponents(year: bits[0], month: bits[1], day: bits[2]))!),
              let start = cal.date(bySettingHour: 18, minute: 0, second: 0, of: dayBefore) else { return nil }
        return DateInterval(start: start, end: end)
    }

    /// The nights to look at, newest last: `count` nights ending on the
    /// one whose morning is `now` (or the most recent morning).
    public static func recent(_ count: Int, now: Date, zone: TimeZone = zone) -> [String] {
        let cal = calendar(zone)
        return (0..<count).reversed().compactMap { back in
            cal.date(byAdding: .day, value: -back, to: now).map { key($0, zone: zone) }
        }
    }

    /// Builds one night from what Health holds around it; nil when there's
    /// no sleep in the window.
    public static func build(night: String, stages samples: [SleepStageSample], vitals: SleepVitals, zone: TimeZone = zone) -> SleepNight? {
        guard let window = window(night, zone: zone) else { return nil }
        let inWindow = samples.compactMap { clip($0, to: window) }

        // One source for the stages, so nothing is counted twice: a watch
        // over the phone, then whichever recorded the most sleep.
        let asleepBySource = Dictionary(grouping: inWindow.filter(\.value.isAsleep), by: \.source)
            .mapValues { $0.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) } }
        guard let source = asleepBySource.keys.max(by: { a, b in
            (a.isWatch ? 1 : 0, asleepBySource[a]!) < (b.isWatch ? 1 : 0, asleepBySource[b]!)
        }) else { return nil }
        let mine = inWindow.filter { $0.source == source && $0.value != .inBed }.sorted { $0.start < $1.start }

        // The main sleep: runs of sleep split by long gaps; the longest wins.
        var runs: [[SleepStageSample]] = []
        for sample in mine where sample.value.isAsleep {
            if let last = runs.last?.last, sample.start.timeIntervalSince(last.end) <= splitGap {
                runs[runs.count - 1].append(sample)
            } else {
                runs.append([sample])
            }
        }
        func asleep(_ run: [SleepStageSample]) -> TimeInterval { run.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) } }
        guard let main = runs.max(by: { asleep($0) < asleep($1) }),
              let asleepStart = main.map(\.start).min(), let asleepEnd = main.map(\.end).max() else { return nil }

        // Its stages: the sleep and the awake moments between, in order.
        let segments = mine
            .filter { $0.start < asleepEnd && $0.end > asleepStart }
            .map { SleepSegment(stage: $0.value.stage ?? "unspecified", start: max($0.start, asleepStart), end: min($0.end, asleepEnd)) }
            .filter { $0.end > $0.start }
        let merged = Array(mergeTouching(segments).prefix(maxStages))

        // In bed: any source's in-bed time around the main sleep, else the sleep itself.
        let beds = inWindow.filter { $0.value == .inBed && $0.start < asleepEnd && $0.end > asleepStart }
        let inBedStart = min(beds.map(\.start).min() ?? asleepStart, asleepStart)
        let inBedEnd = max(beds.map(\.end).max() ?? asleepEnd, asleepEnd)

        var result = SleepNight(night: night, inBedStart: inBedStart, inBedEnd: inBedEnd, asleepStart: asleepStart, asleepEnd: asleepEnd,
                                stages: merged, source: source.isWatch ? "apple_watch" : "iphone")
        let asleepWindow = DateInterval(start: asleepStart, end: asleepEnd)
        let hr = readings(vitals.heartRate, in: asleepWindow).filter { (20...250).contains($0) }
        if let avg = mean(hr), let low = hr.min() { result.heartRate = (round(avg, 1), round(low, 1)) }
        result.hrvMs = mean(readings(vitals.hrvSDNN, in: asleepWindow).filter { (1...300).contains($0) }).map { round($0, 1) }
        result.hrvRmssdMs = mean(readings(vitals.hrvRMSSD, in: asleepWindow).filter { (1...300).contains($0) }).map { round($0, 1) }
        result.respiratoryRate = mean(readings(vitals.respiratoryPerSecond, in: asleepWindow).map(SleepUnits.breathsPerMinute(perSecond:))
            .filter { (4...60).contains($0) }).map { round($0, 1) }
        let oxygen = readings(vitals.oxygenFraction, in: asleepWindow).map(SleepUnits.percent(fraction:)).filter { (50...100).contains($0) }
        if let avg = mean(oxygen), let low = oxygen.min() { result.spo2 = (round(avg, 1), round(low, 1)) }
        // The night's wrist temperature (Health writes one span per night): absolute °C.
        result.wristTempC = mean(readings(vitals.wristTemperature, in: asleepWindow).filter { (25...42).contains($0) }).map { round($0, 2) }
        result.breathingDisturbances = readings(vitals.breathingDisturbances, in: asleepWindow).filter { (0...200).contains($0) }.max()
        return result
    }

    /// A sample cut to the window; nil when it's outside it.
    private static func clip(_ sample: SleepStageSample, to window: DateInterval) -> SleepStageSample? {
        let start = max(sample.start, window.start), end = min(sample.end, window.end)
        guard end > start else { return nil }
        return SleepStageSample(value: sample.value, start: start, end: end, source: sample.source)
    }

    /// Back-to-back pieces of the same stage read as one.
    private static func mergeTouching(_ segments: [SleepSegment]) -> [SleepSegment] {
        var out: [SleepSegment] = []
        for segment in segments.sorted(by: { $0.start < $1.start }) {
            if let last = out.last, last.stage == segment.stage, segment.start <= last.end {
                out[out.count - 1] = SleepSegment(stage: last.stage, start: last.start, end: max(last.end, segment.end))
            } else if let last = out.last, segment.start < last.end {
                // An overlap inside one source: the later piece starts where the earlier ends.
                if segment.end > last.end { out.append(SleepSegment(stage: segment.stage, start: last.end, end: segment.end)) }
            } else {
                out.append(segment)
            }
        }
        return out
    }

    /// The values of readings that overlap `window`, the watch's only when
    /// the watch recorded any (so a phone or another app can't double them).
    private static func readings(_ all: [SleepReading], in window: DateInterval) -> [Double] {
        let inside = all.filter { $0.start < window.end && $0.end > window.start || ($0.start == $0.end && window.contains($0.start)) }
        let watch = inside.filter(\.source.isWatch)
        return (watch.isEmpty ? inside : watch).map(\.value)
    }

    private static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    private static func round(_ value: Double, _ places: Int) -> Double {
        let scale = pow(10, Double(places))
        return (value * scale).rounded() / scale
    }
}

/// The request body. Field names live in ONE map, so the page route's
/// camelCase (or Jarvis's own snake_case) is a one-line change.
public enum SleepWire {
    public enum Style: Sendable { case page, jarvis }

    static func name(_ field: String, _ style: Style) -> String {
        guard style == .jarvis else { return field }
        let snake: [String: String] = [
            "inBedStart": "in_bed_start", "inBedEnd": "in_bed_end", "asleepStart": "asleep_start", "asleepEnd": "asleep_end",
            "heartRate": "heart_rate", "hrvMs": "hrv_ms", "hrvRmssdMs": "hrv_rmssd_ms", "respiratoryRate": "respiratory_rate",
            "wristTempC": "wrist_temp_c", "breathingDisturbances": "breathing_disturbances",
        ]
        return snake[field] ?? field
    }

    /// ISO 8601 with the Pacific offset ("2026-11-20T06:42:00-08:00").
    public static func time(_ date: Date, zone: TimeZone = SleepNights.zone) -> String {
        let f = ISO8601DateFormatter()
        f.timeZone = zone
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    /// The JSON object for one night; fields with nothing to say are left out.
    public static func body(_ n: SleepNight, style: Style = .page, zone: TimeZone = SleepNights.zone) -> [String: Any] {
        var body: [String: Any] = [
            name("night", style): n.night,
            name("inBedStart", style): time(n.inBedStart, zone: zone),
            name("inBedEnd", style): time(n.inBedEnd, zone: zone),
            name("asleepStart", style): time(n.asleepStart, zone: zone),
            name("asleepEnd", style): time(n.asleepEnd, zone: zone),
            name("stages", style): n.stages.map { ["stage": $0.stage, "start": time($0.start, zone: zone), "end": time($0.end, zone: zone)] },
            name("source", style): n.source,
        ]
        if let hr = n.heartRate { body[name("heartRate", style)] = ["avg": hr.avg, "min": hr.min] }
        if let v = n.hrvMs { body[name("hrvMs", style)] = v }
        if let v = n.hrvRmssdMs { body[name("hrvRmssdMs", style)] = v }
        if let v = n.respiratoryRate { body[name("respiratoryRate", style)] = v }
        if let o = n.spo2 { body[name("spo2", style)] = ["avg": o.avg, "min": o.min] }
        if let v = n.wristTempC { body[name("wristTempC", style)] = v }
        if let v = n.breathingDisturbances { body[name("breathingDisturbances", style)] = Int(v.rounded()) }
        return body
    }

    /// A short fingerprint of what was sent for a night (times and counts,
    /// no vitals), so a night that grew since is sent again.
    public static func fingerprint(_ n: SleepNight) -> String {
        "\(Int(n.asleepStart.timeIntervalSince1970))-\(Int(n.asleepEnd.timeIntervalSince1970))-\(n.stages.count)-\(n.source)"
    }
}

/// Which nights have gone to Jarvis, kept on the phone: night → what was
/// sent. A night is sent again only when it changed (a morning that was
/// still going, or a late watch sync); nights past the backfill are let go.
public struct SentNights: Equatable, Sendable {
    public private(set) var sent: [String: String]
    public static let backfill = 14

    public init(sent: [String: String] = [:]) { self.sent = sent }

    /// Whether this night still needs sending.
    public func needs(_ night: SleepNight) -> Bool {
        sent[night.night] != SleepWire.fingerprint(night)
    }

    /// Jarvis has it.
    public mutating func mark(_ night: SleepNight) {
        sent[night.night] = SleepWire.fingerprint(night)
    }

    /// Forgets nights older than the backfill window.
    public mutating func prune(keeping nights: [String]) {
        let keep = Set(nights)
        sent = sent.filter { keep.contains($0.key) }
    }

    /// As stored (UserDefaults takes a [String: String]).
    public var stored: [String: String] { sent }
}
