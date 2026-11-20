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
    /// Jarvis's own jobs a "job" step can run ({id, name}); empty on a
    /// server from before job steps (2026-11-20).
    public var jobs: [Named] = []
    /// Who can do a thinking step; Jarvis's two when he doesn't say.
    public var thinkers: [Named] = StepTypes.defaultThinkers.map { Named(entity: $0.id, name: $0.name) }
    /// The kinds of step and their fields, as Jarvis describes them; the
    /// built-in eight when he doesn't (an older Jarvis).
    public var stepTypes: [StepTypeInfo] = StepTypes.defaults
    /// The options as they came, for a choice list the app doesn't name.
    var raw = RawJSON([:])

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
        func named(_ key: String) -> [Named] {
            (object[key] as? [[String: Any]] ?? []).compactMap { r in
                guard let id = r["id"] as? String, !id.isEmpty else { return nil }
                return Named(entity: id, name: (r["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? id)
            }
        }
        jobs = named("jobs")
        let sentThinkers = named("thinkers")
        if !sentThinkers.isEmpty { thinkers = sentThinkers }
        stepTypes = StepTypes.parse(object["stepTypes"] ?? object["step_types"]) ?? StepTypes.defaults
        raw = RawJSON(object)
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
    /// Fields of the trigger the editor doesn't model, sent back as they came.
    var extra = RawJSON([:])

    public init(type: String, at: String = "08:00", days: [String] = [], zone: String = "home", minAway: Int = 15) {
        self.type = type; self.at = at; self.days = days; self.zone = zone; self.minAway = minAway
    }

    /// What a trigger of `type` starts as when it's picked (blankTrigger).
    public static func blank(_ type: String) -> DraftTrigger {
        DraftTrigger(type: type)
    }

    /// The page's JSON for it, with any fields it came with that the
    /// editor doesn't model.
    public var json: [String: Any] {
        let held: [String: Any]
        switch type {
        case "time": held = ["type": type, "at": at, "days": days]
        case "arrive": held = ["type": type, "zone": zone, "minAway": minAway]
        case "leave": held = ["type": type, "zone": zone]
        default: held = ["type": type]
        }
        return extra.object.merging(held) { _, mine in mine }
    }

    /// The same trigger in the read-only shape the list's wording uses.
    public var plain: PlaybookTrigger {
        PlaybookTrigger(type: type, at: at, days: days, minAway: minAway)
    }
}

/// A piece of the page's JSON kept exactly as it came, so what the app
/// doesn't model goes back unchanged on a save.
public struct RawJSON: Equatable, Sendable {
    let data: Data

    public init(_ object: [String: Any]) {
        data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
    }

    public var object: [String: Any] {
        ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any]) ?? [:]
    }
}

/// One step, as the editor holds it: the JSON it came with, plus only what
/// was changed here. A step opened and saved untouched goes back exactly as
/// it came (numbers stay numbers, no key dropped or added), whatever its
/// kind, known to the app or not (Dylan, 2026-11-20).
public struct DraftStep: Equatable, Sendable {
    public private(set) var type: String
    /// The step as it came.
    let raw: RawJSON
    /// Its scalar values as they came, for reading.
    let base: [String: StepValue]
    /// Values changed here; nil = taken out.
    var edits: [String: StepValue?] = [:]

    /// A new step of a kind, empty.
    public init(type: String) {
        self.type = type
        raw = RawJSON(["type": type])
        base = [:]
    }

    /// Reads a step from the page's JSON. Never nil: a kind the app doesn't
    /// know is kept whole and saved back as it came.
    public init?(json r: [String: Any]) {
        type = r["type"] as? String ?? ""
        raw = RawJSON(r)
        var values: [String: StepValue] = [:]
        for (key, value) in r where key != "type" {
            if let v = StepValue(json: value) { values[key] = v }
        }
        base = values
    }

    /// One value of the step, as it stands.
    public subscript(key: String) -> StepValue? {
        if let edited = edits[key] { return edited }
        return base[key]
    }

