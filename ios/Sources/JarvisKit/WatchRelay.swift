// The Watch's line to Jarvis. Tailscale doesn't run on Apple Watch, so the
// Watch can't reach the PC itself: it hands each ask to the iPhone app
// over WatchConnectivity, and the phone (on Tailscale) asks Jarvis and
// sends the answer back. These are the messages both sides speak, as the
// plain dictionaries WatchConnectivity carries.
import Foundation

/// What the Watch asks the phone for.
public enum WatchRequest: Equatable, Sendable {
    /// Ask Jarvis something (dictated on the Watch); the answer comes back whole.
    case ask(String)
    /// Which approvals are waiting.
    case approvals
    /// Approve or deny one.
    case answer(id: String, ok: Bool)
    /// The board: notices, running tasks, what's next.
    case board
    /// Clear notices everywhere (empty = all).
    case clear([String])

    /// As a WatchConnectivity message.
    public var message: [String: Any] {
        switch self {
        case .ask(let text): return ["op": "ask", "text": text]
        case .approvals: return ["op": "approvals"]
        case .answer(let id, let ok): return ["op": "answer", "id": id, "ok": ok]
        case .board: return ["op": "board"]
        case .clear(let ids): return ["op": "clear", "ids": ids]
        }
    }

    /// Reads a message from the Watch; nil when it isn't one of these.
    public init?(message: [String: Any]) {
        switch message["op"] as? String {
        case "ask":
            guard let text = message["text"] as? String, !text.isEmpty else { return nil }
            self = .ask(text)
        case "approvals":
            self = .approvals
        case "answer":
            guard let id = message["id"] as? String, let ok = message["ok"] as? Bool else { return nil }
            self = .answer(id: id, ok: ok)
        case "board":
            self = .board
        case "clear":
            self = .clear(message["ids"] as? [String] ?? [])
        default:
            return nil
        }
    }
}

/// What the phone sends back.
public enum WatchReply: Equatable, Sendable {
    /// Jarvis's whole answer, and who wrote it ("claude", "ornith").
    case answer(text: String, model: String?)
    case approvals([Approval])
    case board(WatchBoard)
    case done
    /// Something went wrong, worded for the Watch's small screen.
    case problem(String)

    /// As a WatchConnectivity reply.
    public var message: [String: Any] {
        switch self {
        case .answer(let text, let model):
            var out: [String: Any] = ["kind": "answer", "text": text]
            if let model { out["model"] = model }
            return out
        case .approvals(let list):
            let rows: [[String: String]] = list.map { ["id": $0.id, "tool": $0.tool, "summary": $0.summary, "expires": $0.expires] }
            return ["kind": "approvals", "list": rows]
        case .board(let board):
            return ["kind": "board", "board": board.message]
        case .done:
            return ["kind": "done"]
        case .problem(let words):
            return ["kind": "problem", "text": words]
        }
    }

    /// Reads the phone's reply; anything unreadable becomes a problem.
    public init(message: [String: Any]) {
        switch message["kind"] as? String {
        case "answer":
            self = .answer(text: message["text"] as? String ?? "", model: message["model"] as? String)
        case "approvals":
            let rows = message["list"] as? [[String: String]] ?? []
            self = .approvals(rows.compactMap { row in
                guard let id = row["id"], let summary = row["summary"] else { return nil }
                return Approval(id: id, tool: row["tool"] ?? "", summary: summary, expires: row["expires"] ?? "")
            })
        case "board":
            self = .board(WatchBoard(message: message["board"] as? [String: Any] ?? [:]))
        case "done":
            self = .done
        case "problem":
            self = .problem(message["text"] as? String ?? "Something went wrong")
        default:
            self = .problem("The phone sent something this Watch doesn’t understand")
        }
    }
}

extension JarvisClient {
    /// Asks Jarvis and waits for the whole answer (the Watch shows it in one
    /// go). Returns the text and who wrote it.
    public func ask(_ text: String) async throws -> (text: String, model: String?) {
        var reply = ""
        var model: String?
        for try await event in chat(text) {
            switch event {
            case .delta(let words): reply += words
            case .model(let name): model = name
            case .error(let message): throw JarvisError.server(status: 0, message: message)
            default: break
            }
        }
        return (reply, model)
    }

    /// Runs one Watch request against the PC and words the result for the Watch.
    public func handle(_ request: WatchRequest, settledDefaults: UserDefaults = .standard) async -> WatchReply {
        let settled = SettledApprovals.load(from: settledDefaults)
        do {
            switch request {
            case .ask(let text):
                let answer = try await ask(text)
                return .answer(text: answer.text, model: answer.model)
            case .approvals:
                // The phone's settled record: an approval that's over never
                // goes back to the Watch, even while the PC still lists it.
                return .approvals(settled.waiting(try await pendingApprovals()))
            case .answer(let id, let ok):
                switch try await answer(approval: id, ok: ok) {
                case .taken:
                    return .done
                case .gone(_, let answer):
                    // Already over: the card goes, nothing to retry.
                    var record = SettledApprovals.load(from: settledDefaults)
                    record.settle(id, line: ApprovalReply.goneLine(answer: answer, summary: ""))
                    record.save(to: settledDefaults)
                    return .done
                case .failed(let words):
                    return .problem(words)
                }
            case .board:
                return .board(WatchBoard(snapshot: try await snapshot(), settled: settled))
            case .clear(let ids):
                if ids.isEmpty { try await clearAllNotices() } else { try await clearNotices(ids: ids) }
                return .done
            }
        } catch {
            return .problem(error.localizedDescription)
        }
    }
}
