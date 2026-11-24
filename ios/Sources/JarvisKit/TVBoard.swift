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
        return rest == 0 || hours >= 3 ? "\(hours) h left" : "\(hours) h \(rest) min left"
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
        let timed = plans(events: events, agenda: agenda)
        if let on = timed.last(where: { $0.start <= now && ($0.end ?? $0.start.addingTimeInterval(assumedLength)) > now }) {
            return NowNext(kind: .now, title: on.title, start: on.start, end: on.end, location: on.location)
        }
        return upcoming(timed, now: now, calendar: calendar)
    }

    /// What comes after the event on now (Dylan, 2026-11-24: "mention whats
    /// next and when (thats probably more important)"): the next one later
    /// today, or after 6 PM tomorrow's first. Nil when nothing is on now
    /// (then `pick` already is the next one) or nothing follows.
    public static func after(events: [CalendarEvent], agenda: [AgendaItem], now: Date, calendar: Calendar = .current) -> NowNext? {
        guard let current = pick(events: events, agenda: agenda, now: now, calendar: calendar), current.kind == .now else { return nil }
        let later = plans(events: events, agenda: agenda).filter { $0.start > current.start && $0.title != current.title }
        return upcoming(later, now: now, calendar: calendar)
    }

    /// The first of `timed` still to start today, else tomorrow's first from 6 PM.
    private static func upcoming(_ timed: [NowNext], now: Date, calendar: Calendar) -> NowNext? {
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

    /// Calendar events and the agenda's own plans, as one list by start time.
    /// Calendar events (they have ends and places) come first; Jarvis's own
    /// jobs on the agenda are left out, they aren't plans.
    private static func plans(events: [CalendarEvent], agenda: [AgendaItem]) -> [NowNext] {
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
        return timed
    }

    /// "7:30 PM", "Tomorrow 9:00 AM": when it starts, for the strip.
    public func when(timeZone: TimeZone = .current) -> String {
        let clock = Self.clock(start, timeZone: timeZone)
        return kind == .tomorrow ? "Tomorrow \(clock)" : clock
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
    /// The day in order: calendar events and the agenda together, what's
    /// done (only the last couple), what's on, the next one, then later. At
    /// most `limit` rows, keeping the future. Guest-friendly mode leaves out
    /// Jarvis's own jobs: they're private reminders, not plans.
    public static func rows(_ agenda: [AgendaItem], events: [CalendarEvent] = [], now: Date, guest: Bool = false, limit: Int = 6, timeZone: TimeZone = .current, calendar: Calendar = .current) -> [TimelineRow] {
        var items = agenda.filter { !(guest && NowNext.isJarvisJob($0)) }
        for event in events where !items.contains(where: { $0.title == event.title }) {
            guard let start = AgendaTime.parse(event.start), calendar.isDate(start, inSameDayAs: now) || event.allDay == true else { continue }
            items.append(AgendaItem(id: "event-" + event.id, at: event.start, title: event.title, detail: nil, allDay: event.allDay))
        }
        let ends = Dictionary(events.compactMap { e in e.end.flatMap(AgendaTime.parse).map { (e.title, $0) } }, uniquingKeysWith: { a, _ in a })
        let dated = items.map { item -> (AgendaItem, Date?) in (item, AgendaTime.parse(item.at)) }
        let sorted = dated.sorted { ($0.1 ?? .distantPast) < ($1.1 ?? .distantPast) }
        var sawNext = false
        let rows: [TimelineRow] = sorted.map { item, start in
            let state: TimelineRow.State
            if let start, start <= now {
                let end = ends[item.title] ?? start.addingTimeInterval(NowNext.assumedLength)
                state = end > now && !NowNext.isJarvisJob(item) ? .now : .done
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
    /// Jarvis's message (the greeting's full text), first in the rotation.
    case message
    case today, tasks, home, playing, forecast, jarvis, lookout, health, suggestions
    /// Every home device, grouped, lit when on (Dylan, 2026-11-20: "make
    /// sure theres a device slide on apple tv"). Display only.
    case devices
    /// Who's using the graphics card, as a pie.
    case gpu
    /// Last night's sleep: score, time asleep, stages and the week
    /// (Dylan, 2026-11-20). From the snapshot's `sleep`.
    case sleep

    /// The card's title.
    public var title: String {
        switch self {
        case .message: return "From Jarvis"
        case .today: return "Today"
        case .tasks: return "Active tasks"
        case .home: return "Home"
        case .devices: return "Devices"
        case .playing: return "Now playing"
        case .forecast: return "Next hours"
        case .jarvis: return "Jarvis"
        case .lookout: return "Lookout"
        case .health: return "You"
        case .sleep: return "Sleep"
        case .suggestions: return "Suggestions"
        case .gpu: return "System"
        }
    }

    /// Its SF Symbol.
    public var symbol: String {
        switch self {
        case .message: return "text.bubble.fill"
        case .today: return "calendar"
        case .tasks: return "gearshape.2.fill"
        case .home: return "house.fill"
        case .devices: return "lightbulb.2.fill"
        case .playing: return "play.circle.fill"
        case .forecast: return "cloud.sun.fill"
        case .jarvis: return "sparkles"
        case .lookout: return "binoculars.fill"
        case .health: return "heart.fill"
        case .sleep: return "bed.double.fill"
        case .suggestions: return "lightbulb.fill"
        case .gpu: return "desktopcomputer"
        }
    }

    /// Private to Dylan: hidden in guest-friendly mode (sleep, steps and
    /// Jarvis's suggestions, which can quote personal things).
    /// Lookout says what Jarvis is watching for Dylan and how often he's
    /// messaged him: private too.
    /// Reports can be about anything of his: private as well.
    public var isPrivate: Bool { self == .health || self == .sleep || self == .suggestions || self == .lookout }
}

public enum TVBoard {
    /// Seconds each card shows.
    public static let turnSeconds: Double = 15

    /// The cards with something to show, in rotation order. Guest-friendly
    /// mode leaves out the private ones.
    public static func cards(_ snapshot: Snapshot?, guest: Bool) -> [TVCard] {
        guard let snapshot else { return [] }
        var out: [TVCard] = []
        // Jarvis's message first, guests included (Dylan, 2026-11-18: "the
        // message always gets cut off… put it as one of the items that
        // rotate, maybe the first one").
        if greeting(snapshot, guest: guest)?.body != nil { out.append(.message) }
        if !TodayTimeline.rows(snapshot.today, events: snapshot.events, now: Date(), guest: guest).isEmpty { out.append(.today) }
        if !HomeGlance.lines(snapshot.home).isEmpty { out.append(.home) }
        if !(snapshot.home?.devices ?? []).isEmpty { out.append(.devices) }
        if !playing(snapshot.home).isEmpty { out.append(.playing) }
        if (snapshot.home?.forecast?.count ?? 0) >= 3 { out.append(.forecast) }
        // What Jarvis is chasing down, with live timers (Dylan, 2026-11-18).
        if !(snapshot.jobs?.running.isEmpty ?? true) { out.append(.tasks) }
        if !snapshot.services.isEmpty { out.append(.jarvis) }
        if let lookout = snapshot.jobs?.lookout, !lookout.watching.isEmpty || (snapshot.jobs?.messenger?.sentToday ?? 0) > 0 || !lookout.checks.isEmpty {
            out.append(.lookout)
        }
        if SleepSlide.shows(snapshot) { out.append(.sleep) }
        if SleepSlide.showsYou(snapshot) { out.append(.health) }
        if !(snapshot.offers?.offers.isEmpty ?? true) { out.append(.suggestions) }
        // No reports on the TV (Dylan, 2026-11-21): they're read on the iPhone and iPad.
        // The PC (rawValue "gpu" kept so `-tvCard gpu` still works).
        if !snapshot.systemGauges.isEmpty { out.append(.gpu) }
        return guest ? out.filter { !$0.isPrivate } : out
    }

    /// Media playing or on, most recent first as Home Assistant lists them.
    public static func playing(_ home: Home?) -> [Device] {
        (home?.devices ?? []).filter { $0.kind == "media" && $0.isAvailable && ($0.state == "playing" || $0.state == "paused") }
    }

    /// The forecast icon for an hour: a moon after dark where the weather
    /// service still says "sunny" or "clear".
    public static func forecastSymbol(_ hour: ForecastHour, sunrise: Date?, sunset: Date?) -> String {
        let symbol = TodayWording.weatherSymbol(hour.condition)
        guard let at = AgendaTime.parse(hour.at), let sunrise, let sunset else { return symbol }
        let arc = SkyArc.at(now: at, sunrise: sunrise, sunset: sunset)
        guard !arc.sun else { return symbol }
        switch symbol {
        case "sun.max.fill": return "moon.stars.fill"
        case "cloud.sun.fill": return "cloud.moon.fill"
        default: return symbol
        }
    }

    /// The hero card as the TV shows it: guests don't see where.
    public static func hero(_ snapshot: Snapshot, now: Date, guest: Bool) -> NowNext? {
        guard let pick = NowNext.pick(events: snapshot.events, agenda: snapshot.today, now: now) else { return nil }
        return guest ? NowNext(kind: pick.kind, title: pick.title, start: pick.start, end: pick.end, location: nil) : pick
    }

    /// What follows the event on now, for the strip's Next side; nil when
    /// nothing is on now (the hero already is the next one).
    public static func after(_ snapshot: Snapshot, now: Date, guest: Bool) -> NowNext? {
        guard let next = NowNext.after(events: snapshot.events, agenda: snapshot.today, now: now) else { return nil }
        return guest ? NowNext(kind: next.kind, title: next.title, start: next.start, end: next.end, location: nil) : next
    }

    /// The greeting as the TV shows it: the short headline across the top
    /// and the rest on the From Jarvis card. Since Dylan asked for the card
    /// in the rotation, guests see it too (`guest` is kept for when he
    /// wants it hidden again).
    public static func greeting(_ snapshot: Snapshot?, guest: Bool) -> (headline: String, body: String?)? {
        guard let text = snapshot?.offers?.greeting, !text.isEmpty else { return nil }
        let parts = TodayWording.greetingParts(text)
        _ = guest
        return (parts.headline, parts.body)
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

// MARK: Night

/// The TV's calm bedroom layout (Dylan, 2026-11-17): from 2:30 AM until
/// half an hour before sunrise, only the clock, the date, the moon and
/// stars, the dimmed orb and one line if something's on before 10 AM. Any
/// press on the remote brings the full board back for a minute.
public enum NightCalm {
    /// How bright the night view's words are (Dylan, 2026-11-19: the white
    /// letters and numbers "are too bright" in a dark bedroom): the big
    /// clock at 40%, the date and the morning line a little lower at 32%.
    public static let clockOpacity = 0.40
    public static let secondaryOpacity = 0.32
    /// The big orb behind the clock: dim and low, so the room stays dark.
    public static let orbOpacity = 0.16

    /// When the calm layout starts (Dylan: "not from midnight, from 2:30 am").
    public static let startHour = 2, startMinute = 30
    /// Minutes before sunrise the full board comes back.
    public static let wakeLead: Double = 30
    /// How long a remote press shows the full board.
    public static let pressSeconds: Double = 60
    /// Things starting before this hour get the small morning line.
    public static let morningHour = 10

    /// True when the calm layout should show.
    public static func isCalm(now: Date, sunrise: Date, enabled: Bool, wokenUntil: Date?, calendar: Calendar = .current) -> Bool {
        guard enabled else { return false }
        if let wokenUntil, now < wokenUntil { return false }
        let start = calendar.date(bySettingHour: startHour, minute: startMinute, second: 0, of: now) ?? calendar.startOfDay(for: now)
        // Today's sunrise, whatever day the snapshot's time is from.
        let parts = calendar.dateComponents([.hour, .minute, .second], from: sunrise)
        let rise = calendar.date(bySettingHour: parts.hour ?? 6, minute: parts.minute ?? 30, second: parts.second ?? 0, of: now) ?? start
        return now >= start && now < rise.addingTimeInterval(-wakeLead * 60)
    }

    /// The small line for the calm layout: what's on before 10 AM today
    /// ("Dentist at 9:00 AM"), or nil.
    public static func morningLine(events: [CalendarEvent], agenda: [AgendaItem], now: Date, guest: Bool, calendar: Calendar = .current, timeZone: TimeZone = .current) -> String? {
        let cutoff = calendar.date(bySettingHour: morningHour, minute: 0, second: 0, of: now) ?? now
        var starts: [(String, Date)] = events.compactMap { e in
            guard e.allDay != true, let start = AgendaTime.parse(e.start) else { return nil }
            return (e.title, start)
        }
        starts += agenda.filter { !NowNext.isJarvisJob($0) && $0.allDay != true }.compactMap { item in AgendaTime.parse(item.at).map { (item.title, $0) } }
        guard let first = starts.filter({ $0.1 > now && $0.1 < cutoff }).min(by: { $0.1 < $1.1 }) else { return nil }
        _ = guest // titles are fine for guests; the place is never shown here
        return "\(first.0) at \(NowNext.clock(first.1, timeZone: timeZone))"
    }
}

// MARK: Lookout

public enum LookoutCard {
    /// "3 of 8 messages today", "No messages today".
    public static func messagesLine(_ messenger: Messenger?) -> String? {
        guard let messenger else { return nil }
        if messenger.sentToday == 0 { return "No messages today" }
        let noun = messenger.sentToday == 1 ? "message" : "messages"
        if let cap = messenger.cap, cap > 0 { return "\(messenger.sentToday) of \(cap) \(noun) today" }
        return "\(messenger.sentToday) \(noun) today"
    }
}

// MARK: Active tasks

public enum TaskCard {
    /// A task's line on the TV: its name, or for guests just "A task", since
    /// a task's name can say what Dylan is up to.
    public static func title(_ task: RunningTask, index: Int, guest: Bool) -> String {
        guest ? "Task \(index + 1)" : task.label
    }
}


// MARK: Swiping cards

/// Paging the TV's cards with the remote (Dylan, 2026-11-18: "if I swipe on
/// the Apple TV remote, it basically swipes the panel as well and can go to
/// the next (or previous) one").
public enum CardSwipe {
    /// After a swipe the card he chose stays up this long before the
    /// automatic rotation carries on.
    public static let pauseSeconds: Double = 60

    /// Which card a turn count shows, wrapping both ways.
    public static func index(turn: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return ((turn % count) + count) % count
    }

    /// True when the automatic rotation may move on.
    public static func autoAdvanceAllowed(lastSwipe: Date?, now: Date = Date()) -> Bool {
        guard let lastSwipe else { return true }
        return now.timeIntervalSince(lastSwipe) >= pauseSeconds
    }
}
