// What the app says about approvals and models, ported word for word from
// the web page (src/lib/approvals.ts, src/lib/model.ts) so both read alike.
import Foundation

public enum ApprovalWording {
    private static let toolLabels: [String: String] = [
        "run_command": "Run a command",
        "run_windows": "Run a Windows command",
        "write_file": "Write a file",
        "edit_file": "Edit a file",
        "change_code": "Change Jarvis’s code",
        "apply_code_change": "Put the new code live",
        "change_setting": "Change a setting",
    ]

    /// The words for an approval's tool: "run_command" → "Run a command";
    /// anything else → "Needs your OK".
    public static func toolLabel(_ tool: String) -> String {
        toolLabels[tool] ?? "Needs your OK"
    }

    // Ids, email addresses and key=value pairs mean the summary is a raw
    // tool call, not words (Dylan, 2026-11-13: "take out anything not human
    // readable").
    private static let machineBits = try! NSRegularExpression(pattern: #"\w=\S|\S@\S+\.\w|[A-Za-z0-9_-]{20,}"#)

    /// True when the text has an id, an address or a key=value pair in it.
    private static func hasMachineBits(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        return machineBits.firstMatch(in: text, range: range) != nil
    }

    /// The summary as Dylan should read it. A raw call like
    /// "Google Calendar delete_event (eventId=…)" keeps only the service and
    /// the action: "Google Calendar: delete event".
    public static func readableSummary(_ summary: String) -> String {
        if !hasMachineBits(summary) { return summary }
        // The raw call is "<service words> <tool_name> <arguments…>": keep the
        // words up to the tool name, nothing after (the arguments hold the ids).
        let beforeParen = summary.components(separatedBy: "(").first ?? summary
        let words = beforeParen.trimmingCharacters(in: .whitespaces).split(separator: " ").map(String.init)
        guard let toolAt = words.firstIndex(where: { $0.contains("_") }) else {
            return "Jarvis wants to make a change. Ask him what it is before saying yes."
        }
        let service = words[..<toolAt].filter { !hasMachineBits($0) }.joined(separator: " ")
        let letters = words[toolAt].filter { $0.isLetter || $0 == "_" }
        let action = letters.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces)
        if service.isEmpty { return action }
        return "\(service): \(action)"
    }

    /// What a settled approval says: the answer, and who gave it if not here.
    public static func outcomeText(ok: Bool, later: Bool, by: String) -> String {
        if later { return "Holding this for later. Say “go ahead” when you’re ready." }
        if by == "timeout" { return "No answer in time, so he left it alone" }
        let verb = ok ? "Approved" : "Denied"
        if by == "voice" { return "\(verb) out loud" }
        return verb
    }

    /// A settled approval as one line in the conversation (Dylan,
    /// 2026-11-17: it goes up into the history, not pinned): "Approved:
    /// Write a file", "Denied out loud: …", "Timed out: …", "Holding for
    /// later: …". The summary is the readable one.
    public static func settledLine(ok: Bool, later: Bool, by: String, summary: String) -> String {
        let what = readableSummary(summary)
        if later { return "Holding for later: \(what)" }
        if by == "timeout" { return "Timed out: \(what)" }
        let verb = ok ? "Approved" : "Denied"
        if by == "voice" { return "\(verb) out loud: \(what)" }
        return "\(verb): \(what)"
    }

    /// True once an approval's `expires` time has passed. An unreadable or
    /// missing time never expires here (the PC's own timeout still settles it).
    public static func hasExpired(_ expires: String, now: Date = Date()) -> Bool {
        guard let date = ISODate.parse(expires) else { return false }
        return now >= date
    }
}

public enum ModelWording {
    /// The letter for each Claude model, matched anywhere in the name Jarvis
    /// sends ("claude-opus-5-5", "opus").
    private static let claudeLetters: [(word: String, letter: String)] = [
        ("opus", "O"), ("haiku", "H"), ("sonnet", "S"), ("fable", "F"),
    ]

