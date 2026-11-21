// The notification centre (Dylan, 2026-11-18: "since I want to use the
// Jarvis app for notifications, we need a visual notifications center…",
// then the "pips on the orb" design). The page server keeps one shared list
// of unread notices in the snapshot; clearing one anywhere clears it
// everywhere. Each notice is a pip circling the orb: orange when it needs
// Dylan, blue for a heads-up, dim white for an FYI. These are the rules the
// iPhone, iPad and TV share: which pips show, the count, the row wording.
import Foundation

/// How much a notice wants Dylan.
public enum NoticeKind: String, Decodable, Sendable, Comparable {
    case need, heads, fyi

    /// Unknown kinds from a newer server read as FYI.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = NoticeKind(rawValue: raw) ?? .fyi
    }

    /// Need first, then heads-up, then FYI.
    private var rank: Int { self == .need ? 0 : self == .heads ? 1 : 2 }
    public static func < (a: NoticeKind, b: NoticeKind) -> Bool { a.rank < b.rank }
}

/// One unread notice.
public struct Notice: Decodable, Identifiable, Equatable, Sendable {
    public let id: String
    public let kind: NoticeKind
    public let title: String
    public let body: String
    /// approval, lookout, reminder, alert, job or message.
    public let source: String
    /// When it was made (ISO).
    public let created: String
    /// For an approval: the id the Approve and Deny buttons answer.
    public let approvalId: String?
    /// The chat turn this notice previews (the full message lives there).
    public let turnId: Int?
    /// The report a "Report ready" notice is about (16 lowercase hex), so a
    /// tap opens /reports/{id}. Anything else reads as none.
    public let reportId: String?
    /// Kept to remember later (Dylan, 2026-11-19): a yellow dot, never
    /// unread, untouched by Clear; only Let go removes it.
    public let kept: Bool

    public init(id: String, kind: NoticeKind, title: String, body: String = "", source: String, created: String, approvalId: String? = nil, turnId: Int? = nil, reportId: String? = nil, kept: Bool = false) {
        self.id = id; self.kind = kind; self.title = title; self.body = body
        self.source = source; self.created = created; self.approvalId = approvalId; self.turnId = turnId
        self.reportId = reportId.flatMap { Reports.isId($0) ? $0 : nil }
        self.kept = kept
    }

    enum CodingKeys: String, CodingKey { case id, kind, title, body, source, created, approvalId, turnId, reportId, kept }

    /// Missing optional parts read as empty rather than failing the notice.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = (try? c.decode(NoticeKind.self, forKey: .kind)) ?? .fyi
        title = try c.decode(String.self, forKey: .title)
        body = (try? c.decodeIfPresent(String.self, forKey: .body)) ?? ""
        source = (try? c.decodeIfPresent(String.self, forKey: .source)) ?? "message"
        created = (try? c.decodeIfPresent(String.self, forKey: .created)) ?? ""
        approvalId = try? c.decodeIfPresent(String.self, forKey: .approvalId)
        turnId = try? c.decodeIfPresent(Int.self, forKey: .turnId)
        reportId = (try? c.decodeIfPresent(String.self, forKey: .reportId)).flatMap { $0 }.flatMap { Reports.isId($0) ? $0 : nil }
        kept = ((try? c.decodeIfPresent(Bool.self, forKey: .kept)) ?? nil) ?? false
    }

    /// The report page this notice opens, if it's a "Report ready" one.
    public func reportURL(base: URL = JarvisClient.defaultBase) -> URL? {
        reportId.flatMap { Reports.url(id: $0, base: base) }
    }

    /// The words on the control that clears it: a reminder's "Done" (it's
    /// been heard, so the nag stops), anything else "Dismiss". One word
    /// each (Dylan, 2026-11-19: "buttons shouldnt be more than one or two
    /// words"; this used to read "Got it, stop reminding me").
    public var clearLabel: String {
        (source == "reminder" ? NoticeAction.done : .dismiss).label
    }

    /// True when the row carries Approve and Deny.
    public var isApproval: Bool { approvalId != nil }
}

public enum Notices {
    /// The most pips drawn round an orb; more still count.
    public static let maxPips = Int.max

    /// The pips to draw: one per notice, needs first. At night only the
    /// ones that need Dylan, so the bedroom stays dark.
    public static func pips(_ notices: [Notice], night: Bool = false) -> [NoticeKind] {
        let kinds = notices.map(\.kind).filter { !night || $0 == .need }
        return kinds.sorted()
    }

    /// The one dot beside the count in the top bar (Dylan, 2026-11-19: "no
    /// matter how many there is … only one orange dot"): the most urgent
    /// unread notice's kind, which sets its shade; nil (no dot) with none.
    public static func headerDot(_ notices: [Notice]) -> NoticeKind? {
        notices.map(\.kind).min()
    }

