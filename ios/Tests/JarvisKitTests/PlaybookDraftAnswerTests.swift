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
        XCTAssertEqual(draft.steps.map { $0.json as NSDictionary },
                       [["type": "device", "entity": "light.desk", "command": "turn_off"], ["type": "notify", "text": "Lights are off"]] as [NSDictionary])
        XCTAssertEqual(draft.done, ["Every light is off"])
        XCTAssertEqual(assumed, ["You meant the desk lamp"])
        var options = PlaybookOptions()
        options.devices = [.init(entity: "light.desk", name: "Desk lamp", kind: "light", commands: ["turn_on", "turn_off"])]
        XCTAssertNil(draft.problem(options))
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

    /// Rows read from each kind's summary pattern, as on the page (stepLine).
    func testStepRowsReadAsSentences() {
        let options = PlaybookOptions(json: ["devices": [["entity": "light.desk", "name": "Desk lamp", "kind": "light", "commands": ["turn_on", "turn_off"]]]])
        func line(_ json: [String: Any]) -> String { DraftStep(json: json)!.sentence(options) }
        XCTAssertEqual(line(["type": "device", "entity": "light.desk", "command": "turn_off"]), "Desk lamp: turn off")
        XCTAssertEqual(line(["type": "device", "entity": "light.desk", "command": "turn_on", "value": 40]), "Desk lamp: turn on 40")
        XCTAssertEqual(line(["type": "wait", "seconds": 120]), "Wait 120 s")
        XCTAssertEqual(line(["type": "notify", "text": "Popcorn"]), "Notify me: Popcorn")
        XCTAssertEqual(line(["type": "think", "text": "Plan it", "model": "auto"]), "Jarvis: Plan it")
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

final class NoticeActionTests: XCTestCase {
    private func notice(_ source: String = "jarvis", approval: String? = nil, turn: Int? = 5) -> Notice {
        Notice(id: "n1", kind: .heads, title: "T", source: source, created: "2026-11-19T10:00:00Z", approvalId: approval, turnId: turn)
    }

    /// The card's buttons are one or two words (Dylan, 2026-11-19).
    func testCardLabelsAreShort() {
        for action in NoticeAction.allCases where action != .seeInChat {
            XCTAssertLessThanOrEqual(action.label.split(separator: " ").count, 2, action.label)
        }
        XCTAssertEqual(notice("reminder").clearLabel, "Done")
        XCTAssertEqual(notice().clearLabel, "Dismiss")
    }

    func testEachKindGetsItsButtons() {
        XCTAssertEqual(NoticeAction.card(kind: .notice, notice: notice(approval: "a1"), canOpen: true, canDismiss: true), [.deny, .approve])
        XCTAssertEqual(NoticeAction.card(kind: .notice, notice: notice("reminder"), canOpen: true, canDismiss: true), [.keep, .seeMore, .done])
        XCTAssertEqual(NoticeAction.card(kind: .notice, notice: notice(), canOpen: true, canDismiss: true), [.dismiss, .keep, .seeMore])
        XCTAssertEqual(NoticeAction.card(kind: .notice, notice: notice(turn: nil), canOpen: false, canDismiss: true), [.dismiss, .keep])
        XCTAssertEqual(NoticeAction.card(kind: .kept, notice: notice(), canOpen: true, canDismiss: false), [.unkeep, .seeMore])
        XCTAssertEqual(NoticeAction.card(kind: .task, notice: nil, canOpen: true, canDismiss: false), [.open])
    }
}

final class PendingClearsTests: XCTestCase {
    /// A swiped notice disappears at once and comes back if the server didn't take it.
    func testHideThenRollBack() {
        let a = Notice(id: "a", kind: .heads, title: "A", source: "job", created: "")
        let b = Notice(id: "b", kind: .fyi, title: "B", source: "job", created: "")
        var pending = PendingClears()
        pending.hide(["a"])
        XCTAssertEqual(pending.visible([a, b]).map(\.id), ["b"])
        pending.restore(["a"])
        XCTAssertEqual(pending.visible([a, b]).map(\.id), ["a", "b"])
    }
}
