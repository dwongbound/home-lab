// Chat history in pages, and catching up after the app was away (Dylan,
// 2026-11-19: "the chat shouldnt load all history- it should lazy load as
// you scroll up" and "if i type something in the chat and close the app it
// should respond … and still keep going").
//
// GET /api/jarvis/history?limit=N[&before=TURN|&around=TURN] answers
// {turns (oldest first), hasMore, hasNewer, pending}. Today's server takes
// no parameters and sends turns only: hasMore then reads false (no older
// pages are asked for) and pending reads nil (unknown).
import Foundation

/// Which page of history to ask for.
public enum HistoryQuery: Equatable, Sendable {
    /// The newest `limit` turns.
    case newest(limit: Int)
    /// The `limit` turns just older than `before`.
    case before(Int, limit: Int)
    /// A window centred on one turn (a notice or push opening it).
    case around(Int, limit: Int)

    public static let pageSize = 50

    /// The query string; an empty one is today's whole answer.
    public var parameters: [String: String] {
        switch self {
        case .newest(let limit): return ["limit": String(Self.clamp(limit))]
        case .before(let id, let limit): return ["limit": String(Self.clamp(limit)), "before": String(id)]
        case .around(let id, let limit): return ["limit": String(Self.clamp(limit)), "around": String(id)]
        }
    }

    static func clamp(_ limit: Int) -> Int { min(100, max(1, limit)) }
}

/// One page of history.
public struct HistoryPage: Decodable, Equatable, Sendable {
    public let turns: [ChatTurn]
    /// Older turns exist on the server. Missing (today's server) = false.
    public let hasMore: Bool
    /// Newer turns exist past an `around` window.
    public let hasNewer: Bool
    /// Jarvis is still writing the reply to the newest turn; nil when the
    /// server doesn't say.
    public let pending: Bool?

    public init(turns: [ChatTurn], hasMore: Bool = false, hasNewer: Bool = false, pending: Bool? = nil) {
        self.turns = turns; self.hasMore = hasMore; self.hasNewer = hasNewer; self.pending = pending
    }

    enum CodingKeys: String, CodingKey { case turns, hasMore, hasNewer, pending }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // One turn that won't decode is skipped; the rest still show.
        turns = ((try? c.decodeIfPresent([Lenient].self, forKey: .turns)) ?? [])?.compactMap(\.turn) ?? []
        hasMore = ((try? c.decodeIfPresent(Bool.self, forKey: .hasMore)) ?? nil) ?? false
        hasNewer = ((try? c.decodeIfPresent(Bool.self, forKey: .hasNewer)) ?? nil) ?? false
        pending = (try? c.decodeIfPresent(Bool.self, forKey: .pending)) ?? nil
    }
}

/// One turn that may or may not decode.
private struct Lenient: Decodable {
    let turn: ChatTurn?
    init(from decoder: Decoder) throws { turn = try? ChatTurn(from: decoder) }
}

/// Loading older pages at the top of Chat (Dylan, 2026-11-20: "stuck
/// loading earlier messages"). The spinner shows only while a request is
/// really out; a page that brings nothing new (empty, or turns already
/// held) ends paging even if the server says there's more, so it can't
/// loop; a failure stops and offers Retry.
public struct OlderPaging: Equatable, Sendable {
    public enum State: Equatable, Sendable { case idle, loading, failed, done }
    public private(set) var state: State

    public init(hasMore: Bool) { state = hasMore ? .idle : .done }

    /// Start a load; false when one is out, it failed (wait for Retry), or
    /// there's nothing older.
    public mutating func begin() -> Bool {
        guard state == .idle else { return false }
        state = .loading
        return true
    }

    /// A page came back with `added` turns not already held.
    public mutating func finish(added: Int, hasMore: Bool) {
        state = (hasMore && added > 0) ? .idle : .done
    }

    public mutating func fail() { state = .failed }

    /// Retry after a failure.
    public mutating func retry() { if state == .failed { state = .idle } }

    /// The newest page loaded again: older pages may exist again.
    public mutating func reset(hasMore: Bool) { if state != .loading { state = hasMore ? .idle : .done } }
}

public enum ChatHistory {
    /// An older page put in front of what's held, oldest first, with no
    /// turn twice (pages can overlap when new turns arrived in between).
    public static func prepend(_ older: [ChatTurn], to held: [ChatTurn]) -> [ChatTurn] {
        let known = Set(held.compactMap(\.id))
        return older.filter { $0.id.map { !known.contains($0) } ?? true } + held
    }

    /// Whether, back in the app, a reply is still owed: his last line has
    /// no answer after it yet, or the server says Jarvis is still writing.
    public static func replyOwed(_ turns: [ChatTurn], pending: Bool?) -> Bool {
        if pending == true { return true }
        guard let last = turns.last else { return false }
        return last.isUser && pending != false
    }

    /// How long to keep checking for a reply owed after coming back, when
    /// the server can't say whether Jarvis is still writing.
    public static let catchUpSeconds: TimeInterval = 90
    /// How often to look again meanwhile.
    public static let catchUpEvery: TimeInterval = 2
}