    /// The kind in words for VoiceOver: "Kept", "Needs you", "Reminder",
    /// "Heads up" or "For your information".
    public static func kindWords(_ notice: Notice) -> String {
        if notice.kept { return "Kept" }
        if notice.kind == .need { return "Needs you" }
        if notice.source == "reminder" { return "Reminder" }
        return notice.kind == .heads ? "Heads up" : "For your information"
    }

    /// The unread ones: everything not kept. Kept items never count as new.
    public static func unread(_ notices: [Notice]) -> [Notice] {
        notices.filter { !$0.kept }
    }

    /// The kept ones (yellow dots), oldest kept first as they came.
    public static func kept(_ notices: [Notice]) -> [Notice] {
        notices.filter(\.kept)
    }

    /// The kept notice for a chat turn, if that message is kept.
    public static func kept(turnId: Int, in notices: [Notice]) -> Notice? {
        notices.first { $0.kept && $0.turnId == turnId }
    }

    /// The top bar's button (Dylan, 2026-11-19: "it should show blue and
    /// orange if there's also a thread running"): which dots show and its
    /// words. Nil when there's nothing new and nothing running.
    public static func statusButton(unread: [Notice], running: Int) -> (orange: NoticeKind?, blue: Bool, words: String)? {
        let orange = headerDot(unread)
        let blue = running > 0
        if orange == nil && !blue { return nil }
        var words = countLabel(unread) ?? "\(running) running"
        if orange != nil && blue { words += " · \(running) running" }
        return (orange, blue, words)
    }

    /// "3 new", or nil with none.
    public static func countLabel(_ notices: [Notice]) -> String? {
        notices.isEmpty ? nil : "\(notices.count) new"
    }

    /// Newest first (unparseable times last).
    public static func sorted(_ notices: [Notice]) -> [Notice] {
        // Each time read once, not once per comparison.
        notices.map { ($0, AgendaTime.parse($0.created) ?? .distantPast) }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    /// The text of notices shows only outside guest view; guests see pips
    /// and the count.
    public static func showsText(guest: Bool) -> Bool { !guest }

    /// "now", "12 min", "3 h", "Yesterday", "Mon".
    public static func when(_ created: String, now: Date = Date(), calendar: Calendar = .current) -> String {
        guard let date = AgendaTime.parse(created) else { return "" }
        let minutes = Int(now.timeIntervalSince(date) / 60)
        if minutes < 1 { return "now" }
        if minutes < 60 { return "\(minutes) min" }
        if calendar.isDate(date, inSameDayAs: now) { return "\(minutes / 60) h" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) { return "Yesterday" }
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US")
        format.timeZone = calendar.timeZone
        format.dateFormat = minutes < 7 * 24 * 60 ? "EEE" : "MMM d"
        return format.string(from: date)
    }

    /// The SF Symbol for where a notice came from.
    public static func symbol(_ source: String) -> String {
        switch source {
        case "approval": return "hand.raised.fill"
        case "lookout": return "binoculars.fill"
        case "reminder": return "bell.fill"
        case "alert": return "exclamationmark.triangle.fill"
        case "job": return "checkmark.seal.fill"
        default: return "text.bubble.fill"
        }
    }
}

/// The Apple TV's in-app banner (Dylan, 2026-11-18: "can there be
/// notifications on my apple tv somehow? Or an in app banner at least").
/// tvOS shows no notification banners of its own, so the TV slides one in
/// when a new notice turns up in the snapshot.
public enum TVBanner {
    /// How long a banner stays: about 8 seconds.
    public static func seconds(_ notice: Notice) -> Double { 8 }

    /// The notices new since the last snapshot, oldest first so they show
    /// in the order they came. The first snapshot after launch shows none
    /// (they're not news, just what was already waiting). At night only
    /// the ones that need Dylan.
    public static func arrivals(seen: Set<String>?, now notices: [Notice], night: Bool) -> [Notice] {
        guard let seen else { return [] }
        return Notices.sorted(notices).reversed().filter { !seen.contains($0.id) && (!night || $0.kind == .need) }
    }

    /// One banner for a batch of arrivals: the newest, and how many more.
    public static func banner(_ arrivals: [Notice]) -> (notice: Notice, more: Int)? {
        guard let newest = arrivals.last else { return nil }
        return (newest, arrivals.count - 1)
    }

    /// The banner's words: the title, a short body and "+N more" in full
    /// view; in guest view only "New notification" / "N new notifications",
    /// never what they say.
    public static func words(_ notice: Notice, more: Int = 0, guest: Bool) -> (title: String, body: String?) {
        if guest { return (more == 0 ? "New notification" : "\(more + 1) new notifications", nil) }
        let extra = more > 0 ? "+\(more) more" : nil
        let body = [notice.body.isEmpty ? nil : notice.body, extra].compactMap { $0 }.joined(separator: " · ")
        return (notice.title, body.isEmpty ? nil : body)
    }
}

/// What a keep or unkeep said back: ok, its words, and the kept item when
/// Jarvis sends it (otherwise the next snapshot has it).
public struct KeepResult: Equatable, Sendable {
    public let ok: Bool
    public let message: String
    public let notice: Notice?

