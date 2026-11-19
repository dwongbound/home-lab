// "Write it for me": reading Jarvis's drafted playbook (POST
// /api/jarvis/playbooks {op: "draft"}), and the folded step rows' sentences.
import XCTest
@testable import JarvisKit

final class PlaybookDraftAnswerTests: XCTestCase {
    func testADraftFillsTheFormAndSaysWhatWasAssumed() {
        let body = """
        {"ok": true, "playbook": {"name": "Bedtime", "enabled": true, "purpose": "Shut down for the night",
          "whenToUse": "", "trigger": {"type": "time", "at": "23:00", "days": ["mon","tue","wed","thu","fri"]},
          "inputs": [], "steps": [{"type": "device", "entity": "light.desk", "command": "turn_off"},
          {"type": "notify", "text": "Lights are off"}], "decisions": [], "done": ["Every light is off"],
          "edgeCases": ["You meant the desk lamp", "  "], "standard": "", "badVersion": ""}}
        """
        guard case .drafted(let draft, let assumed) = PlaybookDraftAnswer.read(Data(body.utf8)) else {
            return XCTFail("expected a draft")
        }
        XCTAssertNil(draft.id)
        XCTAssertEqual(draft.name, "Bedtime")
        XCTAssertEqual(draft.trigger.type, "time")
        XCTAssertEqual(draft.trigger.at, "23:00")
        XCTAssertEqual(draft.trigger.days.count, 5)
        XCTAssertEqual(draft.steps, [.device(entity: "light.desk", command: "turn_off", value: ""), .notify(text: "Lights are off")])
        XCTAssertEqual(draft.done, ["Every light is off"])
        XCTAssertEqual(assumed, ["You meant the desk lamp"])
        XCTAssertNil(draft.problem)
    }

    func testADraftIsAlwaysNew() {
        let body = #"{"ok": true, "playbook": {"id": "p1", "name": "X", "steps": []}}"#
        guard case .drafted(let draft, let assumed) = PlaybookDraftAnswer.read(Data(body.utf8)) else { return XCTFail() }
        XCTAssertNil(draft.id)
        XCTAssertEqual(assumed, [])
        XCTAssertEqual(draft.trigger.type, "manual")
    }

    func testARefusalKeepsJarvisWordsOrSaysSomethingPlain() {
        XCTAssertEqual(PlaybookDraftAnswer.read(Data(#"{"ok": false, "message": "Jarvis is busy"}"#.utf8)), .refused("Jarvis is busy"))
        guard case .refused(let blank) = PlaybookDraftAnswer.read(Data(#"{"ok": false}"#.utf8)) else { return XCTFail() }
        XCTAssertFalse(blank.isEmpty)
        guard case .refused(let junk) = PlaybookDraftAnswer.read(Data("<html>".utf8)) else { return XCTFail() }
        XCTAssertFalse(junk.isEmpty)
        // ok true with no playbook is not a draft.
        guard case .refused = PlaybookDraftAnswer.read(Data(#"{"ok": true}"#.utf8)) else { return XCTFail() }
    }

    func testStepRowsReadAsSentences() {
        var options = PlaybookOptions()
        options.devices = [.init(entity: "light.desk", name: "Desk lamp", kind: "light", commands: ["turn_on", "turn_off"])]
        XCTAssertEqual(DraftStep.device(entity: "light.desk", command: "turn_off", value: "").sentence(options), "Turn off Desk lamp")
        XCTAssertEqual(DraftStep.device(entity: "", command: "turn_off", value: "").sentence(options), "Pick a device")
        XCTAssertEqual(DraftStep.wait(seconds: 120).sentence(options), "Wait 2 min")
        XCTAssertEqual(DraftStep.notify(text: "").sentence(options), "Notify me: write what it says")
        XCTAssertEqual(DraftStep.scene(entity: "").sentence(options), "Pick a scene")
    }
}

final class DietCaptionTests: XCTestCase {
    func testOneCaptionShapeInEveryColumn() {
        XCTAssertEqual(DietGoals.caption(eaten: 0, goal: 1750, unit: "", limit: true).words, "of 1750")
        XCTAssertEqual(DietGoals.caption(eaten: 1870, goal: 1750, unit: "", limit: true).words, "120 over")
        XCTAssertTrue(DietGoals.caption(eaten: 1870, goal: 1750, unit: "", limit: true).over)
        XCTAssertEqual(DietGoals.caption(eaten: 67, goal: 55, unit: "g", limit: true).words, "12 g over")
        XCTAssertEqual(DietGoals.caption(eaten: 40, goal: 55, unit: "g", limit: true).words, "of 55 g")
        // Protein past its goal is good, never "over".
        XCTAssertEqual(DietGoals.caption(eaten: 160, goal: 140, unit: "g", limit: false).words, "of 140 g")
        XCTAssertFalse(DietGoals.caption(eaten: 160, goal: 140, unit: "g", limit: false).over)
        XCTAssertEqual(DietGoals.caption(eaten: 10, goal: nil, unit: "g", limit: true).words, "no goal")
    }

    func testWeekDaysAndTodayReadFatAndCarbs() throws {
        let week = try JSONDecoder().decode(WeekDay.self, from: Data(#"{"date":"2026-11-19","calories":1200,"goal":1750,"protein":90,"proteinGoal":140,"fat":40,"fatGoal":55,"carbs":null,"carbsGoal":175}"#.utf8))
        XCTAssertEqual(week.fat, 40); XCTAssertEqual(week.fatGoal, 55); XCTAssertNil(week.carbs); XCTAssertEqual(week.carbsGoal, 175)
        let today = try JSONDecoder().decode(Nutrition.self, from: Data(#"{"date":"2026-11-19","eaten":1200,"goal":1750,"left":550,"fat":40,"fatGoal":55,"carbs":120,"carbsGoal":175}"#.utf8))
        XCTAssertEqual(today.fat, 40); XCTAssertEqual(today.carbsGoal, 175)
        XCTAssertEqual(Nutrition(dictionary: today.dictionary)?.carbs, 120)
    }
}

final class ComposerSizeTests: XCTestCase {
    func testTucksAwayOnlyWhenScrolledUpAndIdle() {
        XCTAssertTrue(ComposerSize.collapsed(atBottom: false, focused: false, hasDraft: false, sending: false, opened: false))
        XCTAssertFalse(ComposerSize.collapsed(atBottom: true, focused: false, hasDraft: false, sending: false, opened: false))
        XCTAssertFalse(ComposerSize.collapsed(atBottom: false, focused: true, hasDraft: false, sending: false, opened: false))
        XCTAssertFalse(ComposerSize.collapsed(atBottom: false, focused: false, hasDraft: true, sending: false, opened: false))
        XCTAssertFalse(ComposerSize.collapsed(atBottom: false, focused: false, hasDraft: false, sending: true, opened: false))
        XCTAssertFalse(ComposerSize.collapsed(atBottom: false, focused: false, hasDraft: false, sending: false, opened: true))
    }

    func testANewReplyDoesNotYankHimDownWhileReading() {
        XCTAssertFalse(ComposerSize.follows(atBottom: false, lastIsMine: false, sending: false))
        XCTAssertTrue(ComposerSize.follows(atBottom: true, lastIsMine: false, sending: false))
        XCTAssertTrue(ComposerSize.follows(atBottom: false, lastIsMine: true, sending: false))
    }
}
