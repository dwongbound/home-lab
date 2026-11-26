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
    /// A "Report ready" notice: the Watch can't show the page, so it says
    /// to open it on the iPhone (Reports.elsewhere).
    public let isReport: Bool

    public init(_ notice: Notice) {
        id = notice.id; kind = notice.kind; title = notice.title; body = notice.body
        source = notice.source; approvalId = notice.approvalId
        isReport = notice.reportId != nil
    }

    init?(row: [String: String]) {
        guard let id = row["id"], let title = row["title"] else { return nil }
        self.id = id
        kind = NoticeKind(rawValue: row["kind"] ?? "") ?? .fyi
        self.title = title
        body = row["body"] ?? ""
        source = row["source"] ?? "message"
        approvalId = row["approvalId"].flatMap { $0.isEmpty ? nil : $0 }
        isReport = row["report"] == "1"
    }

    var row: [String: String] {
        var out = ["id": id, "kind": kind.rawValue, "title": title, "body": body, "source": source]
        if let approvalId { out["approvalId"] = approvalId }
        if isReport { out["report"] = "1" }
        return out
    }
}

/// One bar on the Watch's Info page: the PC's memory, graphics card or a disk.
public struct WatchBar: Equatable, Sendable {
    public let name: String
    public let usedGb: Double
    public let totalGb: Double

    public init(name: String, usedGb: Double, totalGb: Double) {
        self.name = name; self.usedGb = usedGb; self.totalGb = totalGb
    }
}

/// One thing in the house the Watch's Actions page can switch.
public struct WatchDevice: Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let kind: String
    public var on: Bool

    public init(id: String, name: String, kind: String, on: Bool) {
        self.id = id; self.name = name; self.kind = kind; self.on = on
    }

    /// The home control command that flips it (server/sources/home.mjs).
    public var command: String { kind == "media" ? "power" : "toggle" }
}

/// The Watch's board: notices, running tasks and the next thing today.
public struct WatchBoard: Equatable, Sendable {
    public var notices: [WatchNotice]
    /// Task names and their starts (ISO), for blue dots and timers.
    public var tasks: [(label: String, startedAt: String?)]
    public var nextTitle: String?
    /// When the next thing starts (ISO).
    public var nextAt: String?
    /// Today's calories (numbers only), when Jarvis has them.
    public var nutrition: Nutrition?
    /// Kept notices (yellow dots on the orb).
    public var kept = 0
    /// His most recent night: the score, minutes asleep, and the week's
    /// scores newest first (0 = no score that night).
    public var sleepScore: Int?
    public var sleepMinutes: Double?
    public var sleepTrend: [Int] = []
    /// The PC: memory, graphics card, disks.
    public var pc: [WatchBar] = []
    /// What the Actions page can switch.
    public var devices: [WatchDevice] = []

    public static func == (a: WatchBoard, b: WatchBoard) -> Bool {
        a.notices == b.notices && a.tasks.map(\.label) == b.tasks.map(\.label) && a.tasks.map(\.startedAt) == b.tasks.map(\.startedAt) && a.nextTitle == b.nextTitle && a.nextAt == b.nextAt && a.nutrition == b.nutrition
            && a.kept == b.kept && a.sleepScore == b.sleepScore && a.sleepMinutes == b.sleepMinutes && a.sleepTrend == b.sleepTrend && a.pc == b.pc && a.devices == b.devices
    }

    public init(notices: [WatchNotice] = [], tasks: [(label: String, startedAt: String?)] = [], nextTitle: String? = nil, nextAt: String? = nil, nutrition: Nutrition? = nil) {
        self.notices = notices; self.tasks = tasks; self.nextTitle = nextTitle; self.nextAt = nextAt; self.nutrition = nutrition
    }

    /// From the phone's snapshot: unread notices newest first, running tasks,
    /// and the next event or agenda item still to come today.
    /// Approval rows already over (`settled`, the phone's record) are left off.
    public init(snapshot: Snapshot?, settled: SettledApprovals = SettledApprovals(), now: Date = Date()) {
        // Kept items (yellow) aren't new: the Watch shows only the unread.
        notices = settled.showing(Notices.unread(Notices.sorted(snapshot?.notices ?? []))).prefix(12).map(WatchNotice.init)
        tasks = (snapshot?.jobs?.running ?? []).map { ($0.label, $0.startedAt) }
        let next = snapshot.flatMap { s in
            NowNext.pick(events: s.events, agenda: s.today, now: now).flatMap { $0.kind == .tomorrow ? nil : $0 }
        }
        nextTitle = next?.title
        nextAt = next.map { ISO8601DateFormatter().string(from: $0.start) }
        nutrition = snapshot?.nutrition
        kept = (snapshot?.notices ?? []).filter(\.kept).count
        sleepScore = snapshot?.sleep?.last?.score
        sleepMinutes = snapshot?.sleep?.last?.minutes?.asleep
        sleepTrend = (snapshot?.sleep?.trend ?? []).map { $0.score ?? 0 }
        if let ram = snapshot?.ram, let used = ram.usedMb, let total = ram.totalMb {
            pc.append(WatchBar(name: "Memory", usedGb: used / 1024, totalGb: total / 1024))
        }
        if let gpu = snapshot?.gpu, let used = gpu.usedMb, let total = gpu.totalMb {
            pc.append(WatchBar(name: "Graphics", usedGb: used / 1024, totalGb: total / 1024))
        }
        pc += (snapshot?.disks ?? []).map { WatchBar(name: $0.name, usedGb: $0.usedGb, totalGb: $0.totalGb) }
        devices = (snapshot?.homeTiles ?? [])
            .filter { ["light", "switch", "fan", "media"].contains($0.kind) }
            .prefix(12)
            .map { WatchDevice(id: $0.id, name: $0.name, kind: $0.kind, on: $0.isOn) }
    }

