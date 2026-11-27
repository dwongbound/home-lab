// Playbook step kinds as Jarvis describes them (Dylan, 2026-11-20: new kinds
// should need no code change). The native twin of the page's
// server/sources/step-types.mjs (parsing, DEFAULT_STEP_TYPES) and
// src/lib/playbooks.ts (activeField, choicesFor, stepLine, blankStep,
// withField, fieldProblem, stepProblem, stepChoices). Keep them in step.
//
// GET /api/jarvis/playbooks's options carry `stepTypes` (the page's
// camelCase); a Jarvis too old to send them gets DEFAULT_STEP_TYPES, which
// is exactly what the app showed before.
import Foundation

/// A step's value: words, a number or a switch, as the page's StepValue.
public enum StepValue: Equatable, Sendable {
    case text(String)
    case number(Double)
    case bool(Bool)

    /// Reads a JSON value; nil for anything else (a list, an object, null).
    public init?(json value: Any?) {
        switch value {
        case let n as NSNumber where CFGetTypeID(n) == CFBooleanGetTypeID(): self = .bool(n.boolValue)
        case let n as NSNumber: self = .number(n.doubleValue)
        case let s as String: self = .text(s)
        default: return nil
        }
    }

    /// As JSON: a whole number stays a whole number.
    public var json: Any {
        switch self {
        case .text(let s): return s
        case .bool(let b): return b
        case .number(let d): return d == d.rounded() && abs(d) < 1e15 ? NSNumber(value: Int(d)) : NSNumber(value: d)
        }
    }

    public var text: String? { if case .text(let s) = self { return s }; return nil }
    public var number: Double? { if case .number(let d) = self { return d }; return nil }
    public var bool: Bool? { if case .bool(let b) = self { return b }; return nil }
}

/// How one box of a step is filled in (StepFieldRule).
public struct StepFieldRule: Equatable, Sendable {
    public var label: String
    /// text, longtext, number, bool, choice, emails or by_command.
    public var kind: String
    public var required: Bool
    public var min: Double?
    public var max: Double?
    public var step: Double?
    public var maxItems: Int?
    public var placeholder: String?
    public var defaultValue: StepValue?
    public var choices: [String]?
    public var choicesFrom: String?
    public var dependsOn: String?
    public var choicesKey: String?
    public var onlyDomains: [String]?

    static let kinds: Set<String> = ["text", "longtext", "number", "bool", "choice", "emails", "by_command"]
}

/// One field of a step type (StepField).
public struct StepField: Equatable, Sendable {
    public var key: String
    public var rule: StepFieldRule
    /// For by_command: the rule for each pick of `dependsOn` that takes a value.
    public var byCommand: [String: StepFieldRule] = [:]
}

/// One kind of step (StepType).
public struct StepTypeInfo: Equatable, Sendable, Identifiable {
    public var type: String
    public var label: String
    public var short: String
    /// "code" or "thinking".
    public var runs: String
    /// The row's one line: "{entity.name}: {command} {value}".
    public var summary: String
    public var fields: [StepField]
    public var id: String { type }
}

public enum StepTypes {
    static let maxTypes = 40
    static let maxFields = 12
    private static let name = try! NSRegularExpression(pattern: "^[a-z][a-z0-9_]{0,39}$")

    static func isName(_ value: Any?) -> Bool {
        guard let s = value as? String else { return false }
        return name.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    /// Reads one key in either spelling (the page's camelCase or Jarvis's snake_case).
    private static func value(_ raw: [String: Any], _ camel: String, _ snake: String) -> Any? {
        raw[camel] ?? raw[snake]
    }

    private static func words(_ value: Any?, max: Int) -> String? {
        guard let s = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return String(s.prefix(max))
    }

    private static func number(_ value: Any?) -> Double? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite else { return nil }
        return n.doubleValue
    }

