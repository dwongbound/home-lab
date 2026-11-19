// Jarvis's playbooks in the app (Dylan, 2026-11-19): a first, read-mostly
// screen. Each playbook shows its name, when it runs in plain words, an on
// or off switch, how its last run went (with "Not done: …" for checks that
// didn't hold) and Run now. No editor here; editing is on the home page.
// The wording follows the page's src/lib/playbooks.ts (triggerLine,
// clockLabel, daysLabel, failedChecks); keep them in step.
//
// GET /api/jarvis/playbooks answers {book: {playbooks, options}} in the
// page's shape (camelCase). Switching one on or off saves the whole
// playbook back ({op: "save", playbook}), so each one keeps the JSON it
// came in and sends that back with only `enabled` changed.
import Foundation

/// When a playbook runs.
public struct PlaybookTrigger: Equatable, Sendable {
    public let type: String
    /// "08:30" for a timed one.
    public let at: String?
    /// "mon"… for a timed one; empty means every day.
    public let days: [String]
    /// For "arrive": minutes away before it counts.
    public let minAway: Int

    public init(type: String, at: String? = nil, days: [String] = [], minAway: Int = 0) {
        self.type = type; self.at = at; self.days = days; self.minAway = minAway
    }
}

/// One item of the done checklist, as the last run left it.
public struct PlaybookCheck: Equatable, Sendable {
    public let item: String
    public let ok: Bool
    public let why: String
}

/// How the last run went.
public struct PlaybookRun: Equatable, Sendable {
    public let at: String
    public let ok: Bool
    public let detail: String
    public let checks: [PlaybookCheck]
}

/// One playbook as the screen shows it, plus the JSON it came in.
public struct Playbook: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public var enabled: Bool
    public let purpose: String
    public let trigger: PlaybookTrigger
    public let madeBy: String
    public let lastRun: PlaybookRun?
    /// The playbook exactly as it came, sent back on save.
    let raw: Data

    /// Reads one from the page's JSON; nil without an id and a name.
    public init?(json object: [String: Any]) {
        guard let id = object["id"] as? String, !id.isEmpty, let name = object["name"] as? String else { return nil }
        self.id = id
        self.name = name
        enabled = object["enabled"] as? Bool ?? true
        purpose = object["purpose"] as? String ?? ""
        madeBy = object["madeBy"] as? String ?? "dylan"
        let t = object["trigger"] as? [String: Any] ?? [:]
        trigger = PlaybookTrigger(
            type: t["type"] as? String ?? "manual",
            at: t["at"] as? String,
            days: t["days"] as? [String] ?? [],
            minAway: (t["minAway"] as? NSNumber)?.intValue ?? 0
        )
        if let last = object["lastRun"] as? [String: Any], let at = last["at"] as? String {
            lastRun = PlaybookRun(at: at, ok: last["ok"] as? Bool ?? true, detail: last["detail"] as? String ?? "", checks: Playbooks.checks(last["checks"]))
        } else {
            lastRun = nil
        }
        raw = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }

    /// The playbook to save with this on or off: what came in, with only
    /// `enabled` changed and what Jarvis keeps (last run, author) left out.
    public func draft(enabled: Bool) -> [String: Any] {
        var object = ((try? JSONSerialization.jsonObject(with: raw)) as? [String: Any]) ?? [:]
        object["enabled"] = enabled
        object.removeValue(forKey: "lastRun")
        object.removeValue(forKey: "madeBy")
        return object
    }

    public static func == (a: Playbook, b: Playbook) -> Bool {
        a.id == b.id && a.name == b.name && a.enabled == b.enabled && a.purpose == b.purpose
            && a.trigger == b.trigger && a.madeBy == b.madeBy && a.lastRun == b.lastRun
    }
}

/// What a save or a run answered.
public struct PlaybookResult: Equatable, Sendable {
    public let ok: Bool
    public let detail: String
    public let checks: [PlaybookCheck]

