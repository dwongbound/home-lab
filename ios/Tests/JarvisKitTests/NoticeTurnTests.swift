import XCTest
@testable import JarvisKit

final class NoticeTurnTests: XCTestCase {
    func testNoticesAndHistoryCarryTheTurn() throws {
        let s = try JSONDecoder().decode(Snapshot.self, from: Data(#"{"generatedAt":"x","services":[],"today":[],"notices":[{"id":"n","kind":"heads","title":"Take your vitamins","source":"reminder","created":"","turnId":412}]}"#.utf8))
        XCTAssertEqual(s.notices.first?.turnId, 412)
        XCTAssertEqual(s.notices.first?.clearLabel, "Done")
        XCTAssertEqual(Notice(id: "x", kind: .fyi, title: "", source: "job", created: "").clearLabel, "Dismiss")
        let turns = try JSONDecoder().decode([ChatTurn].self, from: Data(#"[{"role":"user","text":"hi","at":"a","id":410},{"role":"assistant","text":"Vitamins!","at":"b","model":"notice:reminder","id":412}]"#.utf8))
        XCTAssertEqual(ChatTurn.index(of: 412, in: turns), 1)
        XCTAssertNil(ChatTurn.index(of: 999, in: turns))
    }

    func testPushPayloadTurnId() {
        XCTAssertEqual(PushWords.turnId(from: ["turn_id": 412]), 412)
        XCTAssertEqual(PushWords.turnId(from: ["turn_id": "413"]), 413)
        XCTAssertEqual(PushWords.turnId(from: ["jarvis": ["turn_id": 414]]), 414)
        XCTAssertNil(PushWords.turnId(from: [:]))
    }

    func testNoticeChipsAreWords() {
        XCTAssertTrue(ModelWording.isNotice("notice:reminder"))
        XCTAssertEqual(ModelWording.label("notice:reminder"), "Reminder")
        XCTAssertEqual(ModelWording.label("notice:lookout"), "Lookout")
        XCTAssertEqual(ModelWording.label("notice:job"), "Finished")
        XCTAssertEqual(ModelWording.label("notice:start_of_day"), "Jarvis")
        XCTAssertFalse(ModelWording.isNotice("claude-opus-5-5"))
        XCTAssertEqual(ModelWording.label("claude-opus-5-5"), "Jarvis (CO)")
    }
}