    /// The name trimmed and lowercased, as every check below reads it.
    private static func clean(_ model: String) -> String {
        model.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// The chip over a reply. Claude models get two letters: "Jarvis (CO)"
    /// Opus, "Jarvis (CH)" Haiku, "Jarvis (CS)" Sonnet, "Jarvis (CF)" Fable;
    /// a bare "claude" stays "Jarvis (C)". Anything else gets its initial,
    /// "Jarvis (O)" for Ornith; empty when unknown.
    public static func label(_ model: String) -> String {
        let name = clean(model)
        guard let first = name.first else { return "" }
        if isNotice(name) { return noticeLabel(name) }
        if isClaude(name) {
            if let found = claudeLetters.first(where: { name.contains($0.word) }) {
                return "Jarvis (C\(found.letter))"
            }
            return "Jarvis (C)"
        }
        return "Jarvis (\(first.uppercased()))"
    }

    /// True for a message Jarvis sent unasked (a reminder, a Lookout ping,
    /// the start of day): its model is "notice:" + where it came from
    /// (the app is his only channel, 2026-11-18). It gets a plain word chip.
    public static func isNotice(_ model: String) -> Bool {
        clean(model).hasPrefix("notice:")
    }

    /// "Reminder", "Lookout", "Alert", "Finished", "Digest"; anything else
    /// he sends unasked is just "Jarvis".
    public static func noticeLabel(_ model: String) -> String {
        let word = noticeWord(model)
        return word.isEmpty ? "Jarvis" : word
    }

    /// Where an unasked message came from, as a word ("Lookout"); "" for a
    /// source with no word (the page's noticeWord).
    public static func noticeWord(_ model: String) -> String {
        let source = String(clean(model).dropFirst("notice:".count))
        return ["reminder": "Reminder", "lookout": "Lookout", "alert": "Alert", "job": "Finished", "digest": "Digest"][source] ?? ""
    }

    /// What a chip shows: who wrote it, its colour, and for an unasked
    /// message where it came from (the page's Chip).
    public struct Chip: Equatable, Sendable {
        public enum Tone: Equatable, Sendable { case claude, local, notice }
        public let label: String
        public let tone: Tone
        /// "Lookout", "Reminder"…, in quiet grey after the label; "" for a reply.
        public let source: String
    }

    /// The chip for a running or finished job (Dylan, 2026-11-19: "be sure
    /// when indicating parallel jobs what's doing it"): the model's chip, or
    /// nil for a plain code job with no model.
    public static func jobChip(_ model: String?) -> Chip? {
        guard let model = model?.trimmingCharacters(in: .whitespaces), !model.isEmpty else { return nil }
        let chip = chip(model: model)
        return chip.label.isEmpty ? nil : chip
    }

    /// The chip for one turn (the page's chipFor). A reply: its model's
    /// label and colour. An unasked message: the writer's label and colour
    /// ("Jarvis" in the plain notice tone when no model wrote it) plus the
    /// source word: "Jarvis (CO) Lookout", "Jarvis Reminder". Never the
    /// source word alone (Dylan, 2026-11-18: "this should also say jarvis or
    /// ornith").
    public static func chip(model: String, writer: String? = nil) -> Chip {
        guard isNotice(model) else {
            return Chip(label: label(model), tone: isClaude(model) ? .claude : .local, source: "")
        }
        let source = noticeWord(model)
        let writer = writer?.trimmingCharacters(in: .whitespaces) ?? ""
        if writer.isEmpty || isNotice(writer) { return Chip(label: "Jarvis", tone: .notice, source: source) }
        return Chip(label: label(writer), tone: isClaude(writer) ? .claude : .local, source: source)
    }

    /// Claude's chip (any of its models) is orange; every local model's is blue.
    public static func isClaude(_ model: String) -> Bool {
        let name = clean(model)
        if name.hasPrefix("claude") { return true }
        return claudeLetters.contains { $0.word == name }
    }
}
