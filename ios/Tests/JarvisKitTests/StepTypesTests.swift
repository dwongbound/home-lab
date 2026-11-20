// Playbook step kinds driven by Jarvis's description (options.stepTypes),
// with the built-in eight as the fallback. Fixture JSON only.
import XCTest
@testable import JarvisKit

final class StepTypesTests: XCTestCase {
    /// Options as the page sends them, with a kind the app has never seen.
    private let options = PlaybookOptions(json: [
        "devices": [
            ["entity": "light.desk", "name": "Desk lamp", "kind": "light", "commands": ["turn_on", "turn_off"]],
            ["entity": "climate.bedroom", "name": "Bedroom", "kind": "climate", "commands": ["set_temperature", "set_hvac_mode"]],
            ["entity": "fan.porch", "name": "Porch fan", "kind": "fan", "commands": ["turn_on"]],
        ],
        "scenes": [],
        "apps": [["entity": "media_player.tv", "name": "TV", "apps": ["Jarvis", "Netflix"]]],
        "zones": ["home"],
        "jobs": [["id": "nightly", "name": "Nightly self-improvement"]],
        "stepTypes": [
            ["type": "speak", "label": "Say something out loud", "short": "Speak", "runs": "code", "summary": "Say “{words}” on {speaker.name}",
             "fields": [
                ["key": "speaker", "label": "Speaker", "kind": "choice", "required": true, "choicesFrom": "apps"],
                ["key": "words", "label": "Words", "kind": "text", "required": true, "max": 200],
                ["key": "loud", "label": "Loud", "kind": "bool", "required": false, "default": true],
                ["key": "repeat", "label": "Times", "kind": "number", "required": true, "min": 1, "max": 3, "default": 1],
             ]],
            ["type": "device", "label": "Control a device", "short": "Device", "runs": "code", "summary": "{entity.name}: {command} {value}",
             "fields": [
                ["key": "entity", "label": "Device", "kind": "choice", "required": true, "choicesFrom": "devices"],
                ["key": "command", "label": "Do", "kind": "choice", "required": true, "choicesFrom": "devices", "dependsOn": "entity", "choicesKey": "commands"],
                ["key": "value", "label": "Value", "kind": "by_command", "dependsOn": "command", "byCommand": [
                    "turn_on": ["label": "Brightness %", "kind": "number", "required": false, "min": 1, "max": 100, "onlyDomains": ["light"]],
                    "set_temperature": ["label": "Temperature (°F)", "kind": "number", "required": true, "min": 45, "max": 90],
                ]],
             ]],
            ["type": "scene", "label": "Run a scene", "short": "Scene", "summary": "Scene: {entity.name}",
             "fields": [["key": "entity", "label": "Scene", "kind": "choice", "required": true, "choicesFrom": "scenes"]]],
            ["type": "broken", "fields": "nope"],
        ],
    ])

    func testTheListIsReadAndBrokenKindsDropped() {
        XCTAssertEqual(options.stepTypes.map(\.type), ["speak", "device", "scene"])
        XCTAssertEqual(options.stepTypes[0].short, "Speak")
    }

    func testJarvisSnakeCaseReadsTheSame() {
        let snake = StepTypes.parse([["type": "wait", "label": "Wait", "summary": "Wait {seconds} s",
                                      "fields": [["key": "seconds", "label": "Seconds", "kind": "number", "required": true, "max_items": 3]]]])
        XCTAssertEqual(snake?.first?.fields.first?.rule.maxItems, 3)
    }

    func testNoListFallsBackToTheBuiltInEight() {
        let old = PlaybookOptions(json: ["devices": []])
        XCTAssertEqual(old.stepTypes.map(\.type), ["device", "scene", "app", "notify", "think", "email", "wait", "job"])
        XCTAssertEqual(old.thinkers.map(\.entity), ["worker", "claude"])
    }

    /// A kind the app has never heard of: added, filled in, checked, saved.
    func testANewKindNeedsNoCode() {
        var step = DraftStep.blank("speak", options: options)
        XCTAssertEqual(step.json as NSDictionary, ["type": "speak", "speaker": "media_player.tv", "words": "", "loud": true, "repeat": 1] as NSDictionary)
        XCTAssertEqual(step.problem(options), "Words is missing")
        step = step.with("words", .text("Dinner"), options: options)
        XCTAssertNil(step.problem(options))
        XCTAssertEqual(step.sentence(options), "Say “Dinner” on TV")
        step = step.with("repeat", .number(5), options: options)
        XCTAssertEqual(step.problem(options), "Times must be between 1 and 3")
    }

    func testPickingAnotherDeviceStartsItsCommandOver() {
        var step = DraftStep.blank("device", options: options)
        XCTAssertEqual(step["entity"], .text("light.desk"))
        XCTAssertEqual(step["command"], .text("turn_on"))
        step = step.with("entity", .text("climate.bedroom"), options: options)
        XCTAssertEqual(step["command"], .text("set_temperature"), "the new device's first command")
        XCTAssertEqual(step.problem(options), "Temperature (°F) is missing")
        step = step.with("value", .number(68), options: options)
        XCTAssertNil(step.problem(options))
        XCTAssertEqual(step.sentence(options), "Bedroom: set temperature 68")
    }

    func testBrightnessIsOnlyForALight() {
        let lamp = DraftStep(json: ["type": "device", "entity": "light.desk", "command": "turn_on"])!
        let fan = DraftStep(json: ["type": "device", "entity": "fan.porch", "command": "turn_on"])!
        let valueField = options.stepTypes[1].fields[2]
        XCTAssertEqual(options.activeRule(valueField, lamp)?.label, "Brightness %")
        XCTAssertNil(options.activeRule(valueField, fan))
    }

    func testAKindWithNothingToPickIsNotOffered() {
        XCTAssertFalse(options.stepChoices.map(\.type).contains("scene"), "no scenes to pick from")
        XCTAssertTrue(options.stepChoices.map(\.type).contains("speak"))
    }

    func testThinkConfirmIsASwitchThatStartsOff() {
        let old = PlaybookOptions(json: [:])
        let step = DraftStep.blank("think", options: old)
        XCTAssertEqual(step["confirm"], .bool(false))
        XCTAssertEqual(step["model"], .text("auto"), "a pick that isn't required is Jarvis's")
    }

    /// Untouched steps go back exactly as they came: numbers stay numbers.
    func testUntouchedStepsKeepTheirJSON() {
        let came: [String: Any] = ["type": "device", "entity": "climate.bedroom", "command": "set_temperature", "value": 67, "extra": ["a": 1]]
        XCTAssertEqual(DraftStep(json: came)!.json as NSDictionary, came as NSDictionary)
        let half: [String: Any] = ["type": "device", "entity": "light.desk", "command": "turn_on", "value": 0.4]
        XCTAssertEqual(DraftStep(json: half)!.json as NSDictionary, half as NSDictionary)
    }
}
