// The iPad kiosk's choices (Dylan, 2026-11-17): what earns the big hero
// spot right now, and which panels take turns beside it. Pure, so the
// rules are tested; KioskView draws them. No money here, ever: the kiosk
// is on show to anyone in the room.
import Foundation

/// What fills the kiosk's hero spot, most important first.
public enum KioskHero: Equatable, Sendable {
    /// Jarvis is waiting on an OK.
    case approval(count: Int, summary: String)
    /// A service on the PC is down or struggling.
    case alert(name: String, status: String)
    /// Something on today's schedule starts within the next 45 minutes.
    case soon(title: String, minutes: Int)
    /// Nothing pressing: the greeting and the clock.
    case calm
}

/// The panels that take turns beside the hero.
public enum KioskPanel: String, CaseIterable, Sendable {
    case schedule, home, work, health
}

public enum KioskPlan {
    /// How long each pair of panels shows before the next slides in.
    public static let turnSeconds: Double = 20
    /// How long a touch holds the rotation still.
    public static let touchHoldSeconds: Double = 60

    /// The hero: an approval first, then an alert, then an event soon,
    /// else calm.
    public static func hero(snapshot: Snapshot?, pending: [Approval], now: Date = Date()) -> KioskHero {
        if let first = pending.first {
            return .approval(count: pending.count, summary: ApprovalWording.readableSummary(first.summary))
        }
        if let alert = snapshot?.alerts.first {
            return .alert(name: alert.name, status: alert.status)
        }
        if let soon = nextSoon(snapshot?.today ?? [], now: now) {
            return .soon(title: soon.item.title, minutes: soon.minutes)
        }
        return .calm
    }

    /// The first timed item starting in the next 45 minutes (or just now).
    public static func nextSoon(_ items: [AgendaItem], now: Date) -> (item: AgendaItem, minutes: Int)? {
        items
            .filter { $0.allDay != true }
            .compactMap { item -> (AgendaItem, Int)? in
                guard let start = AgendaTime.parse(item.at) else { return nil }
                let minutes = Int((start.timeIntervalSince(now) / 60).rounded(.up))
                return (0...45).contains(minutes) ? (item, minutes) : nil
            }
            .min { $0.1 < $1.1 }
            .map { (item: $0.0, minutes: $0.1) }
    }

    /// The panels with something to show, in rotation order.
    public static func panels(snapshot: Snapshot?) -> [KioskPanel] {
        guard let snapshot else { return [] }
        var out: [KioskPanel] = [.schedule]
        if !snapshot.homeTiles.isEmpty { out.append(.home) }
        if !(snapshot.jobs?.running.isEmpty ?? true) { out.append(.work) }
        if snapshot.health?.sleep?.asleepMin != nil || snapshot.health?.yesterday?.steps != nil { out.append(.health) }
        return out
    }

    /// The `count` panels to show at turn `turn`, wrapping round.
    public static func showing(_ panels: [KioskPanel], turn: Int, count: Int) -> [KioskPanel] {
        guard !panels.isEmpty else { return [] }
        let n = min(count, panels.count)
        return (0..<n).map { panels[(turn * n + $0) % panels.count] }
    }
}

/// The iPhone's StandBy-style kiosk (Dylan, 2026-11-17: "a simple kiosk mode
/// for iphone too, when it's horizontal + charging"): when it comes up by
/// itself, and when it goes away.
public enum PhoneKiosk {
    /// Which way the phone is held. Flat (on a table) and unknown keep
    /// whatever was showing.
    public enum Orientation: Sendable { case portrait, landscape, flat, unknown }
    /// Whether it's on power.
    public enum Power: Sendable { case unplugged, charging, full, unknown }

    /// The next state from the current one. Turning it upright or unplugging
    /// it always leaves the kiosk and forgets a Close, so the next sideways
    /// charge brings it back; Close keeps it away until then.
    public static func decide(enabled: Bool, orientation: Orientation, power: Power, dismissed: Bool, showing: Bool) -> (showing: Bool, dismissed: Bool) {
        if orientation == .portrait || power == .unplugged { return (false, false) }
        guard enabled else { return (false, dismissed) }
        if orientation == .landscape && (power == .charging || power == .full) {
            return (!dismissed, dismissed)
        }
        return (showing && !dismissed, dismissed)
    }
}
