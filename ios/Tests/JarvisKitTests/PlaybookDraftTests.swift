import XCTest
@testable import JarvisKit

final class PlaybookDraftTests: XCTestCase {
    /// A GET /api/jarvis/playbooks answer as recorded tonight, plus a fuller
    /// playbook with every field and step kind.
    private let fixture = #"""
    {"book":{"playbooks":[
      {"id":"arrive-home","name":"Arrive home","enabled":true,"purpose":"","whenToUse":"","trigger":{"type":"arrive","zone":"home","minAway":15},"inputs":[],"steps":[{"type":"app","entity":"media_player.bedroom_dylans_rokm","app":"Jarvis"}],"decisions":[],"done":[],"edgeCases":[],"standard":"","badVersion":"","madeBy":"dylan","lastRun":{"at":"2026-11-19T01:47:02-08:00","ok":false,"detail":"1 of 1 steps failed","checks":[]}},
      {"id":"bedtime","name":"Bedtime","enabled":false,"purpose":"Wind down","whenToUse":"When I say goodnight","trigger":{"type":"time","at":"22:30","days":["mon","tue"]},
       "inputs":[{"name":"Lights","where":"Home Assistant"}],
       "steps":[{"type":"device","entity":"climate.bedroom","command":"set_temperature","value":67},{"type":"device","entity":"climate.bedroom","command":"set_hvac_mode","value":"cool"},{"type":"device","entity":"light.desk","command":"turn_off"},{"type":"scene","entity":"scene.night"},{"type":"notify","text":"Night"},{"type":"think","text":"Check tomorrow","model":"claude"},{"type":"email","to":"a@b.co, c@d.co","subject":"Hi","body":"Body","confirm":true},{"type":"wait","seconds":90}],
       "decisions":[{"if":"raining","then":"close blinds"}],"done":["Lights off"],"edgeCases":["TV asleep"],"standard":"Quiet","badVersion":"Loud","madeBy":"jarvis"}
    ],"options":{"devices":[{"entity":"climate.bedroom","name":"Bedroom","kind":"climate","commands":["set_temperature","set_hvac_mode"]},{"entity":"light.desk","name":"Desk","kind":"light","commands":["turn_on","turn_off"]}],"scenes":[{"entity":"scene.night","name":"Night"}],"apps":[{"entity":"media_player.bedroom_dylans_rokm","name":"Dylans Apple TV","apps":["Jarvis","Netflix"]}],"zones":["home"]}}}
    """#

    /// The page saves draftOf(playbook): the GET object without lastRun and madeBy.
    private func pageDraft(_ object: [String: Any]) -> NSDictionary {
        var o = object
        o.removeValue(forKey: "lastRun")
        o.removeValue(forKey: "madeBy")
        return o as NSDictionary
    }

    func testEveryFieldRoundTripsToThePagesSaveShape() throws {
        let book = try XCTUnwrap(Playbooks.book(from: Data(fixture.utf8)))
        for raw in book.raw {
            let draft = PlaybookDraft(json: raw)
            XCTAssertEqual(draft.json as NSDictionary, pageDraft(raw), "save body for \(raw["id"] ?? "")")
            XCTAssertNil(draft.problem)
        }
    }

    func testTheSwitchSavesThePagesShapeToo() throws {
        let list = try XCTUnwrap(Playbooks.list(from: Data(fixture.utf8)))
        let book = try XCTUnwrap(Playbooks.book(from: Data(fixture.utf8)))
        var expected = pageDraft(book.raw[0]) as! [String: Any]
        expected["enabled"] = false
        XCTAssertEqual(list[0].draft(enabled: false) as NSDictionary, expected as NSDictionary)
    }

    func testOptionsAndLines() throws {
        let options = try XCTUnwrap(Playbooks.book(from: Data(fixture.utf8))).options
        XCTAssertEqual(options.apps.first?.apps, ["Jarvis", "Netflix"])
        XCTAssertEqual(DraftStep.app(entity: "media_player.bedroom_dylans_rokm", app: "Jarvis").line(options), "Open Jarvis on Dylans Apple TV")
        XCTAssertEqual(DraftStep.device(entity: "climate.bedroom", command: "set_temperature", value: "67").line(options), "Bedroom: set temperature to 67")
        XCTAssertEqual(DraftStep.device(entity: "light.desk", command: "turn_off", value: "").line(options), "Turn off: Desk")
        XCTAssertEqual(DraftStep.wait(seconds: 120).line(options), "Wait 2 min")
        XCTAssertEqual(DraftStep.blank("app", options: options), .app(entity: "media_player.bedroom_dylans_rokm", app: "Jarvis"))
    }

    func testWhatsMissing() {
        var draft = PlaybookDraft()
        XCTAssertEqual(draft.problem, "Give the playbook a name")
        draft.name = "Movie night"
        XCTAssertEqual(draft.problem, "Add at least one step")
        draft.trigger = DraftTrigger(type: "time", at: "25:00")
        XCTAssertEqual(draft.problem, "Pick a time")
        draft.trigger = DraftTrigger.blank("time")
        draft.steps = [.device(entity: "climate.bedroom", command: "set_temperature", value: "")]
        XCTAssertEqual(draft.problem, "Step 1: give it a value")
        draft.steps = [.email(to: "nope", subject: "s", body: "b", confirm: false)]
        XCTAssertEqual(draft.problem, "Step 1: check the email address")
        draft.steps = [.wait(seconds: 900)]
        XCTAssertEqual(draft.problem, "Step 1: wait between 1 and 600 seconds")
        draft.steps = [.notify(text: "Popcorn time")]
        XCTAssertNil(draft.problem)
        XCTAssertNil(draft.json["id"], "a new playbook has no id")
    }
}
