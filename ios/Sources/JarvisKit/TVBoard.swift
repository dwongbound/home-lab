// The Apple TV's always-on board, as plain rules (Dylan, 2026-11-17: "make
// it more dynamic / nicely styled — people will see this as they walk into
// my room — as well as more important information"). What the hero card
// says (the event on now, or next, with a live countdown), where the sun or
// moon sits on its arc, the rest of today as a timeline, which cards rotate
// and in what order, the status chips, and what guest-friendly mode leaves
// out. The TV draws these; nothing here touches SwiftUI.
import Foundation

// MARK: Countdown

public enum Countdown {
    /// "now", "in 5 min", "in 1 h 20 min", "in 3 h".
    public static func words(from now: Date, to start: Date) -> String {
        let minutes = Int((start.timeIntervalSince(now) / 60).rounded(.up))
        if minutes <= 0 { return "now" }
        if minutes < 60 { return "in \(minutes) min" }
        let hours = minutes / 60, rest = minutes % 60
        if hours >= 3 || rest == 0 { return "in \(hours) h" }
        return "in \(hours) h \(rest) min"
    }

    /// "42 min left", "1 h 5 min left".
    public static func left(from now: Date, to end: Date) -> String {
        let minutes = max(1, Int((end.timeIntervalSince(now) / 60).rounded(.up)))
        if minutes < 60 { return "\(minutes) min left" }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? "\(hours) h left" : "\(hours) h \(rest) min left"
    }
}

// MARK: Now / Next

/// The hero card: what's on now, what's next today, or tomorrow's first
/// thing once the evening has nothing left.
public struct NowNext: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case now, next, tomorrow }
    public let kind: Kind
    public let title: String
    public let start: Date
    public let end: Date?
    public let location: String?

    /// "Now", "Next", "Tomorrow".
    public var label: String {
        switch kind {
        case .now: return "Now"
        case .next: return "Next"
        case .tomorrow: return "Tomorrow"
        }
    }

    /// The live line under the title: "in 42 min", "18 min left", "8:00 AM".
    public func countdown(now: Date, timeZone: TimeZone = .current) -> String {
        switch kind {
        case .now: return end.map { Countdown.left(from: now, to: $0) } ?? "on now"
        case .next: return Countdown.words(from: now, to: start)
        case .tomorrow: return Self.clock(start, timeZone: timeZone)
        }
    }

    /// How far through it is (0…1), for an event on now with an end.
    public func progress(now: Date) -> Double? {
        guard kind == .now, let end, end > start else { return nil }
        return min(1, max(0, now.timeIntervalSince(start) / end.timeIntervalSince(start)))
    }

    /// From 6 PM on, an empty rest of today shows tomorrow's first event.
    public static let eveningHour = 18
    /// An event with no end is taken to run this long.
    public static let assumedLength: TimeInterval = 60 * 60

    /// The pick. Calendar events (they have ends and places) come first;
    /// Jarvis's own jobs on the agenda are left out, they aren't plans.
    public static func pick(events: [CalendarEvent], agenda: [AgendaItem], now: Date, calendar: Calendar = .current) -> NowNext? {
        var timed: [NowNext] = events.compactMap { event in
            guard event.allDay != true, let start = AgendaTime.parse(event.start) else { return nil }
            let end = event.end.flatMap(AgendaTime.parse)
            let place = event.location?.trimmingCharacters(in: .whitespaces)
            return NowNext(kind: .next, title: event.title, start: start, end: end, location: place?.isEmpty == false ? place : nil)
        }
        // Agenda items that aren't Jarvis jobs and aren't already events.
        for item in agenda where item.allDay != true && !isJarvisJob(item) {
            guard let start = AgendaTime.parse(item.at), !timed.contains(where: { $0.title == item.title }) else { continue }
            timed.append(NowNext(kind: .next, title: item.title, start: start, end: nil, location: nil))
        }
        timed.sort { $0.start < $1.start }
        if let on = timed.last(where: { $0.start <= now && ($0.end ?? $0.start.addingTimeInterval(assumedLength)) > now }) {
            return NowNext(kind: .now, title: on.title, start: on.start, end: on.end, location: on.location)
        }
        if let next = timed.first(where: { $0.start > now && calendar.isDate($0.start, inSameDayAs: now) }) {
            return next
        }
        if calendar.component(.hour, from: now) >= eveningHour,
           let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           let first = timed.first(where: { calendar.isDate($0.start, inSameDayAs: tomorrow) }) {
            return NowNext(kind: .tomorrow, title: first.title, start: first.start, end: first.end, location: first.location)
        }
        return nil
    }

    /// True for the agenda's Jarvis jobs ("Jarvis: Marketplace scan").
    public static func isJarvisJob(_ item: AgendaItem) -> Bool {
        item.id.hasPrefix("jarvis-") || (item.detail ?? "").hasPrefix("Jarvis")
    }

    static func clock(_ date: Date, timeZone: TimeZone) -> String {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US")
        format.timeZone = timeZone
        format.dateFormat = "h:mm a"
        return format.string(from: date)
    }
}