    private static func strings(_ value: Any?) -> [String]? {
        guard let list = value as? [Any] else { return nil }
        return Array(list.compactMap { ($0 as? String).flatMap { $0.isEmpty ? nil : String($0.prefix(80)) } }.prefix(40))
    }

    /// The parts every field shares (fieldBody); nil when its kind is unknown.
    static func rule(_ raw: [String: Any]) -> StepFieldRule? {
        guard let kind = raw["kind"] as? String, StepFieldRule.kinds.contains(kind) else { return nil }
        let fallback = StepValue(json: raw["default"])
        return StepFieldRule(
            label: words(raw["label"], max: 80) ?? "",
            kind: kind,
            required: raw["required"] as? Bool == true,
            min: number(raw["min"]), max: number(raw["max"]), step: number(raw["step"]),
            maxItems: number(value(raw, "maxItems", "max_items")).map { Int($0) },
            placeholder: words(raw["placeholder"], max: 120),
            defaultValue: fallback,
            choices: strings(raw["choices"]),
            choicesFrom: isName(value(raw, "choicesFrom", "choices_from")) ? value(raw, "choicesFrom", "choices_from") as? String : nil,
            dependsOn: isName(value(raw, "dependsOn", "depends_on")) ? value(raw, "dependsOn", "depends_on") as? String : nil,
            choicesKey: isName(value(raw, "choicesKey", "choices_key")) ? value(raw, "choicesKey", "choices_key") as? String : nil,
            onlyDomains: strings(value(raw, "onlyDomains", "only_domains"))
        )
    }

    /// One field (parseField); nil when it isn't well formed.
    static func field(_ raw: [String: Any]) -> StepField? {
        guard isName(raw["key"]), let key = raw["key"] as? String, let rule = rule(raw) else { return nil }
        var field = StepField(key: key, rule: rule)
        if rule.kind == "by_command" {
            let subs = value(raw, "byCommand", "by_command") as? [String: Any] ?? [:]
            for (command, sub) in subs {
                guard isName(command), let sub = sub as? [String: Any], let subRule = self.rule(sub), subRule.kind != "by_command" else { continue }
                field.byCommand[command] = subRule
            }
        }
        return field
    }

    /// One step type (parseType); nil when it isn't well formed.
    static func type(_ raw: [String: Any]) -> StepTypeInfo? {
        guard isName(raw["type"]), let type = raw["type"] as? String, let fields = raw["fields"] as? [Any] else { return nil }
        let label = words(raw["label"], max: 80) ?? type
        return StepTypeInfo(
            type: type, label: label,
            short: words(raw["short"], max: 24) ?? label,
            runs: raw["runs"] as? String == "thinking" ? "thinking" : "code",
            summary: words(raw["summary"], max: 200) ?? label,
            fields: Array(fields.compactMap { ($0 as? [String: Any]).flatMap(field) }.prefix(maxFields))
        )
    }

    /// The list Jarvis sent, without anything broken; nil when he sent
    /// none (an older Jarvis), so the caller falls back to the defaults.
    public static func parse(_ raw: Any?) -> [StepTypeInfo]? {
        guard let list = raw as? [Any] else { return nil }
        let types = Array(list.compactMap { ($0 as? [String: Any]).flatMap(type) }.prefix(maxTypes))
        return types.isEmpty ? nil : types
    }

