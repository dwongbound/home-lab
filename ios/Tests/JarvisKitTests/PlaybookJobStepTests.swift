// Job steps and step kinds the app doesn't know (Jarvis build 83, the
// nightly self-improvement playbook): they decode, show, and go back on a
// save exactly as they came, in their place. Fixture JSON only.
import XCTest
@testable import JarvisKit

final class PlaybookJobStepTests: XCTestCase {
    private let book = #"""
    {"book": {
      "playbooks": [
        {"id": "nightly", "name": "Nightly self-improvement", "enabled": true, "madeBy": "dylan",
         "purpose": "Jarvis's nightly pass", "trigger": {"type": "time", "at": "03:30", "days": [], "window": 20},
         "steps": [
           {"type": "notify", "text": "Starting the nightly pass"},
           {"type": "job", "job": "nightly", "note": "keep me"},
           {"type": "teleport", "where": "moon", "speed": 3},
           {"type": "wait", "seconds": 60}
         ],
         "owner": "jarvis",
         "lastRun": {"at": "2026-11-20T03:30:00Z", "ok": true, "detail": "done"}}
      ],
      "options": {"devices": [], "scenes": [], "apps": [], "zones": ["home"],
                  "jobs": [{"id": "nightly", "name": "Nightly self-improvement"}]}
    }}
    """#

    private func parsed() throws -> (raw: [[String: Any]], options: PlaybookOptions) {
        try XCTUnwrap(Playbooks.book(from: Data(book.utf8)))
    }

    func testTheNightlyPlaybookDecodesWithItsJobStep() throws {
        let list = try XCTUnwrap(Playbooks.list(from: Data(book.utf8)))
        XCTAssertEqual(list.map(\.id), ["nightly"])
        let draft = list[0].draft
        XCTAssertEqual(draft.steps.count, 4, "no step may be dropped")
        XCTAssertEqual(draft.steps[1].type, "job")
        let (_, options) = try parsed()
        XCTAssertEqual(draft.steps[1].sentence(options), "Run: Nightly self-improvement")
        XCTAssertNil(draft.steps[1].problem(options))
    }

    func testAnUnknownStepKindDecodesAndShowsAsARow() throws {
        let draft = try XCTUnwrap(Playbooks.list(from: Data(book.utf8)))[0].draft
        XCTAssertEqual(draft.steps[2].type, "teleport")
        XCTAssertNil(draft.steps[2].problem(PlaybookOptions()), "an unknown step never blocks a save")
        XCTAssertEqual(draft.steps[2].sentence(PlaybookOptions()), "Teleport")
    }

    func testOptionsWithoutJobsFallBackToTheId() {
        let options = PlaybookOptions(json: ["devices": []])
        XCTAssertTrue(options.jobs.isEmpty)
        let step = DraftStep(json: ["type": "job", "job": "nightly"])
        XCTAssertEqual(step?.sentence(options), "Run: nightly")
    }

    /// A save sends the job step and the unknown step back unchanged, every
    /// field, in the same places, along with fields the editor doesn't hold.
    func testJobAndUnknownStepsRoundTripUnchanged() throws {
        let (raw, _) = try parsed()
        let sent = PlaybookDraft(json: raw[0]).json
        let steps = try XCTUnwrap(sent["steps"] as? [[String: Any]])
        XCTAssertEqual(steps.count, 4)
        XCTAssertEqual(steps.map { $0["type"] as? String }, ["notify", "job", "teleport", "wait"])
        XCTAssertEqual(steps[1] as NSDictionary, ["type": "job", "job": "nightly", "note": "keep me"] as NSDictionary)
        XCTAssertEqual(steps[2] as NSDictionary, ["type": "teleport", "where": "moon", "speed": 3] as NSDictionary)
        // Fields the editor doesn't model ride along; what Jarvis keeps doesn't.
        XCTAssertEqual(sent["owner"] as? String, "jarvis")
        XCTAssertNil(sent["lastRun"])
        XCTAssertNil(sent["madeBy"])
        let trigger = try XCTUnwrap(sent["trigger"] as? [String: Any])
        XCTAssertEqual(trigger["at"] as? String, "03:30")
        XCTAssertEqual(trigger["window"] as? Int, 20)
    }

    func testChoosingAnotherJobKeepsTheStepsOtherFields() throws {
        let step = try XCTUnwrap(DraftStep(json: ["type": "job", "job": "nightly", "note": "keep me"]))
        let changed = step.with("job", .text("weekly"), options: PlaybookOptions()).json
        XCTAssertEqual(changed as NSDictionary, ["type": "job", "job": "weekly", "note": "keep me"] as NSDictionary)
    }

    /// The list's on/off switch already sent the playbook back whole.
    func testTheSwitchKeepsEveryStep() throws {
        let playbook = try XCTUnwrap(Playbooks.list(from: Data(book.utf8)))[0]
        let sent = playbook.draft(enabled: false)
        XCTAssertEqual((sent["steps"] as? [[String: Any]])?.count, 4)
        XCTAssertEqual(sent["enabled"] as? Bool, false)
    }
}