// MARK: Sky arc

/// Where the sun (by day) or the moon (by night) sits on its arc across the
/// top of the sky.
public struct SkyArc: Equatable, Sendable {
    /// True for the sun, false for the moon.
    public let sun: Bool
    /// 0 at the left horizon (rise) … 1 at the right (set).
    public let progress: Double
    /// 0 on the horizon … 1 at the top of the arc.
    public var height: Double { sin(.pi * progress) }

    /// From today's sunrise and sunset (moved to the nearest day, like the
    /// lamp). The moon stands in for the night, rising at sunset.
    public static func at(now: Date, sunrise: Date, sunset: Date) -> SkyArc {
        let rise = SunLamp.nearest(sunrise, to: now), set = SunLamp.nearest(sunset, to: now)
        if rise <= now && now <= set {
            return SkyArc(sun: true, progress: now.timeIntervalSince(rise) / set.timeIntervalSince(rise))
        }
        // Night: from the last sunset to the next sunrise.
        let lastSet = set <= now ? set : set.addingTimeInterval(-86_400)
        let nextRise = rise > now ? rise : rise.addingTimeInterval(86_400)
        let p = now.timeIntervalSince(lastSet) / nextRise.timeIntervalSince(lastSet)
        return SkyArc(sun: false, progress: min(1, max(0, p)))
    }

    /// How visible the stars are (0 day … 1 deep night), from the lamp.
    public static func stars(_ lamp: SunLampState) -> Double {
        max(0, min(1, (0.35 - lamp.brightness) / 0.32))
    }
}

// MARK: Today timeline

/// One row of the Today card.
public struct TimelineRow: Equatable, Identifiable, Sendable {
    public enum State: Equatable, Sendable { case done, now, next, later }
    public let id: String
    public let time: String
    public let title: String
    public let state: State
    /// Jarvis's own scheduled jobs, drawn with a sparkle.
    public let jarvis: Bool
}

public enum TodayTimeline {
    /// The day in order: what's done (only the last couple), what's on, the
    /// next one, then later. At most `limit` rows, keeping the future.
    public static func rows(_ agenda: [AgendaItem], now: Date, limit: Int = 6, timeZone: TimeZone = .current) -> [TimelineRow] {
        let dated = agenda.compactMap { item -> (AgendaItem, Date?) in (item, AgendaTime.parse(item.at)) }
        let sorted = dated.sorted { ($0.1 ?? .distantPast) < ($1.1 ?? .distantPast) }
        var sawNext = false
        let rows: [TimelineRow] = sorted.map { item, start in
            let state: TimelineRow.State
            if let start, start <= now {
                state = now.timeIntervalSince(start) < NowNext.assumedLength && !NowNext.isJarvisJob(item) ? .now : .done
            } else if !sawNext {
                sawNext = true
                state = .next
            } else {
                state = .later
            }
            return TimelineRow(
                id: item.id,
                time: AgendaTime.label(at: item.at, allDay: item.allDay ?? false, timeZone: timeZone),
                title: item.title,
                state: state,
                jarvis: NowNext.isJarvisJob(item)
            )
        }
        // Keep the future; trim the oldest finished rows first.
        var out = rows
        while out.count > limit, let firstDone = out.firstIndex(where: { $0.state == .done }) {
            out.remove(at: firstDone)
        }
        return Array(out.prefix(limit))
    }
}

// MARK: Cards and guests

/// The rotating cards on the TV's right side.
public enum TVCard: String, CaseIterable, Sendable {
    case today, home, playing, forecast, jarvis, health, suggestions