    /// The page's JSON for it: what came, with the changes made here.
    public var json: [String: Any] {
        var out = raw.object
        out["type"] = type
        for (key, value) in edits {
            if let value { out[key] = value.json } else { out.removeValue(forKey: key) }
        }
        return out
    }

    /// The step with one value set (or taken out) and nothing else changed.
    func setting(_ key: String, _ value: StepValue?) -> DraftStep {
        var next = self
        next.edits[key] = .some(value)
        return next
    }

    /// What a step of `type` starts as: the first device, scene or app
    /// Jarvis lists, and his defaults (blankStep).
    public static func blank(_ type: String, options: PlaybookOptions) -> DraftStep {
        var step = DraftStep(type: type)
        for field in options.stepType(of: step)?.fields ?? [] {
            if let rule = options.activeRule(field, step) { step = step.setting(field.key, options.startValue(rule, step)) }
        }
        return step
    }

    /// What the step is still missing, or nil when it's complete
    /// (stepProblem). A kind Jarvis didn't describe is his to judge.
    public func problem(_ options: PlaybookOptions) -> String? {
        for field in options.stepType(of: self)?.fields ?? [] {
            guard let rule = options.activeRule(field, self) else { continue }
            if let problem = StepCheck.problem(rule, self[field.key]) { return problem }
        }
        return nil
    }

    /// The step as one line, from its kind's summary pattern (stepLine).
    public func sentence(_ options: PlaybookOptions) -> String {
        guard let described = options.stepType(of: self) else { return StepTypes.plainWords(type) }
        let pattern = try! NSRegularExpression(pattern: #"\{([a-z0-9_]+)(\.name)?\}"#)
        let summary = described.summary as NSString
        var line = ""
        var last = 0
        for match in pattern.matches(in: described.summary, range: NSRange(location: 0, length: summary.length)) {
            line += summary.substring(with: NSRange(location: last, length: match.range.location - last))
            let key = summary.substring(with: match.range(at: 1))
            line += options.valueWords(self, key: key, byName: match.range(at: 2).location != NSNotFound)
            last = match.range.location + match.range.length
        }
        line += summary.substring(from: last)
        return line.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The step with one value changed (withField): fields that hang off it
    /// start over, since another device has other commands and another
    /// command takes another value.
    public func with(_ key: String, _ value: StepValue?, options: PlaybookOptions) -> DraftStep {
        var next = setting(key, value)
        var changed = [key]
        for field in options.stepType(of: self)?.fields ?? [] {
            guard changed.contains(where: { StepCheck.hangsOff(field, $0) }) else { continue }
            let rule = options.activeRule(field, next)
            next = next.setting(field.key, rule.flatMap { options.startValue($0, next) })
            changed.append(field.key)
        }
        return next
    }
}

/// What one field still needs (fieldProblem), and which fields hang off
/// which (hangsOff).
enum StepCheck {
    static func problem(_ rule: StepFieldRule, _ value: StepValue?) -> String? {
        if rule.kind == "bool" { return nil }
        if rule.kind == "emails" {
            let addresses = PlaybookWording.emailAddresses(value?.text ?? "")
            let most = rule.maxItems ?? 10
            if addresses.isEmpty { return rule.required ? "give it one to \(most) email addresses" : nil }
            if addresses.count > most { return "give it one to \(most) email addresses" }
            if !addresses.allSatisfy(PlaybookWording.looksLikeEmail) { return "check the email address" }
            return nil
        }
        let empty: Bool
        switch value {
        case nil: empty = true
        case .text(let s)?: empty = s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default: empty = false
        }
        if empty { return rule.required ? "\(rule.label) is missing" : nil }
        if rule.kind == "number" {
            let low = rule.min ?? -.infinity
            let high = rule.max ?? .infinity
            guard let n = value?.number, n >= low, n <= high else {
                return "\(rule.label) must be between \(DraftStepNumber.words(low)) and \(DraftStepNumber.words(high))"
            }
        }
        return nil
    }

    static func hangsOff(_ field: StepField, _ key: String) -> Bool {
        field.rule.dependsOn == key || field.byCommand.values.contains { $0.dependsOn == key }
    }
}

/// "21" for 21.0, "0.4" for 0.4.
enum DraftStepNumber {
    static func words(_ d: Double) -> String {
        guard d.isFinite else { return d > 0 ? "∞" : "-∞" }
        return d == d.rounded() ? String(Int(d)) : String(d)
    }
}

/// One thing a choice field can be set to: the value saved and its words.
public struct StepChoice: Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
}

extension PlaybookOptions {
    /// Jarvis's description of a step's kind; nil for one he didn't describe.
    public func stepType(of step: DraftStep) -> StepTypeInfo? {
        stepTypes.first { $0.type == step.type }
    }

