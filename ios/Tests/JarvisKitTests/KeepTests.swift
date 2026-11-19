import XCTest
@testable import JarvisKit

final class KeepTests: XCTestCase {
    private func decode(_ json: String) throws -> Notice {
        try JSONDecoder().decode(Notice.self, from: Data(json.utf8))
    }

    func testKeptIsOptionalAndDefaultsOff() throws {
        XCTAssertFalse(try decode(#"{"id":"a","kind":"heads","title":"x"}"#).kept)
        XCTAssertTrue(try decode(#"{"id":"b","kind":"fyi","title":"Matthew replied","source":"kept","turnId":412,"kept":true}"#).kept)
    }

    func testKeptItemsAreYellowNotUnread() throws {
        let unread = Notice(id: "a", kind: .heads, title: "New", source: "lookout", created: "")
        // A kept former need stays yellow, not orange, whatever its kind.
        let keptNeed = Notice(id: "b", kind: .need, title: "Kept", source: "lookout", created: "", kept: true)
        let keptChat = Notice(id: "c", kind: .fyi, title: "Lesson moved", source: "kept", created: "", turnId: 9, kept: true)
        let all = [unread, keptNeed, keptChat]
        XCTAssertEqual(Notices.unread(all).map(\.id), ["a"])
        XCTAssertEqual(Notices.countLabel(Notices.unread(all)), "1 new")
        XCTAssertEqual(Notices.headerDot(Notices.unread(all)), .heads)
        let dots = Orbit.items(running: [], notices: all)
        XCTAssertEqual(dots.map(\.kind), [.notice, .kept, .kept])
        XCTAssertTrue(Orbit.items(running: [], notices: all, night: true).allSatisfy { $0.kind != .kept }, "none at night")
        XCTAssertEqual(Notices.kept(turnId: 9, in: all)?.id, "c")
        XCTAssertNil(Notices.kept(turnId: 10, in: all))
        XCTAssertFalse(Orbit.readOnView(keptChat), "seeing a kept item never clears it")
        XCTAssertFalse(Orbit.offersKeep(keptChat))
    }

    func testKeepAnswers() {
        let ok = KeepResult.read(status: 200, data: Data(#"{"ok":true,"message":"Kept","notice":{"id":"k1","kind":"fyi","title":"x","kept":true,"turnId":3}}"#.utf8))
        XCTAssertTrue(ok.ok)
        XCTAssertEqual(ok.notice?.id, "k1")
        let plain = KeepResult.read(status: 200, data: Data(#"{"ok":true,"message":"Let go"}"#.utf8))
        XCTAssertTrue(plain.ok)
        XCTAssertNil(plain.notice)
        let refused = KeepResult.read(status: 409, data: Data(#"{"ok":false,"message":"Jarvis can't find that message"}"#.utf8))
        XCTAssertFalse(refused.ok)
        XCTAssertEqual(refused.message, "Jarvis can't find that message")
    }

    func testHistoryTurnsCarryKept() throws {
        let turn = try JSONDecoder().decode(ChatTurn.self, from: Data(#"{"id":9,"role":"assistant","text":"x","at":"","kept":true}"#.utf8))
        XCTAssertEqual(turn.kept, true)
        XCTAssertNil(try JSONDecoder().decode(ChatTurn.self, from: Data(#"{"role":"assistant","text":"x","at":""}"#.utf8)).kept)
    }
}

final class KindWordsTests: XCTestCase {
    func testTheKindInWords() {
        XCTAssertEqual(Notices.kindWords(Notice(id: "a", kind: .fyi, title: "x", source: "kept", created: "", kept: true)), "Kept")
        XCTAssertEqual(Notices.kindWords(Notice(id: "b", kind: .need, title: "x", source: "approval", created: "")), "Needs you")
        XCTAssertEqual(Notices.kindWords(Notice(id: "c", kind: .heads, title: "x", source: "reminder", created: "")), "Reminder")
        XCTAssertEqual(Notices.kindWords(Notice(id: "d", kind: .heads, title: "x", source: "lookout", created: "")), "Heads up")
    }
}

final class TalkSettleTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testPassingThroughTalkDoesNotCall() {
        // Swiped on to Chat 0.3 s later: no longer on Talk.
        XCTAssertFalse(TalkSettle.shouldStart(onTalk: false, landedAt: t0, now: t0.addingTimeInterval(0.7), started: false))
        // Still settling.
        XCTAssertFalse(TalkSettle.shouldStart(onTalk: true, landedAt: t0, now: t0.addingTimeInterval(0.3), started: false))
    }

    func testStayingOnTalkCallsOnce() {
        XCTAssertTrue(TalkSettle.shouldStart(onTalk: true, landedAt: t0, now: t0.addingTimeInterval(0.7), started: false))
        XCTAssertFalse(TalkSettle.shouldStart(onTalk: true, landedAt: t0, now: t0.addingTimeInterval(5), started: true), "already called")
    }
}
