// The chat stream from POST /api/jarvis/chat: one JSON object per line
// (NDJSON). Same events the web page reads (src/types.ts ChatEvent).
import Foundation

/// Jarvis asking before he does something on the PC. He waits until
/// `expires` for Approve or Deny from the app, a spoken answer, or the page.
public struct Approval: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let tool: String
    public let summary: String
    public let expires: String

    /// Builds an approval (tests and previews; the stream decodes its own).
    public init(id: String, tool: String, summary: String, expires: String) {
        self.id = id
        self.tool = tool
        self.summary = summary
        self.expires = expires
    }
}

/// One piece of a streamed reply.
public enum ChatEvent: Equatable, Sendable {
    /// More words of the reply.
    case delta(String)
    /// The reply is finished.
    case done
    /// Something went wrong; the message is for Dylan.
    case error(String)
    /// Jarvis wants an OK before he carries on.
    case approval(Approval)
    /// An approval was settled. `by` is who answered (page, voice, telegram,
    /// timeout); `later` means he said "wait", so it's held, not denied.
    case approvalDone(id: String, ok: Bool, by: String, later: Bool)
    /// A slow lookup started ("Searching the web.").
    case working(String)
    /// The slow lookup is over.
    case workingDone
    /// Which brain is answering: "claude", or a local model like "ornith".
    case model(String)
    /// A meal photo that looks like one already logged: Dylan picks same,
    /// leftovers or new (the buttons under the reply).
    case mealQuestion(key: String, choices: [String])

    /// Reads one line of the stream. Blank lines, bad JSON and event types
    /// this build doesn't know yet come back nil, so a newer Jarvis never
    /// breaks an older app.
    public static func parse(line: String) -> ChatEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        guard let type = object["type"] as? String else { return nil }

        switch type {
        case "delta":
            guard let text = object["text"] as? String else { return nil }
            return .delta(text)
        case "done":
            return .done
        case "error":
            return .error(object["message"] as? String ?? "Something went wrong")
        case "approval":
            guard let raw = object["approval"] as? [String: Any] else { return nil }
            return approval(from: raw)
        case "approval_done":
            guard let id = object["id"] as? String else { return nil }
            let ok = object["ok"] as? Bool ?? false
            let by = object["by"] as? String ?? "page"
            let later = object["later"] as? Bool ?? false
            return .approvalDone(id: id, ok: ok, by: by, later: later)
        case "working":
            return .working(object["label"] as? String ?? "")
        case "working_done":
            return .workingDone
        case "model":
            guard let model = object["model"] as? String else { return nil }
            return .model(model)
        case "meal_question":
            guard let key = object["key"] as? String, !key.isEmpty else { return nil }
            let choices = (object["choices"] as? [String] ?? MealChoice.all).filter { MealChoice.all.contains($0) }
            return .mealQuestion(key: key, choices: choices.isEmpty ? MealChoice.all : choices)
        default:
            return nil
        }
    }

    /// The approval inside an "approval" event, if every field is there.
    private static func approval(from raw: [String: Any]) -> ChatEvent? {
        guard
            let id = raw["id"] as? String,
            let tool = raw["tool"] as? String,
            let summary = raw["summary"] as? String
        else { return nil }
        let expires = raw["expires"] as? String ?? ""
        return .approval(Approval(id: id, tool: tool, summary: summary, expires: expires))
    }
}

/// One saved line of the web chat (GET /api/jarvis/history), oldest first.
public struct ChatTurn: Codable, Equatable, Sendable {
    public let role: String
    public let text: String
    public let at: String
    /// Who wrote one of Jarvis's lines, when known.
    public let model: String?
    /// How many photos one of Dylan's lines carried (the photos themselves
    /// aren't kept in history).
    public let images: Int?
    /// Jarvis's id for the turn, so a notice can point at it.
    public let id: Int?

    /// True for Dylan's own lines.
    public var isUser: Bool { role == "user" }

    /// Builds a turn (sample data and tests; the server's are decoded).
    public init(role: String, text: String, at: String, model: String?, images: Int? = nil, id: Int? = nil) {
        self.role = role; self.text = text; self.at = at; self.model = model; self.images = images; self.id = id
    }

    /// The position of the turn with Jarvis's id `turnId`, or nil.
    public static func index(of turnId: Int, in turns: [ChatTurn]) -> Int? {
        turns.firstIndex { $0.id == turnId }
    }
}