    /// The card's title.
    public var title: String {
        switch self {
        case .today: return "Today"
        case .home: return "Home"
        case .playing: return "Now playing"
        case .forecast: return "Next hours"
        case .jarvis: return "Jarvis"
        case .health: return "You"
        case .suggestions: return "From Jarvis"
        }
    }

    /// Its SF Symbol.
    public var symbol: String {
        switch self {
        case .today: return "calendar"
        case .home: return "house.fill"
        case .playing: return "play.circle.fill"
        case .forecast: return "cloud.sun.fill"
        case .jarvis: return "sparkles"
        case .health: return "heart.fill"
        case .suggestions: return "lightbulb.fill"
        }
    }

    /// Private to Dylan: hidden in guest-friendly mode (sleep, steps and
    /// Jarvis's suggestions, which can quote personal things).
    public var isPrivate: Bool { self == .health || self == .suggestions }
}

public enum TVBoard {
    /// Seconds each card shows.
    public static let turnSeconds: Double = 15

    /// The cards with something to show, in rotation order. Guest-friendly
    /// mode leaves out the private ones.
    public static func cards(_ snapshot: Snapshot?, guest: Bool) -> [TVCard] {
        guard let snapshot else { return [] }
        var out: [TVCard] = []
        if !snapshot.today.isEmpty { out.append(.today) }
        if !HomeGlance.lines(snapshot.home).isEmpty { out.append(.home) }
        if !playing(snapshot.home).isEmpty { out.append(.playing) }
        if (snapshot.home?.forecast?.count ?? 0) >= 3 { out.append(.forecast) }
        if !(snapshot.jobs?.running.isEmpty ?? true) || !snapshot.services.isEmpty { out.append(.jarvis) }
        if snapshot.health?.sleep?.asleepMin != nil || snapshot.health?.yesterday?.steps != nil { out.append(.health) }
        if !(snapshot.offers?.offers.isEmpty ?? true) { out.append(.suggestions) }
        return guest ? out.filter { !$0.isPrivate } : out
    }

    /// Media playing or on, most recent first as Home Assistant lists them.
    public static func playing(_ home: Home?) -> [Device] {
        (home?.devices ?? []).filter { $0.kind == "media" && $0.isAvailable && ($0.state == "playing" || $0.state == "paused") }
    }

    /// The greeting as the TV shows it. Guests get the headline only: the
    /// rest often says where Dylan is and what he's doing.
    public static func greeting(_ snapshot: Snapshot?, guest: Bool) -> (headline: String, body: String?)? {
        guard let text = snapshot?.offers?.greeting, !text.isEmpty else { return nil }
        let parts = TodayWording.greetingParts(text)
        return (parts.headline, guest ? nil : parts.body)
    }
}

// MARK: Status chips

/// A small pill along the top of the right side: what's going on at a glance.
public struct StatusChip: Equatable, Identifiable, Sendable {
    public enum Tone: Equatable, Sendable { case calm, working, attention }
    public let symbol: String
    public let text: String
    public let tone: Tone
    public var id: String { symbol + text }
}

public enum StatusChips {
    /// Problems first, then work, then the calm all-clear when there's
    /// nothing else. Approvals are a count only, never what they're for.
    public static func chips(_ snapshot: Snapshot?, approvals: Int) -> [StatusChip] {
        guard let snapshot else { return [] }
        var out: [StatusChip] = []
        for service in snapshot.alerts.prefix(2) {
            out.append(StatusChip(symbol: "exclamationmark.triangle.fill", text: "\(service.name) \(service.status)", tone: .attention))
        }
        let attention = HomeGlance.lines(snapshot.home).filter(\.attention)
        if let first = attention.first {
            let text = attention.count == 1 ? "\(first.title) · \(first.value.lowercased())" : "\(attention.count) things at home"
            out.append(StatusChip(symbol: first.symbol, text: text, tone: .attention))
        }
        if approvals > 0 {
            out.append(StatusChip(symbol: "hand.raised.fill", text: approvals == 1 ? "1 approval waiting" : "\(approvals) approvals waiting", tone: .attention))
        }
        let running = snapshot.jobs?.running.count ?? 0
        if running > 0 {
            out.append(StatusChip(symbol: "gearshape.2.fill", text: running == 1 ? "Jarvis is working" : "\(running) tasks running", tone: .working))
        }
        if out.isEmpty {
            out.append(StatusChip(symbol: "checkmark.seal.fill", text: "All systems normal", tone: .calm))
        }
        return out
    }
}
