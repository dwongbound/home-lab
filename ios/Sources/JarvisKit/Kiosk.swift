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
    /// Jarvis's suggestions (offers), titles only.
    case offers
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
        if !HomeGlance.lines(snapshot.home).isEmpty { out.append(.home) }
        if !(snapshot.jobs?.running.isEmpty ?? true) { out.append(.work) }
        if snapshot.health?.sleep?.asleepMin != nil || snapshot.health?.yesterday?.steps != nil { out.append(.health) }
        if !(snapshot.offers?.offers.isEmpty ?? true) { out.append(.offers) }
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

    /// What tapping a kiosk's orb does (Dylan, 2026-11-18: "even while the
    /// kiosk mode is on we should be able to talk to Jarvis… tap the orb…
    /// talk mode without any text or buttons").
    public enum OrbTap: Equatable, Sendable { case start, hangUp, nothing }

    /// Off: start a call. On in any way, dozing included: hang up fully, so
    /// the mic is off and the wake word can't bring him back (Dylan: "if
    /// tapped again it will go back to idle and not listen"). Still
    /// calling: wait, a second tap mid-dial would race the line.
    public static func orbTap(callOpen: Bool, connecting: Bool) -> OrbTap {
        if connecting { return .nothing }
        return callOpen ? .hangUp : .start
    }

    /// When the bedside display goes away mid-call, the call carries on in
    /// the Talk tab rather than dropping.
    public static func handOverToTalk(callLive: Bool) -> Bool { callLive }
}

/// Icons for the kiosk screens (Dylan, 2026-11-17: "for a kiosk the more
/// icons and images / emojis the better"). One emoji, for the greeting;
/// SF Symbols everywhere else, so the TV, iPad kiosk and bedside display
/// match.
public enum KioskIcons {
    /// 🌙 late night, 🌅 early morning, ☀️ day, 🌇 evening.
    public static func greetingEmoji(hour: Int) -> String {
        switch hour {
        case 5..<8: return "🌅"
        case 8..<17: return "☀️"
        case 17..<20: return "🌇"
        default: return "🌙"
        }
    }

    /// A symbol for a schedule item, from the words in its title.
    public static func agendaSymbol(_ title: String) -> String {
        let t = title.lowercased()
        func has(_ words: [String]) -> Bool { words.contains { t.contains($0) } }
        if has(["flight", "fly ", "flying", "pilot", "airport", "ground school", "checkride"]) { return "airplane" }
        if has(["church", "worship", "service", "rehearsal", "practice", "sow", "cg "]) { return "music.note.house.fill" }
        if has(["remind", "reminder", "nag"]) { return "bell.fill" }
        if has(["jarvis", "pickup run", "lookout", "nightly"]) { return "sparkles" }
        if has(["volleyball", "gym", "run ", "workout", "golf", "hike"]) { return "figure.run" }
        if has(["study", "test", "exam", "class", "homework"]) { return "book.fill" }
        if has(["dinner", "lunch", "breakfast", "coffee"]) { return "fork.knife" }
        if has(["call", "meeting", "1:1", "interview"]) { return "person.2.fill" }
        return "calendar"
    }
}

/// The Apple TV's Night button (Dylan, 2026-11-18: "when I click night, it
/// should change to the minimal night mode… clicking the remote should back
/// out of it… that should also signal to Jarvis that I'm sleeping. It should
/// know I'm awake when I first wake up and talk to Jarvis").
public enum NightButton {
    /// Backing out this soon after pressing Night reads as a mis-press, and
    /// tells Jarvis he's awake after all. Later, Jarvis works it out himself
    /// the next time Dylan talks to him.
    public static let misPressSeconds: Double = 10 * 60

    /// True when backing out of night should send "awake".
    public static func sendAwakeOnExit(pressedAt: Date, now: Date) -> Bool {
        now.timeIntervalSince(pressedAt) < misPressSeconds
    }
}

/// The iPad going to its kiosk by itself (Dylan, 2026-11-18: "after being
/// in the talk tab or the chat tab for like 5 minutes without any action
/// AND the ipad is charging, it should automatically switch over to the
/// always on ipad kiosk mode").
public enum IdleKiosk {
    /// How long with nothing happening before the kiosk comes up.
    public static let idleSeconds: Double = 5 * 60

    /// True when the kiosk should come up now: the setting is on, the Talk
    /// or Chat tab is showing, it's on power, no conversation is going, and
    /// nothing has been touched or typed for five minutes.
    public static func shouldEnter(enabled: Bool, onTalkOrChat: Bool, charging: Bool, conversationActive: Bool, lastActivity: Date, now: Date) -> Bool {
        enabled && onTalkOrChat && charging && !conversationActive && now.timeIntervalSince(lastActivity) >= idleSeconds
    }
}


