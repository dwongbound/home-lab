// Writing a playbook in the app (Dylan, 2026-11-19: "there also isn't
// another button for me to add another routine"). The native twin of the
// page's editor model: src/lib/playbooks.ts (blankPlaybook, blankTrigger,
// blankStep, playbookProblem, stepLine, commandLabel) and the field limits
// in server/sources/playbooks.mjs. Keep them in step.
//
// A draft is read from and written back to the page's JSON shape
// (camelCase); the server marks what the page saves as made by Dylan.
import Foundation

/// What a step can use, from GET /api/jarvis/playbooks's options.
public struct PlaybookOptions: Equatable, Sendable {
    public struct Device: Equatable, Sendable, Identifiable {
        public let entity: String
        public let name: String
        public let kind: String
        public let commands: [String]
        public var id: String { entity }
    }
    public struct Named: Equatable, Sendable, Identifiable {
        public let entity: String
        public let name: String
        public var id: String { entity }
    }
    public struct Screen: Equatable, Sendable, Identifiable {
        public let entity: String
        public let name: String
        public let apps: [String]
        public var id: String { entity }
    }
    public var devices: [Device] = []
    public var scenes: [Named] = []
    public var apps: [Screen] = []
    public var zones: [String] = []

    public init() {}

    /// Reads the options leniently; a row without an entity is skipped.
    public init(json object: [String: Any]) {
        func rows(_ key: String) -> [[String: Any]] {
            (object[key] as? [[String: Any]] ?? []).filter { ($0["entity"] as? String)?.isEmpty == false }
        }
        devices = rows("devices").map { r in
            let entity = r["entity"] as? String ?? ""
            return Device(entity: entity, name: (r["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? entity, kind: r["kind"] as? String ?? "", commands: r["commands"] as? [String] ?? [])
        }
        scenes = rows("scenes").map { r in
            let entity = r["entity"] as? String ?? ""
            return Named(entity: entity, name: (r["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? entity)
        }
        apps = rows("apps").map { r in
            let entity = r["entity"] as? String ?? ""
            return Screen(entity: entity, name: (r["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? entity, apps: r["apps"] as? [String] ?? [])
        }
        zones = object["zones"] as? [String] ?? []
    }

    /// The name a device, scene or screen goes by; its id when unknown.
    public func name(of entity: String) -> String {
        devices.first { $0.entity == entity }?.name
            ?? scenes.first { $0.entity == entity }?.name
            ?? apps.first { $0.entity == entity }?.name
            ?? entity
    }
}

/// When a playbook runs, as the editor holds it.
public struct DraftTrigger: Equatable, Sendable {
    public var type: String
    public var at: String = "08:00"
    public var days: [String] = []
    public var zone: String = "home"
    public var minAway: Int = 15

    public init(type: String, at: String = "08:00", days: [String] = [], zone: String = "home", minAway: Int = 15) {
        self.type = type; self.at = at; self.days = days; self.zone = zone; self.minAway = minAway
    }

    /// What a trigger of `type` starts as when it's picked (blankTrigger).
    public static func blank(_ type: String) -> DraftTrigger {
        DraftTrigger(type: type)
    }

    /// The page's JSON for it.
    public var json: [String: Any] {
        switch type {
        case "time": return ["type": type, "at": at, "days": days]
        case "arrive": return ["type": type, "zone": zone, "minAway": minAway]
        case "leave": return ["type": type, "zone": zone]
        default: return ["type": type]
        }
    }

    /// The same trigger in the read-only shape the list's wording uses.
    public var plain: PlaybookTrigger {
        PlaybookTrigger(type: type, at: at, days: days, minAway: minAway)
    }
}

/// One step, as the editor holds it.
public enum DraftStep: Equatable, Sendable {
    case device(entity: String, command: String, value: String)
    case scene(entity: String)
    case app(entity: String, app: String)
    case notify(text: String)
    case think(text: String, model: String)
    case email(to: String, subject: String, body: String, confirm: Bool)
    case wait(seconds: Int)

    /// The step's type name, as the page has it.
    public var type: String {
        switch self {
        case .device: return "device"
        case .scene: return "scene"
        case .app: return "app"
        case .notify: return "notify"
        case .think: return "think"
        case .email: return "email"
        case .wait: return "wait"
        }
    }

    /// Reads a step from the page's JSON; nil for one the app doesn't know.
    public init?(json r: [String: Any]) {
        switch r["type"] as? String {
        case "device":
            let value: String
            if let n = r["value"] as? NSNumber, !(r["value"] is String) { value = DraftStep.numberText(n.doubleValue) }
            else { value = r["value"] as? String ?? "" }
            self = .device(entity: r["entity"] as? String ?? "", command: r["command"] as? String ?? "turn_off", value: value)
        case "scene": self = .scene(entity: r["entity"] as? String ?? "")
        case "app": self = .app(entity: r["entity"] as? String ?? "", app: r["app"] as? String ?? "")
        case "notify": self = .notify(text: r["text"] as? String ?? "")
        case "think", "ask": self = .think(text: r["text"] as? String ?? "", model: r["model"] as? String ?? "auto")
        case "email": self = .email(to: r["to"] as? String ?? "", subject: r["subject"] as? String ?? "", body: r["body"] as? String ?? "", confirm: r["confirm"] as? Bool ?? false)
        case "wait": self = .wait(seconds: (r["seconds"] as? NSNumber)?.intValue ?? 60)
        default: return nil
        }
    }

    /// "21" for 21.0, "0.4" for 0.4.
    static func numberText(_ d: Double) -> String {
        d == d.rounded() ? String(Int(d)) : String(d)
    }

    /// The page's JSON for it. A device value is a number unless the
    /// command takes words (a mode, an app), and is left out when empty.
    public var json: [String: Any] {
        switch self {
        case .device(let entity, let command, let value):
            var out: [String: Any] = ["type": "device", "entity": entity, "command": command]
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                if PlaybookWording.commandTakesWords(command) { out["value"] = trimmed }
                else if let n = Double(trimmed) { out["value"] = n == n.rounded() ? NSNumber(value: Int(n)) : NSNumber(value: n) }
                else { out["value"] = trimmed }
            }
            return out
        case .scene(let entity): return ["type": "scene", "entity": entity]
        case .app(let entity, let app): return ["type": "app", "entity": entity, "app": app]
        case .notify(let text): return ["type": "notify", "text": text]
        case .think(let text, let model): return ["type": "think", "text": text, "model": model]
        case .email(let to, let subject, let body, let confirm): return ["type": "email", "to": to, "subject": subject, "body": body, "confirm": confirm]
        case .wait(let seconds): return ["type": "wait", "seconds": seconds]
        }
    }

    /// What a step of `type` starts as: the first device, scene or app
    /// Jarvis lists (blankStep).
    public static func blank(_ type: String, options: PlaybookOptions) -> DraftStep {
        switch type {
        case "device":
            let first = options.devices.first
            return .device(entity: first?.entity ?? "", command: first?.commands.first ?? "turn_off", value: "")
        case "scene": return .scene(entity: options.scenes.first?.entity ?? "")
        case "app":
            let first = options.apps.first
            return .app(entity: first?.entity ?? "", app: first?.apps.first ?? "")
        case "notify": return .notify(text: "")
        case "think": return .think(text: "", model: "auto")
        // A playbook you wrote doesn't ask before sending (Dylan, 2026-11-18).
        case "email": return .email(to: "", subject: "", body: "", confirm: false)
        default: return .wait(seconds: 60)
        }
    }

    /// What the step is still missing, or nil when it's complete (stepProblem).
    public var problem: String? {
        switch self {
        case .device(let entity, let command, let value):
            if entity.isEmpty { return "pick a device" }
            if PlaybookWording.commandTakesValue(command) && value.trimmingCharacters(in: .whitespaces).isEmpty { return "give it a value" }
            return nil
        case .scene(let entity): return entity.isEmpty ? "pick a scene" : nil
        case .app(let entity, let app): return entity.isEmpty || app.isEmpty ? "pick a TV and an app" : nil
        case .notify(let text): return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "write what it should say" : nil
        case .think(let text, _): return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "write what Jarvis should do" : nil
        case .email(let to, let subject, let body, _):
            let addresses = PlaybookWording.emailAddresses(to)
            if addresses.isEmpty || addresses.count > 10 { return "give it one to ten email addresses" }
            if !addresses.allSatisfy(PlaybookWording.looksLikeEmail) { return "check the email address" }
            if subject.trimmingCharacters(in: .whitespaces).isEmpty || body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "write a subject and a message" }
            return nil
        case .wait(let seconds): return seconds < 1 || seconds > 600 ? "wait between 1 and 600 seconds" : nil
        }
    }

    /// The step as a short sentence for its folded row in the editor:
    /// "Turn off Desk lamp", "Run the Movie scene", "Wait 2 min". A field
    /// not filled in yet reads as what to do ("Pick a device").
    public func sentence(_ options: PlaybookOptions) -> String {
        func or(_ text: String, _ blank: String) -> String {
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? blank : PlaybookWording.clip(t)
        }
        switch self {
        case .device(let entity, let command, let value):
            guard !entity.isEmpty else { return "Pick a device" }
            let name = options.name(of: entity)
            let verb = PlaybookWording.commandLabel(command)
            if PlaybookWording.commandTakesValue(command) {
                return "\(name): \(verb.lowercased()) \(or(value, "…"))"
            }
            return "\(verb) \(name)"
        case .scene(let entity): return entity.isEmpty ? "Pick a scene" : "Run the \(options.name(of: entity)) scene"
        case .app(let entity, let app):
            if entity.isEmpty { return "Pick a TV" }
            return app.isEmpty ? "Pick an app for \(options.name(of: entity))" : "Open \(app) on \(options.name(of: entity))"
        case .notify(let text): return "Notify me: " + or(text, "write what it says")
        case .think(let text, _): return "Ask Jarvis: " + or(text, "write what to work out")
        case .email(let to, let subject, _, _):
            let who = to.trimmingCharacters(in: .whitespaces)
            return who.isEmpty ? "Email: pick who it goes to" : "Email \(PlaybookWording.clip(who, max: 28)): " + or(subject, "no subject yet")
        case .wait(let seconds): return seconds % 60 == 0 ? "Wait \(seconds / 60) min" : "Wait \(seconds) s"
        }
    }

}

/// A playbook being written: a new one has no id yet.
public struct PlaybookDraft: Equatable, Sendable {
    /// A two-part row: {name, where} for inputs, {if, then} for decisions.
    public struct Pair: Equatable, Sendable {
        public var first: String
        public var second: String
        public init(_ first: String, _ second: String) { self.first = first; self.second = second }
    }

    public var id: String?
    public var name = ""
    public var enabled = true
    public var purpose = ""
    public var whenToUse = ""
    public var trigger = DraftTrigger(type: "manual")
    public var inputs: [Pair] = []
    public var steps: [DraftStep] = []
    public var decisions: [Pair] = []
    public var done: [String] = []
    public var edgeCases: [String] = []
    public var standard = ""
    public var badVersion = ""

    /// The most steps a playbook can have.
    public static let maxSteps = 20

    /// A new, empty playbook: runs only when asked until a trigger is picked (blankPlaybook).
    public init() {}

    /// Reads a saved playbook from the page's JSON.
    public init(json o: [String: Any]) {
        id = (o["id"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        name = o["name"] as? String ?? ""
        enabled = o["enabled"] as? Bool ?? true
        purpose = o["purpose"] as? String ?? ""
        whenToUse = o["whenToUse"] as? String ?? ""
        let t = o["trigger"] as? [String: Any] ?? [:]
        trigger = DraftTrigger(
            type: t["type"] as? String ?? "manual",
            at: t["at"] as? String ?? "08:00",
            days: t["days"] as? [String] ?? [],
            zone: t["zone"] as? String ?? "home",
            minAway: (t["minAway"] as? NSNumber)?.intValue ?? 15
        )
        func pairs(_ key: String, _ a: String, _ b: String) -> [Pair] {
            (o[key] as? [[String: Any]] ?? []).map { Pair($0[a] as? String ?? "", $0[b] as? String ?? "") }
        }
        inputs = pairs("inputs", "name", "where")
        decisions = pairs("decisions", "if", "then")
        steps = (o["steps"] as? [[String: Any]] ?? []).compactMap(DraftStep.init(json:))
        done = o["done"] as? [String] ?? []
        edgeCases = o["edgeCases"] as? [String] ?? []
        standard = o["standard"] as? String ?? ""
        badVersion = o["badVersion"] as? String ?? ""
    }

    /// The page's JSON to save: everything the editor holds, blank rows
    /// left out (the server drops them too).
    public var json: [String: Any] {
        func clean(_ list: [String]) -> [String] {
            list.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        func pairs(_ list: [Pair], _ a: String, _ b: String) -> [[String: Any]] {
            list.map { ($0.first.trimmingCharacters(in: .whitespaces), $0.second.trimmingCharacters(in: .whitespaces)) }
                .filter { !$0.0.isEmpty && !$0.1.isEmpty }
                .map { [a: $0.0, b: $0.1] }
        }
        var out: [String: Any] = [
            "name": name.trimmingCharacters(in: .whitespaces),
            "enabled": enabled,
            "purpose": purpose,
            "whenToUse": whenToUse,
            "trigger": trigger.json,
            "inputs": pairs(inputs, "name", "where"),
            "steps": steps.map(\.json),
            "decisions": pairs(decisions, "if", "then"),
            "done": clean(done),
            "edgeCases": clean(edgeCases),
            "standard": standard,
            "badVersion": badVersion,
        ]
        if let id { out["id"] = id }
        return out
    }

    /// Why it can't be saved yet, in plain words; nil when it can (playbookProblem).
    public var problem: String? {
        if name.trimmingCharacters(in: .whitespaces).isEmpty { return "Give the playbook a name" }
        if trigger.type == "time", !PlaybookWording.isClock(trigger.at) { return "Pick a time" }
        if steps.isEmpty { return "Add at least one step" }
        if steps.count > Self.maxSteps { return "A playbook can have up to \(Self.maxSteps) steps" }
        for (i, step) in steps.enumerated() {
            if let problem = step.problem { return "Step \(i + 1): \(problem)" }
        }
        return nil
    }
}

/// The editor's choices and words (the page's DAYS, TRIGGER_CHOICES,
/// STEP_CHOICES, THINKER_CHOICES, commandLabel and friends).
public enum PlaybookWording {
    public static let days: [(id: String, label: String)] = [
        ("mon", "Mon"), ("tue", "Tue"), ("wed", "Wed"), ("thu", "Thu"), ("fri", "Fri"), ("sat", "Sat"), ("sun", "Sun"),
    ]
    public static let steps: [(type: String, label: String)] = [
        ("device", "Control a device"), ("scene", "Run a scene"), ("app", "Open an app on a TV"),
        ("notify", "Send me a notification"), ("think", "Have Jarvis work something out"),
        ("email", "Send an email"), ("wait", "Wait"),
    ]
    /// The "Add a step" row's buttons (the page's STEP_CHOICES `short`), with an icon each.
    public static let stepButtons: [(type: String, short: String, icon: String)] = [
        ("device", "Device", "lightbulb"), ("scene", "Scene", "sparkles"), ("app", "TV app", "tv"),
        ("notify", "Notify me", "bell"), ("think", "Ask Jarvis", "brain"), ("email", "Email", "envelope"),
        ("wait", "Wait", "hourglass"),
    ]
    /// The icon for a step's kind.
    public static func stepIcon(_ type: String) -> String {
        stepButtons.first { $0.type == type }?.icon ?? "circle"
    }
    /// The trigger choices as short tiles, with an icon each.
    public static let triggerTiles: [(type: String, short: String, icon: String)] = [
        ("time", "At a time", "clock"), ("arrive", "I get home", "house"), ("leave", "I leave home", "figure.walk"),
        ("asleep", "I go to sleep", "moon.zzz"), ("awake", "I wake up", "sun.max"), ("manual", "When I ask", "hand.tap"),
    ]
    public static let thinkers: [(model: String, label: String)] = [
        ("auto", "Jarvis picks"), ("worker", "Ornith (simple, stays on the PC)"), ("claude", "Claude (judgment and writing)"),
    ]

    private static let commandWords: [String: String] = [
        "set_temperature": "Set temperature to", "set_hvac_mode": "Set mode to", "volume_set": "Set volume to",
        "select_source": "Open", "media_play": "Play", "media_pause": "Pause", "media_stop": "Stop",
    ]

    /// A command in plain words: "turn_off" reads "Turn off".
    public static func commandLabel(_ command: String) -> String {
        if let known = commandWords[command] { return known }
        let words = command.replacingOccurrences(of: "_", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }

    /// Whether a command needs a value (a temperature, a mode, a volume, an app).
    public static func commandTakesValue(_ command: String) -> Bool {
        ["set_temperature", "set_hvac_mode", "volume_set", "select_source"].contains(command)
    }

    /// Whether that value is words rather than a number.
    public static func commandTakesWords(_ command: String) -> Bool {
        ["set_hvac_mode", "select_source"].contains(command)
    }

    /// Every address in a "to" box.
    public static func emailAddresses(_ to: String) -> [String] {
        to.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Something@somewhere.tld.
    static func looksLikeEmail(_ address: String) -> Bool {
        address.range(of: #"^[^@\s]+@[^@\s]+\.[^@\s]+$"#, options: .regularExpression) != nil
    }

    /// "HH:MM", 24-hour.
    public static func isClock(_ at: String) -> Bool {
        at.range(of: #"^([01]\d|2[0-3]):[0-5]\d$"#, options: .regularExpression) != nil
    }

    /// A short piece of typed text for a one-line summary.
    static func clip(_ words: String, max: Int = 48) -> String {
        words.count <= max ? words : String(words.prefix(max - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }

}

extension Playbooks {
    /// The playbooks (as JSON objects, for the editor) and the options from
    /// GET /api/jarvis/playbooks; nil when the book is missing.
    public static func book(from data: Data) -> (raw: [[String: Any]], options: PlaybookOptions)? {
        guard let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let book = body["book"] as? [String: Any] else { return nil }
        return (book["playbooks"] as? [[String: Any]] ?? [], PlaybookOptions(json: book["options"] as? [String: Any] ?? [:]))
    }
}

extension Playbook {
    /// The playbook as the editor's draft.
    public var draft: PlaybookDraft {
        PlaybookDraft(json: ((try? JSONSerialization.jsonObject(with: raw)) as? [String: Any]) ?? [:])
    }
}

/// What "Write it for me" got back (Dylan, 2026-11-19: "make this edit /
/// create playbook page more smooth and intuitive"). POST
/// /api/jarvis/playbooks {op: "draft", text} answers {ok: true, playbook}
/// in the listed shape minus id, madeBy and lastRun, NOT saved; or
/// {ok: false, message}.
public enum PlaybookDraftAnswer: Equatable, Sendable {
    /// The form, filled in; `assumed` is what Jarvis guessed (its edgeCases).
    case drafted(PlaybookDraft, assumed: [String])
    /// Why he couldn't, in words for the screen.
    case refused(String)

    /// The longest description the server passes on.
    public static let maxText = 1000

    /// Reads the answer; anything unreadable is a plain refusal.
    public static func read(_ data: Data) -> PlaybookDraftAnswer {
        guard let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return .refused("Jarvis didn't answer properly. Try again in a minute.")
        }
        if body["ok"] as? Bool == true, let object = body["playbook"] as? [String: Any] {
            var draft = PlaybookDraft(json: object)
            // A draft is always new, whatever came back.
            draft.id = nil
            let assumed = draft.edgeCases.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            return .drafted(draft, assumed: assumed)
        }
        let message = (body["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return .refused(message.isEmpty ? "Jarvis couldn't write it just now. Try again, or fill it in yourself." : message)
    }
}
