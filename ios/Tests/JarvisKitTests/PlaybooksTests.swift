import XCTest
@testable import JarvisKit

final class PlaybooksTests: XCTestCase {
    private let body = #"""
    {"book":{"playbooks":[
      {"id":"night","name":"Bedtime","enabled":true,"purpose":"Wind the room down","whenToUse":"","trigger":{"type":"asleep"},"inputs":[],"steps":[{"type":"scene","entity":"scene.night"}],"decisions":[],"done":["Every light is off"],"edgeCases":[],"standard":"","badVersion":"","madeBy":"dylan",
       "lastRun":{"at":"2026-11-18T23:40:00-08:00","ok":false,"detail":"Ran 1 step","checks":[{"item":"Every light is off","ok":false,"why":"the porch lights were still on"},{"item":"TV off","ok":true,"why":""}]}},
      {"id":"morning","name":"Morning","enabled":false,"trigger":{"type":"time","at":"07:05","days":["mon","tue","wed","thu","fri"]},"steps":[]},
      {"name":"no id"}
    ],"options":{}}}
    """#

    func testTheBookDecodes() throws {
        let list = try XCTUnwrap(Playbooks.list(from: Data(body.utf8)))
        XCTAssertEqual(list.map(\.id), ["night", "morning"])
        XCTAssertEqual(Playbooks.triggerLine(list[0].trigger), "When I go to sleep")
        XCTAssertEqual(Playbooks.triggerLine(list[1].trigger), "At 7:05 AM, weekdays")
        XCTAssertEqual(Playbooks.notDone(list[0].lastRun?.checks ?? []), ["Not done: Every light is off: the porch lights were still on"])
        XCTAssertEqual(Playbooks.tileLine(list), "1 on")
        XCTAssertNil(Playbooks.list(from: Data(#"{"book":null}"#.utf8)))
    }

    func testSavingChangesOnlyEnabled() throws {
        let list = try XCTUnwrap(Playbooks.list(from: Data(body.utf8)))
        let draft = list[0].draft(enabled: false)
        XCTAssertEqual(draft["enabled"] as? Bool, false)
        XCTAssertNil(draft["lastRun"])
        XCTAssertNil(draft["madeBy"])
        XCTAssertEqual(draft["done"] as? [String], ["Every light is off"])
        XCTAssertEqual((draft["steps"] as? [[String: Any]])?.first?["entity"] as? String, "scene.night")
    }

    func testWording() {
        XCTAssertEqual(Playbooks.clockLabel("00:15"), "12:15 AM")
        XCTAssertEqual(Playbooks.clockLabel("13:00"), "1:00 PM")
        XCTAssertEqual(Playbooks.daysLabel([]), "every day")
        XCTAssertEqual(Playbooks.daysLabel(["sat", "sun"]), "weekends")
        XCTAssertEqual(Playbooks.daysLabel(["wed", "mon"]), "Mon, Wed")
        XCTAssertEqual(Playbooks.triggerLine(PlaybookTrigger(type: "arrive", minAway: 30)), "When I get home after 30 min away")
        XCTAssertEqual(Playbooks.triggerLine(PlaybookTrigger(type: "manual")), "When I ask, or the job comes up")
        XCTAssertEqual(Playbooks.tileLine([]), "No playbooks")
    }

    func testResults() {
        let r = PlaybookResult(json: ["ok": true, "detail": "running"])
        XCTAssertTrue(r.ok)
        XCTAssertEqual(r.detail, "running")
        XCTAssertEqual(PlaybookResult(json: ["ok": false, "message": "Give the playbook a name"]).detail, "Give the playbook a name")
    }
}

final class PlaybookTroubleTests: XCTestCase {
    func testRunWords() {
        XCTAssertEqual(PlaybookTrouble.runWords("1 of 1 steps failed: 1. app: Home Assistant refused it (500): pyatv.exceptions.ProtocolError: Command _launchApp failed"), "The TV refused to open the app. Open it once on the TV, then try again.")
        XCTAssertEqual(PlaybookTrouble.runWords("… Command _hidC failed"), "The TV didn't answer. It may have been asleep; try again.")
        XCTAssertNil(PlaybookTrouble.runWords("Ran 3 steps"))
    }

    func testSaveWords() {
        XCTAssertEqual(PlaybookTrouble.saveWords("a playbook needs at least one step", hasSteps: true), "Jarvis couldn't save this just now. Try again in a minute.")
        XCTAssertEqual(PlaybookTrouble.saveWords("a playbook needs at least one step", hasSteps: false), "a playbook needs at least one step")
        XCTAssertEqual(PlaybookTrouble.saveWords("", hasSteps: true), "Jarvis didn't save it.")
    }
}