    /// Reads {ok, detail | message, checks}.
    public init(json object: [String: Any]) {
        ok = object["ok"] as? Bool ?? false
        detail = (object["detail"] as? String) ?? (object["message"] as? String) ?? ""
        checks = Playbooks.checks(object["checks"])
    }

    public init(ok: Bool, detail: String, checks: [PlaybookCheck] = []) {
        self.ok = ok; self.detail = detail; self.checks = checks
    }
}

public enum Playbooks {
    /// The playbooks inside GET /api/jarvis/playbooks's {book: {playbooks}};
    /// nil when the book is missing (an older Jarvis, or he's down).
    public static func list(from data: Data) -> [Playbook]? {
        guard let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let book = body["book"] as? [String: Any] else { return nil }
        return (book["playbooks"] as? [[String: Any]] ?? []).compactMap(Playbook.init(json:))
    }

    /// The well-formed items of a checklist.
    static func checks(_ value: Any?) -> [PlaybookCheck] {
        (value as? [[String: Any]] ?? []).compactMap { raw in
            guard let item = raw["item"] as? String, !item.isEmpty else { return nil }
            return PlaybookCheck(item: item, ok: raw["ok"] as? Bool ?? true, why: raw["why"] as? String ?? "")
        }
    }

    /// "08:30" as "8:30 AM" (clockLabel).
    public static func clockLabel(_ at: String) -> String {
        let bits = at.split(separator: ":").compactMap { Int($0) }
        guard bits.count == 2 else { return at }
        let hour = bits[0] % 12 == 0 ? 12 : bits[0] % 12
        return String(format: "%d:%02d %@", hour, bits[1], bits[0] < 12 ? "AM" : "PM")
    }

    /// Which days, in words: "every day", "weekdays", "weekends", "Mon, Wed" (daysLabel).
    public static func daysLabel(_ days: [String]) -> String {
        let order = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
        let set = Set(days)
        if set.isEmpty || set.count == 7 { return "every day" }
        if set == Set(order.prefix(5)) { return "weekdays" }
        if set == ["sat", "sun"] { return "weekends" }
        return order.filter(set.contains).map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: ", ")
    }

    /// When a playbook runs, as one line (triggerLine).
    public static func triggerLine(_ trigger: PlaybookTrigger) -> String {
        switch trigger.type {
        case "time": return "At \(clockLabel(trigger.at ?? "")), \(daysLabel(trigger.days))"
        case "arrive": return trigger.minAway > 0 ? "When I get home after \(trigger.minAway) min away" : "When I get home"
        case "leave": return "When I leave home"
        case "asleep": return "When I go to sleep"
        case "awake": return "When I wake up"
        default: return "When I ask, or the job comes up"
        }
    }

    /// The done items that didn't hold, as "Not done: item: why" lines (failedChecks).
    public static func notDone(_ checks: [PlaybookCheck]) -> [String] {
        checks.filter { !$0.ok }.map { "Not done: " + ($0.why.isEmpty ? $0.item : "\($0.item): \($0.why)") }
    }

}

/// Jarvis's raw failure text in words Dylan can act on (Dylan, 2026-11-19:
/// "not able to run arrive home"). The raw text stays under Details.
public enum PlaybookTrouble {
    /// A run's detail, in plain words when it's one we recognise; nil otherwise.
    public static func runWords(_ detail: String) -> String? {
        if detail.contains("_launchApp failed") { return "The TV refused to open the app. Open it once on the TV, then try again." }
        if detail.contains("_hidC failed") { return "The TV didn't answer. It may have been asleep; try again." }
        return nil
    }

    /// A refused save, in plain words: the "needs at least one step" Jarvis
    /// bug reads as try-again when the playbook does have steps.
    public static func saveWords(_ message: String, hasSteps: Bool) -> String {
        if hasSteps, message.lowercased().contains("needs at least one step") {
            return "Jarvis couldn't save this just now. Try again in a minute."
        }
        return message.isEmpty ? "Jarvis didn't save it." : message
    }
}