/// The app's pages swipe sideways; the keyboard goes away as a swipe
/// starts (Dylan, 2026-11-18), not only once the next page lands.
public enum PageSwipe {
    /// How much more sideways than up-and-down a drag must be to count.
    public static let ratio = 2.0
    /// How far it must have gone, in points.
    public static let minDistance = 20.0

    /// True when a drag so far is a page swipe, not a scroll.
    public static func isSideways(width: Double, height: Double) -> Bool {
        abs(width) >= minDistance && abs(width) > abs(height) * ratio
    }
}

/// When landing on the Talk page starts a call (Dylan, 2026-11-19: with the
/// pages Home, Talk, Chat, swiping from Home to Chat passes Talk and must
/// not call Jarvis). The page has to stay selected for a moment first.
public enum TalkSettle {
    /// How long Talk must stay the page before the call starts.
    public static let seconds: Double = 0.7

    /// Whether to start the call now: Talk is still the page, it has been
    /// for long enough, and no call has started yet.
    public static func shouldStart(onTalk: Bool, landedAt: Date, now: Date = Date(), started: Bool) -> Bool {
        onTalk && !started && now.timeIntervalSince(landedAt) >= seconds
    }
}

/// When the bottom tab bar is full size (Dylan, 2026-11-19: "the bottom
/// glass navbar shrinks and just shows the icons unless it's in focus like
/// I'm using it"). It rests compact; it opens while he's using it.
public enum TabBarSize {
    /// How long it stays open after the last touch, tab change or scroll up.
    public static let holdSeconds: Double = 2

    /// Full size when touched, changed or scrolled up within the last two
    /// seconds; compact at once on a scroll down, on Talk, and otherwise.
    public static func expanded(lastInteraction: Date?, now: Date = Date(), scrollingDown: Bool, onTalk: Bool) -> Bool {
        if onTalk || scrollingDown { return false }
        guard let lastInteraction else { return false }
        return now.timeIntervalSince(lastInteraction) < holdSeconds
    }

    /// Whether a scroll by `delta` points (positive = content moved down the
    /// page, i.e. reading further) counts as scrolling down; small jitters don't.
    public static func isScrollDown(_ delta: Double) -> Bool? {
        if delta > 6 { return true }
        if delta < -6 { return false }
        return nil
    }
}

/// The orange "new" dot on the Home tiles (Dylan, 2026-11-19): something in
/// Reports, Playbooks or Diet he hasn't seen since he last opened it. What
/// he's seen is kept on the device; with nothing kept yet (a first launch)
/// there's never a dot, and the current state becomes the seen one.
public enum SeenTracker {
    /// New when any current id wasn't there when he last looked; never on a
    /// first launch (`seen` nil).
    public static func hasNew(current: [String], seen: [String]?) -> Bool {
        guard let seen else { return false }
        return !Set(current).isSubset(of: Set(seen))
    }

    /// Diet's mark: the day and what was eaten ("2026-11-19:1052"); nil
    /// when there's nothing logged today.
    public static func dietMark(_ food: Nutrition?, now: Date = Date()) -> String? {
        guard let food, food.isToday(now: now), food.eaten > 0 else { return nil }
        return "\(food.date):\(Int(food.eaten.rounded()))"
    }

    /// New in Diet when something's been logged today since he last opened it.
    public static func dietHasNew(current: String?, seen: String??) -> Bool {
        guard let seen else { return false }        // never stored: first launch
        guard let current else { return false }      // nothing logged today
        return current != seen
    }
}

/// The Chat input bar (Dylan, 2026-11-19: it "takes a lot of vertical space
/// by always being there"): a slim one-line pill at the bottom of the chat,
/// tucked into a small compose button while he reads further up.
public enum ComposerSize {
    /// Tucked away only while scrolled up and idle: never while the field is
    /// focused, holds words or photos, or Jarvis is answering what he just
    /// sent, nor right after he tapped to open it.
    public static func collapsed(atBottom: Bool, focused: Bool, hasDraft: Bool, sending: Bool, opened: Bool) -> Bool {
        !atBottom && !focused && !hasDraft && !sending && !opened
    }

    /// Whether a new line should pull the chat down to it: at the bottom
    /// already, or it's his own message or the reply to it. Otherwise the
    /// place he's reading stays put and the compose button shows a dot.
    public static func follows(atBottom: Bool, lastIsMine: Bool, sending: Bool) -> Bool {
        atBottom || lastIsMine || sending
    }
}