    /// What heads a step in the editor (stepLabel).
    public func stepLabel(_ step: DraftStep) -> String {
        stepType(of: step)?.label ?? StepTypes.plainWords(step.type)
    }

    /// The kinds of step the editor can add: every one Jarvis describes, but
    /// not one whose only pick has nothing to pick from (stepChoices).
    public var stepChoices: [StepTypeInfo] {
        stepTypes.filter { t in
            !t.fields.contains { f in
                f.rule.kind == "choice" && f.rule.required && f.rule.dependsOn == nil
                    && choices(for: f.rule, DraftStep(type: t.type)).isEmpty
            }
        }
    }

    /// One options list by name (devices, scenes, apps, jobs, thinkers), as
    /// rows with an id: devices, scenes and TVs go by `entity`, the rest by `id`.
    func optionRows(_ name: String) -> [(id: String, name: String, row: [String: Any])] {
        if name == "thinkers" {
            return thinkers.map { ($0.entity, $0.name, ["id": $0.entity, "name": $0.name]) }
        }
        if name == "jobs" {
            return jobs.map { ($0.entity, $0.name, ["id": $0.entity, "name": $0.name]) }
        }
        let list = raw.object[name] as? [[String: Any]] ?? []
        return list.compactMap { row in
            guard let id = (row["entity"] as? String) ?? (row["id"] as? String), !id.isEmpty else { return nil }
            return (id, (row["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? id, row)
        }
    }

    /// What a choice field offers for this step: fixed words, a whole
    /// options list, or the picked row's own list (choicesFor).
    public func choices(for rule: StepFieldRule, _ step: DraftStep) -> [StepChoice] {
        if let fixed = rule.choices { return fixed.map { StepChoice(id: $0, name: StepTypes.plainWords($0)) } }
        guard let from = rule.choicesFrom else { return [] }
        let rows = optionRows(from)
        guard let dependsOn = rule.dependsOn, let key = rule.choicesKey else {
            return rows.map { StepChoice(id: $0.id, name: $0.name) }
        }
        let picked = rows.first { $0.id == step[dependsOn]?.text }
        let sub = picked?.row[key] as? [Any] ?? []
        return sub.compactMap { ($0 as? String).map { StepChoice(id: $0, name: StepTypes.plainWords($0)) } }
    }

    /// The kind of device a step is about (light, climate).
    func deviceKind(_ step: DraftStep) -> String {
        devices.first { $0.entity == step["entity"]?.text }?.kind ?? ""
    }

    /// The field as it applies to this step right now (activeField): a
    /// by_command field becomes the rule for the picked command, or nil
    /// when that command takes no value (or only for another kind of device).
    public func activeRule(_ field: StepField, _ step: DraftStep) -> StepFieldRule? {
        guard field.rule.kind == "by_command" else { return field.rule }
        guard let picked = step[field.rule.dependsOn ?? ""]?.text, let rule = field.byCommand[picked] else { return nil }
        if let only = rule.onlyDomains, !only.contains(deviceKind(step)) { return nil }
        return rule
    }

    /// What a field starts as, given the step so far; nil = left out (startValue).
    func startValue(_ rule: StepFieldRule, _ step: DraftStep) -> StepValue? {
        switch rule.kind {
        case "choice":
            // A pick that isn't required is left to Jarvis.
            if !rule.required { return .text(StepTypes.auto) }
            return .text(choices(for: rule, step).first?.id ?? "")
        case "bool": return .bool(rule.defaultValue?.bool == true)
        case "number": return rule.defaultValue?.number.map(StepValue.number)
        default: return .text("")
        }
    }

    /// A step's value as it reads in the row: a pick's name, or the typed
    /// words cut short (valueWords).
    func valueWords(_ step: DraftStep, key: String, byName: Bool) -> String {
        guard let value = step[key] else { return "" }
        if case .text(let s) = value, s.isEmpty || s == StepTypes.auto { return "" }
        let field = stepType(of: step)?.fields.first { $0.key == key }
        let rule = field.flatMap { activeRule($0, step) }
        if rule?.kind == "choice", case .text(let id) = value, let rule {
            let name = choices(for: rule, step).first { $0.id == id }?.name
            // "{entity.name}" asks for the name; a bare "{command}" reads mid-sentence.
            return byName ? (name ?? id) : id.replacingOccurrences(of: "_", with: " ")
        }
        switch value {
        case .text(let s): return PlaybookWording.clip(s)
        case .number(let d): return DraftStepNumber.words(d)
        case .bool(let b): return b ? "true" : "false"
        }
    }

    /// A job's name; its id when the server didn't name it.
    public func jobName(_ id: String) -> String {
        jobs.first { $0.entity == id }?.name ?? id
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
    /// Everything else the playbook came with that the editor doesn't
    /// model, sent back as it was.
    var extra = RawJSON([:])

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
        var triggerRest = t
        for key in ["type", "at", "days", "zone", "minAway"] { triggerRest.removeValue(forKey: key) }
        trigger.extra = RawJSON(triggerRest)
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
        var rest = o
        for key in Self.modelled { rest.removeValue(forKey: key) }
        extra = RawJSON(rest)
    }

    /// The fields the editor holds itself, plus the two Jarvis keeps.
    static let modelled: [String] = ["id", "name", "enabled", "purpose", "whenToUse", "trigger", "inputs", "steps",
                                     "decisions", "done", "edgeCases", "standard", "badVersion", "lastRun", "madeBy"]

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
        var out = extra.object
        let held: [String: Any] = [
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
        out.merge(held) { _, mine in mine }
        if let id { out["id"] = id }
        return out
    }

    /// Why it can't be saved yet, in plain words; nil when it can (playbookProblem).
    public func problem(_ options: PlaybookOptions = PlaybookOptions()) -> String? {
        if name.trimmingCharacters(in: .whitespaces).isEmpty { return "Give the playbook a name" }
        if trigger.type == "time", !PlaybookWording.isClock(trigger.at) { return "Pick a time" }
        if steps.isEmpty { return "Add at least one step" }
        if steps.count > Self.maxSteps { return "A playbook can have up to \(Self.maxSteps) steps" }
        for (i, step) in steps.enumerated() {
            if let problem = step.problem(options) { return "Step \(i + 1): \(problem)" }
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
        // Shown, never offered: job steps come from Jarvis (2026-11-20).
        ("job", "Run one of Jarvis's jobs"),
    ]
    /// The "Add a step" row's buttons (the page's STEP_CHOICES `short`), with an icon each.
    public static let stepButtons: [(type: String, short: String, icon: String)] = [
        ("device", "Device", "lightbulb"), ("scene", "Scene", "sparkles"), ("app", "TV app", "tv"),
        ("notify", "Notify me", "bell"), ("think", "Ask Jarvis", "brain"), ("email", "Email", "envelope"),
        ("wait", "Wait", "hourglass"),
    ]
    /// The icon for a step's kind.
    public static func stepIcon(_ type: String) -> String {
        if type == "job" { return "gearshape.2" }
        // A kind the app has no icon for (one Jarvis added): a plain mark.
        return stepButtons.first { $0.type == type }?.icon ?? "circle.dashed"
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
