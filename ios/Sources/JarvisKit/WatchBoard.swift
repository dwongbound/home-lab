// What the Watch shows besides answers (Dylan, 2026-11-18: the Watch app
// "with helpful complications as well"): the notices (orange: need him),
// the tasks Jarvis is chasing (blue), and what's next today. The phone
// builds it from the snapshot and hands it over WatchConnectivity; the
// Watch's complications read a small cached copy. No money, ever.
import Foundation

/// One notice as the Watch shows it.
public struct WatchNotice: Equatable, Identifiable, Sendable {
    public let id: String
    public let kind: NoticeKind
    public let title: String
    public let body: String
    public let source: String
    public let approvalId: String?

    public init(_ notice: Notice) {
        id = notice.id; kind = notice.kind; title = notice.title; body = notice.body
        source = notice.source; approvalId = notice.approvalId
    }

    init?(row: [String: String]) {
        guard let id = row["id"], let title = row["title"] else { return nil }
        self.id = id
        kind = NoticeKind(rawValue: row["kind"] ?? "") ?? .fyi
        self.title = title
        body = row["body"] ?? ""
        source = row["source"] ?? "message"
        approvalId = row["approvalId"].flatMap { $0.isEmpty ? nil : $0 }
    }

    var row: [String: String] {
        var out = ["id": id, "kind": kind.rawValue, "title": title, "body": body, "source": source]
        if let approvalId { out["approvalId"] = approvalId }
        return out
    }
}

/// The Watch's board: notices, running tasks and the next thing today.
public struct WatchBoard: Equatable, Sendable {
    public var notices: [WatchNotice]
    /// Task names and their starts (ISO), for blue dots and timers.
    public var tasks: [(label: String, startedAt: String?)]
    public var nextTitle: String?
    /// When the next thing starts (ISO).
    public var nextAt: String?

    public static func == (a: WatchBoard, b: WatchBoard) -> Bool {
        a.notices == b.notices && a.tasks.map(\.label) == b.tasks.map(\.label) && a.tasks.map(\.startedAt) == b.tasks.map(\.startedAt) && a.nextTitle == b.nextTitle && a.nextAt == b.nextAt
    }

    public init(notices: [WatchNotice] = [], tasks: [(label: String, startedAt: String?)] = [], nextTitle: String? = nil, nextAt: String? = nil) {
        self.notices = notices; self.tasks = tasks; self.nextTitle = nextTitle; self.nextAt = nextAt
    }

    /// From the phone's snapshot: unread notices newest first, running tasks,
    /// and the next event or agenda item still to come today.
    public init(snapshot: Snapshot?, now: Date = Date()) {
        notices = Notices.sorted(snapshot?.notices ?? []).prefix(12).map(WatchNotice.init)
        tasks = (snapshot?.jobs?.running ?? []).map { ($0.label, $0.startedAt) }
        let next = snapshot.flatMap { s in
            NowNext.pick(events: s.events, agenda: s.today, now: now).flatMap { $0.kind == .tomorrow ? nil : $0 }
        }
        nextTitle = next?.title
        nextAt = next.map { ISO8601DateFormatter().string(from: $0.start) }
    }

    /// As a WatchConnectivity dictionary.
    public var message: [String: Any] {
        var out: [String: Any] = [
            "notices": notices.map(\.row),
            "tasks": tasks.map { ["label": $0.label, "startedAt": $0.startedAt ?? ""] },
        ]
        if let nextTitle { out["nextTitle"] = nextTitle }
        if let nextAt { out["nextAt"] = nextAt }
        return out
    }

    /// Reads one back; missing parts read as empty.
    public init(message: [String: Any]) {
        notices = (message["notices"] as? [[String: String]] ?? []).compactMap(WatchNotice.init(row:))
        tasks = (message["tasks"] as? [[String: String]] ?? []).compactMap { row in
            guard let label = row["label"] else { return nil }
            let start = row["startedAt"] ?? ""
            return (label, start.isEmpty ? nil : start)
        }
        nextTitle = message["nextTitle"] as? String
        nextAt = message["nextAt"] as? String
    }
}

/// What the complications show, cached on the Watch with when it came.
public struct ComplicationData: Equatable, Sendable {
    /// Orange: notices that want Dylan.
    public var needCount: Int
    /// Blue: tasks Jarvis is running.
    public var runningCount: Int
    public var nextTitle: String?
    public var nextAt: String?
    /// When the phone sent it.
    public var updated: Date

    /// Older than this, the complications say they're out of date.
    public static let staleAfter: TimeInterval = 45 * 60

    public init(board: WatchBoard, updated: Date = Date()) {
        needCount = board.notices.count
        runningCount = board.tasks.count
        nextTitle = board.nextTitle
        nextAt = board.nextAt
        self.updated = updated
    }

    public init(needCount: Int, runningCount: Int, nextTitle: String?, nextAt: String?, updated: Date) {
        self.needCount = needCount; self.runningCount = runningCount
        self.nextTitle = nextTitle; self.nextAt = nextAt; self.updated = updated
    }

    /// As the dictionary the phone sends and the Watch keeps.
    public var dictionary: [String: Any] {
        var out: [String: Any] = ["need": needCount, "running": runningCount, "updated": updated.timeIntervalSince1970]
        if let nextTitle { out["nextTitle"] = nextTitle }
        if let nextAt { out["nextAt"] = nextAt }
        return out
    }

    public init?(dictionary: [String: Any]) {
        guard let updated = dictionary["updated"] as? Double else { return nil }
        needCount = dictionary["need"] as? Int ?? 0
        runningCount = dictionary["running"] as? Int ?? 0
        nextTitle = dictionary["nextTitle"] as? String
        nextAt = dictionary["nextAt"] as? String
        self.updated = Date(timeIntervalSince1970: updated)
    }

    public func isStale(now: Date = Date()) -> Bool {
        now.timeIntervalSince(updated) > Self.staleAfter
    }

    /// "2 need you · 1 running", "All clear", or "Open Jarvis to update".
    public func summary(now: Date = Date()) -> String {
        if isStale(now: now) { return "Open Jarvis to update" }
        var parts: [String] = []
        if needCount > 0 { parts.append("\(needCount) need you") }
        if runningCount > 0 { parts.append("\(runningCount) running") }
        return parts.isEmpty ? "All clear" : parts.joined(separator: " · ")
    }

    /// "Volleyball · 6:42 PM", or nil with nothing next (or stale data).
    public func nextLine(now: Date = Date(), timeZone: TimeZone = .current) -> (title: String, time: String)? {
        guard !isStale(now: now), let nextTitle, let nextAt, let start = AgendaTime.parse(nextAt), start > now else { return nil }
        return (nextTitle, NowNext.clock(start, timeZone: timeZone))
    }
}

/// Where the Watch keeps the complication data, shared between the Watch
/// app and its complications (an App Group).
public enum ComplicationStore {
    public static let suite = "group.com.dwongbound.jarvis"
    static let key = "complication"

    /// Keeps the latest data.
    public static func save(_ data: ComplicationData, defaults: UserDefaults? = UserDefaults(suiteName: suite)) {
        defaults?.set(data.dictionary, forKey: key)
    }

    /// The latest data, or nil before the phone has sent any.
    public static func load(defaults: UserDefaults? = UserDefaults(suiteName: suite)) -> ComplicationData? {
        (defaults?.dictionary(forKey: key)).flatMap(ComplicationData.init(dictionary:))
    }
}
