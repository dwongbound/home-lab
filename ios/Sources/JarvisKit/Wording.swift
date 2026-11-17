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
        if by == "telegram" { return "\(verb) on Telegram" }
        if by == "voice" { return "\(verb) out loud" }
        return verb
    }
}

public enum ModelWording {
    /// The chip over a reply: "Jarvis (C)" for Claude, "Jarvis (O)" for
    /// Ornith, the model's initial for any other; empty when unknown.
    public static func label(_ model: String) -> String {
        let name = model.trimmingCharacters(in: .whitespaces)
        guard let first = name.first else { return "" }
        return "Jarvis (\(first.uppercased()))"
    }

    /// Claude's chip is orange; every local model's is blue.
    public static func isClaude(_ model: String) -> Bool {
        model.trimmingCharacters(in: .whitespaces).lowercased() == "claude"
    }
}