    /// Reads {ok, message, notice?}; anything but a 2xx with ok is a refusal.
    public static func read(status: Int, data: Data) -> KeepResult {
        struct Body: Decodable { let ok: Bool?; let message: String?; let notice: Notice? }
        let body = try? JSONDecoder().decode(Body.self, from: data)
        let ok = (200..<300).contains(status) && (body?.ok ?? true)
        return KeepResult(ok: ok, message: body?.message ?? (ok ? "" : "Jarvis answered \(status)"), notice: body?.notice)
    }
}

/// What can be done to a notice, in one or two words each, so every button
/// and swipe that shows one reads the same.
public enum NoticeAction: Equatable, Sendable, CaseIterable {
    case open, dismiss, done, approve, deny, unkeep, keep, seeInChat
    /// The note's whole text in the bottom sheet (Dylan, 2026-11-20: "see
    /// more" like the notification center's).
    case seeMore

    public var label: String {
        switch self {
        case .open: return "Open"
        case .dismiss: return "Dismiss"
        case .done: return "Done"
        case .approve: return "Approve"
        case .deny: return "Deny"
        // A kept item's way out reads Dismiss (Dylan, 2026-11-21): letting
        // it go takes it off the list, like dismissing any notice.
        case .unkeep: return "Dismiss"
        case .keep: return "Keep"
        case .seeInChat: return "See in chat"
        case .seeMore: return "See more"
        }
    }

    /// The buttons along the bottom of the orb's note card, secondary first
    /// and the main one last (it sits on the right). `canOpen`: the note
    /// has a message to open; `canDismiss`: it can be cleared from here.
    public static func card(kind: OrbitItem.Kind, notice: Notice?, canOpen: Bool, canDismiss: Bool) -> [NoticeAction] {
        if notice?.isApproval == true { return [.deny, .approve] }
        switch kind {
        case .task:
            return canOpen ? [.open] : []
        case .kept:
            return [.unkeep] + (canOpen ? [.seeMore] : [])
        case .notice:
            let clear: NoticeAction = notice?.source == "reminder" ? .done : .dismiss
            // Keep turns it into a yellow dot that stays (Dylan, 2026-11-20:
            // "a way to keep a glowing orb after seeing it").
            if notice?.source == "reminder" {
                // A reminder's main act is "Done" (stop the nag).
                return (canDismiss ? [.keep] : []) + (canOpen ? [.seeMore] : []) + (canDismiss ? [clear] : [])
            }
            return (canDismiss ? [clear, .keep] : []) + (canOpen ? [.seeMore] : [])
        }
    }
}

/// Notices cleared here before the server has confirmed it: hidden at once,
/// shown again if the server didn't take it (the drawer's swipe, Dismiss).
public struct PendingClears: Equatable, Sendable {
    public private(set) var ids: Set<String> = []
    public init() {}
    public mutating func hide(_ some: [String]) { ids.formUnion(some) }
    public mutating func restore(_ some: [String]) { ids.subtract(some) }
    public func visible(_ notices: [Notice]) -> [Notice] { notices.filter { !ids.contains($0.id) } }
}

/// Where a tap on a notice (or its push) lands (Dylan, 2026-11-20: "when i
/// click a notification and its no longer in the chat history, it just
/// glitches"): the message in Chat when that turn is really there after
/// loading round it, otherwise the notice's own full text. Never the bottom
/// of Chat as if something had been found.
public enum NoticeFocus: Equatable, Sendable {
    case scroll(to: Int)
    case read

    /// `loaded`: the turn ids held after asking history for a window round
    /// the turn (a failed or unknown-id answer simply won't contain it).
    public static func outcome(turnId: Int?, loaded: [Int]) -> NoticeFocus {
        guard let turnId, loaded.contains(turnId) else { return .read }
        return .scroll(to: turnId)
    }

    /// A long body: worth a "More" on the row.
    public static func isLong(_ body: String) -> Bool { body.count > 120 || body.contains("\n") }
}

/// A notice's whole text, from the chat turn it points to (Dylan,
/// 2026-11-20: "when tapping view more, i should see everything"). The page
/// server cuts a notice's title and body at 300 characters each; the turn
/// holds the message as Jarvis wrote it, usually the title's line then the
/// body.
public struct NoticeFullText: Equatable, Sendable {
    public let title: String
    public let body: String

    /// The cap the page server puts on a notice's title and body.
    public static let wireCap = 300

    /// The whole text, or nil when the turn says no more than the notice.
    public static func from(turn: String, title: String, body: String) -> NoticeFullText? {
        let text = turn.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > title.count + body.count + 1 else { return nil }
        let stem = String(title.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: ".…")).prefix(30))
        let lines = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        if let first = lines.first, !stem.isEmpty, first.hasPrefix(stem) {
            let rest = lines.count > 1 ? String(lines[1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
            return NoticeFullText(title: String(first), body: rest)
        }
        return NoticeFullText(title: title, body: text)
    }
}
