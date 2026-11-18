// Approvals that are over, so their cards stay gone (Dylan, 2026-11-18: he
// answered one out loud, the card stayed up, and every Deny tap came back
// "timed out" and put the card back). Once an approval is settled, by an
// `approval_done` on the chat stream or the Talk line, by Jarvis saying it's
// already answered, or by its own time running out, its id goes in here, and
// no card, notice row, orbit dot or banner is shown for it again, even while
// GET /api/jarvis/approvals or the snapshot's notices still list it for a
// moment. Kept for a day, across relaunches.
import Foundation

/// The settled approvals, by id, with the line each one ended on.
public struct SettledApprovals: Codable, Equatable, Sendable {
    /// One settled approval: its history line and when it settled.
    public struct Entry: Codable, Equatable, Sendable {
        public let line: String
        public let at: Date
    }

    /// How long an id is remembered: a day.
    public static let keepFor: TimeInterval = 24 * 60 * 60
    /// Where each app keeps them.
    public static let defaultsKey = "settledApprovals"

    public private(set) var entries: [String: Entry] = [:]

    public init() {}

    /// True once the approval is over.
    public func isSettled(_ id: String) -> Bool { entries[id] != nil }

    /// The line it ended on ("Denied out loud: …"), if it's settled.
    public func line(for id: String) -> String? { entries[id]?.line }

    /// Marks it over. The first line wins: a later echo of the same answer
    /// (the stream and the Talk line both say it) doesn't rewrite it.
    public mutating func settle(_ id: String, line: String, at now: Date = Date()) {
        guard entries[id] == nil else { return }
        entries[id] = Entry(line: line, at: now)
    }

    /// Takes one back off (only for an answer this app sent that never
    /// reached Jarvis, so the card can be tried again).
    public mutating func unsettle(_ id: String) {
        entries[id] = nil
    }

    /// Forgets ids older than a day.
    public mutating func prune(now: Date = Date()) {
        entries = entries.filter { now.timeIntervalSince($0.value.at) < Self.keepFor }
    }

    /// The approvals still really waiting.
    public func waiting(_ approvals: [Approval]) -> [Approval] {
        approvals.filter { !isSettled($0.id) }
    }

    /// The notices less any approval row that's already over.
    public func showing(_ notices: [Notice]) -> [Notice] {
        notices.filter { notice in
            guard let id = notice.approvalId else { return true }
            return !isSettled(id)
        }
    }

    // MARK: Keeping them

    /// Reads the saved ones, already pruned.
    public static func load(from defaults: UserDefaults = .standard, now: Date = Date()) -> SettledApprovals {
        guard let data = defaults.data(forKey: defaultsKey),
              var saved = try? JSONDecoder().decode(SettledApprovals.self, from: data) else { return SettledApprovals() }
        saved.prune(now: now)
        return saved
    }

    /// Saves them.
    public func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.defaultsKey) }
    }
}

/// What POST /api/jarvis/approve said back.
public enum ApprovalReply: Equatable, Sendable {
    /// How Jarvis says a finished approval was answered.
    public struct Answer: Equatable, Sendable {
        public let ok: Bool
        /// page, voice, telegram or timeout.
        public let by: String
        /// He said "wait": held, not denied.
        public let later: Bool

        public init(ok: Bool, by: String, later: Bool = false) {
            self.ok = ok; self.by = by; self.later = later
        }
    }

    /// Jarvis took the answer.
    case taken
    /// The approval was already over (answered elsewhere or timed out): the
    /// card goes for good. Not an error to retry. `answer` is there only
    /// while Jarvis still remembers how it ended.
    case gone(message: String?, answer: Answer?)
    /// A real error (409 and the like): the card stays, with the message.
    case failed(String)

    /// Reads the reply. The page answers a finished approval with 410 and
    /// {ok: false, gone: true, message, answer?: {ok, by, later}}. Read
    /// leniently: `gone: true` at any status counts, and so does a bare 410
    /// or 404 (Jarvis's own answer, if it ever comes straight through).
    /// The words come from `message` or `error`, whichever is there.
    public static func read(status: Int, data: Data) -> ApprovalReply {
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let words = (object["message"] as? String) ?? (object["error"] as? String)
        if object["gone"] as? Bool == true || status == 410 || status == 404 {
            var answer: Answer?
            if let raw = object["answer"] as? [String: Any], let by = raw["by"] as? String {
                answer = Answer(ok: raw["ok"] as? Bool ?? false, by: by, later: raw["later"] as? Bool ?? false)
            }
            return .gone(message: words, answer: answer)
        }
        if (200..<300).contains(status) { return .taken }
        return .failed(words ?? "Jarvis answered \(status)")
    }

    /// The history line for a finished approval: as `answer` says it ended
    /// ("Denied out loud: …", "Holding for later: …"), or "Timed out: …"
    /// when Jarvis no longer remembers (the same words as settledLine).
    public static func goneLine(answer: Answer?, summary: String) -> String {
        guard let answer else {
            return ApprovalWording.settledLine(ok: false, later: false, by: "timeout", summary: summary)
        }
        return ApprovalWording.settledLine(ok: answer.ok, later: answer.later, by: answer.by, summary: summary)
    }
}