    /// The step types Jarvis had on 2026-11-20 (DEFAULT_STEP_TYPES).
    public static let defaults: [StepTypeInfo] = {
        let json = #"""
        [
          {"type": "device", "label": "Control a device", "short": "Device", "runs": "code", "summary": "{entity.name}: {command} {value}",
           "fields": [
             {"key": "entity", "label": "Device", "kind": "choice", "required": true, "choices_from": "devices"},
             {"key": "command", "label": "Do", "kind": "choice", "required": true, "choices_from": "devices", "depends_on": "entity", "choices_key": "commands"},
             {"key": "value", "label": "Value", "kind": "by_command", "depends_on": "command", "by_command": {
               "turn_on": {"label": "Brightness %", "kind": "number", "required": false, "min": 1, "max": 100, "only_domains": ["light"]},
               "volume_set": {"label": "Volume (0 to 1)", "kind": "number", "required": true, "min": 0, "max": 1, "step": 0.05},
               "select_source": {"label": "App or input", "kind": "choice", "required": true, "choices_from": "apps", "depends_on": "entity", "choices_key": "apps"},
               "set_temperature": {"label": "Temperature (°F)", "kind": "number", "required": true, "min": 45, "max": 90},
               "set_hvac_mode": {"label": "Mode", "kind": "choice", "required": true, "choices": ["off", "heat", "cool", "heat_cool", "auto"]}
             }}
           ]},
          {"type": "scene", "label": "Run a scene", "short": "Scene", "runs": "code", "summary": "Scene: {entity.name}",
           "fields": [{"key": "entity", "label": "Scene", "kind": "choice", "required": true, "choices_from": "scenes"}]},
          {"type": "app", "label": "Open an app on a TV", "short": "TV app", "runs": "code", "summary": "Open {app} on {entity.name}",
           "fields": [
             {"key": "entity", "label": "TV", "kind": "choice", "required": true, "choices_from": "apps"},
             {"key": "app", "label": "App", "kind": "choice", "required": true, "choices_from": "apps", "depends_on": "entity", "choices_key": "apps"}
           ]},
          {"type": "notify", "label": "Send me a notification", "short": "Notify me", "runs": "code", "summary": "Notify me: {text}",
           "fields": [{"key": "text", "label": "Message", "kind": "longtext", "required": true, "max": 2000, "placeholder": "What to tell me"}]},
          {"type": "think", "label": "Have Jarvis work something out", "short": "Ask Jarvis", "runs": "thinking", "summary": "Jarvis: {text}",
           "fields": [
             {"key": "text", "label": "What Jarvis should do", "kind": "longtext", "required": true, "max": 2000, "placeholder": "Check tomorrow’s weather and tell me if I need a jacket"},
             {"key": "model", "label": "Who does it", "kind": "choice", "required": false, "choices_from": "thinkers", "default": "claude"},
             {"key": "confirm", "label": "Ask me first", "kind": "bool", "required": false, "default": false}
           ]},
          {"type": "email", "label": "Send an email", "short": "Email", "runs": "code", "summary": "Email {to}: {subject}",
           "fields": [
             {"key": "to", "label": "To", "kind": "emails", "required": true, "max_items": 10},
             {"key": "subject", "label": "Subject", "kind": "text", "required": true, "max": 200},
             {"key": "body", "label": "Message", "kind": "longtext", "required": true, "max": 5000},
             {"key": "confirm", "label": "Ask me first", "kind": "bool", "required": false, "default": false}
           ]},
          {"type": "wait", "label": "Wait", "short": "Wait", "runs": "code", "summary": "Wait {seconds} s",
           "fields": [{"key": "seconds", "label": "Seconds", "kind": "number", "required": true, "min": 1, "max": 600, "default": 60}]},
          {"type": "job", "label": "Run one of Jarvis’s jobs", "short": "Jarvis job", "runs": "code", "summary": "Run: {job.name}",
           "fields": [{"key": "job", "label": "Job", "kind": "choice", "required": true, "choices_from": "jobs"}]}
        ]
        """#
        return parse(try? JSONSerialization.jsonObject(with: Data(json.utf8))) ?? []
    }()

    /// Who can do a thinking step when Jarvis doesn't say (DEFAULT_THINKERS).
    public static let defaultThinkers: [(id: String, name: String)] = [
        ("worker", "Ornith (simple, stays on the PC)"),
        ("claude", "Claude (judgment and writing)"),
    ]

    /// The page's word for a pick left to Jarvis.
    public static let auto = "auto"

    /// An id in plain words: "turn_off" reads "Turn off" (plainWords).
    public static func plainWords(_ id: String) -> String {
        let words = id.replacingOccurrences(of: "_", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}