    /// The orb's dots, as on the phone: orange notices, blue tasks, yellow kept.
    public var orbit: [OrbitItem] {
        let orange = notices.map { OrbitItem(id: "notice-" + $0.id, kind: .notice, title: $0.title, detail: $0.body, startedAt: nil, notice: nil) }
        let blue = tasks.enumerated().map { OrbitItem(id: "task-\($0.offset)", kind: .task, title: $0.element.label, detail: "", startedAt: $0.element.startedAt, notice: nil) }
        let yellow = (0..<kept).map { OrbitItem(id: "kept-\($0)", kind: .kept, title: "", detail: "", startedAt: nil, notice: nil) }
        return orange + blue + yellow
    }

    /// As a WatchConnectivity dictionary.
    public var message: [String: Any] {
        var out: [String: Any] = [
            "notices": notices.map(\.row),
            "tasks": tasks.map { ["label": $0.label, "startedAt": $0.startedAt ?? ""] },
        ]
        if let nextTitle { out["nextTitle"] = nextTitle }
        if let nextAt { out["nextAt"] = nextAt }
        if let nutrition { out["nutrition"] = nutrition.dictionary }
        out["kept"] = kept
        if let sleepScore { out["sleepScore"] = sleepScore }
        if let sleepMinutes { out["sleepMinutes"] = sleepMinutes }
        out["sleepTrend"] = sleepTrend
        out["pc"] = pc.map { ["name": $0.name, "used": $0.usedGb, "total": $0.totalGb] as [String: Any] }
        out["devices"] = devices.map { ["id": $0.id, "name": $0.name, "kind": $0.kind, "on": $0.on] as [String: Any] }
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
        nutrition = (message["nutrition"] as? [String: Any]).flatMap(Nutrition.init(dictionary:))
        kept = message["kept"] as? Int ?? 0
        sleepScore = message["sleepScore"] as? Int
        sleepMinutes = message["sleepMinutes"] as? Double
        sleepTrend = message["sleepTrend"] as? [Int] ?? []
        pc = (message["pc"] as? [[String: Any]] ?? []).compactMap { row in
            guard let name = row["name"] as? String, let used = row["used"] as? Double, let total = row["total"] as? Double else { return nil }
            return WatchBar(name: name, usedGb: used, totalGb: total)
        }
        devices = (message["devices"] as? [[String: Any]] ?? []).compactMap { row in
            guard let id = row["id"] as? String, let name = row["name"] as? String else { return nil }
            return WatchDevice(id: id, name: name, kind: row["kind"] as? String ?? "", on: row["on"] as? Bool ?? false)
        }
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
    /// Today's calories, when Jarvis has them.
    public var nutrition: Nutrition?
    /// When the phone sent it.
    public var updated: Date

    /// Older than this, the complications say they're out of date.
    public static let staleAfter: TimeInterval = 45 * 60

    public init(board: WatchBoard, updated: Date = Date()) {
        needCount = board.notices.count
        runningCount = board.tasks.count
        nextTitle = board.nextTitle
        nextAt = board.nextAt
        nutrition = board.nutrition
        self.updated = updated
    }

    public init(needCount: Int, runningCount: Int, nextTitle: String?, nextAt: String?, nutrition: Nutrition? = nil, updated: Date) {
        self.needCount = needCount; self.runningCount = runningCount
        self.nextTitle = nextTitle; self.nextAt = nextAt; self.nutrition = nutrition; self.updated = updated
    }

    /// As the dictionary the phone sends and the Watch keeps.
    public var dictionary: [String: Any] {
        var out: [String: Any] = ["need": needCount, "running": runningCount, "updated": updated.timeIntervalSince1970]
        if let nextTitle { out["nextTitle"] = nextTitle }
        if let nextAt { out["nextAt"] = nextAt }
        if let nutrition { out["nutrition"] = nutrition.dictionary }
        return out
    }

    public init?(dictionary: [String: Any]) {
        guard let updated = dictionary["updated"] as? Double else { return nil }
        needCount = dictionary["need"] as? Int ?? 0
        runningCount = dictionary["running"] as? Int ?? 0
        nextTitle = dictionary["nextTitle"] as? String
        nextAt = dictionary["nextAt"] as? String
        nutrition = (dictionary["nutrition"] as? [String: Any]).flatMap(Nutrition.init(dictionary:))
        self.updated = Date(timeIntervalSince1970: updated)
    }

    /// Today's calories if fresh and for today; nil means "Open Jarvis to update".
    public func calories(now: Date = Date()) -> Nutrition? {
        guard !isStale(now: now), let nutrition, nutrition.isToday(now: now) else { return nil }
        return nutrition
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
