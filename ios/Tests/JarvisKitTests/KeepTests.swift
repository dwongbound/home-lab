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

final class TalkStartTests: XCTestCase {
    /// Selecting the Talk page, opening the app or coming back never calls.
    func testOnlyATapStartsTalk() {
        XCTAssertFalse(TalkStart.starts(.pageShown))
        XCTAssertFalse(TalkStart.starts(.appOpened))
        XCTAssertFalse(TalkStart.starts(.appReturned))
        XCTAssertTrue(TalkStart.starts(.talkTapped))
        XCTAssertTrue(TalkStart.starts(.orbTapped))
    }
}

final class CardStepTests: XCTestCase {
    func testUpGoesBackAndDownGoesOnWrappingRound() {
        // Down (+1) from the last card wraps to the first; up (-1) from the first to the last.
        XCTAssertEqual(CardSwipe.index(turn: 2 + 1, count: 3), 0)
        XCTAssertEqual(CardSwipe.index(turn: 0 - 1, count: 3), 2)
        XCTAssertEqual(CardSwipe.index(turn: -7, count: 3), 2)
        XCTAssertEqual(CardSwipe.index(turn: 5, count: 1), 0)
    }
}

final class TabBarSizeTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testOpenWhileInUseCompactOtherwise() {
        XCTAssertFalse(TabBarSize.expanded(lastInteraction: nil, now: t0, scrollingDown: false, onTalk: false), "rests compact")
        XCTAssertTrue(TabBarSize.expanded(lastInteraction: t0, now: t0.addingTimeInterval(1.5), scrollingDown: false, onTalk: false))
        XCTAssertFalse(TabBarSize.expanded(lastInteraction: t0, now: t0.addingTimeInterval(2.1), scrollingDown: false, onTalk: false), "shrinks after 2 s")
        XCTAssertFalse(TabBarSize.expanded(lastInteraction: t0, now: t0.addingTimeInterval(0.5), scrollingDown: true, onTalk: false), "scrolling down shrinks it at once")
        XCTAssertFalse(TabBarSize.expanded(lastInteraction: t0, now: t0, scrollingDown: false, onTalk: true), "compact on Talk")
    }

    func testScrollDirection() {
        XCTAssertEqual(TabBarSize.isScrollDown(20), true)
        XCTAssertEqual(TabBarSize.isScrollDown(-20), false)
        XCTAssertNil(TabBarSize.isScrollDown(3))
    }
}

final class NightTextTests: XCTestCase {
    func testTheNightWordsAreDim() {
        XCTAssertTrue((0.35...0.45).contains(NightCalm.clockOpacity))
        XCTAssertLessThan(NightCalm.secondaryOpacity, NightCalm.clockOpacity)
    }
}

final class SeenTrackerTests: XCTestCase {
    func testIds() {
        XCTAssertFalse(SeenTracker.hasNew(current: ["a", "b"], seen: nil), "first launch: no dot")
        XCTAssertFalse(SeenTracker.hasNew(current: ["a"], seen: ["a", "b"]), "one went away: nothing new")
        XCTAssertTrue(SeenTracker.hasNew(current: ["a", "c"], seen: ["a", "b"]))
        XCTAssertFalse(SeenTracker.hasNew(current: [], seen: []))
    }

    func testDiet() {
        let now = ISO8601DateFormatter().date(from: "2026-11-19T20:00:00Z")!
        let food = Nutrition(date: "2026-11-19", eaten: 1052, goal: 1750, left: 698)
        let mark = SeenTracker.dietMark(food, now: now)
        XCTAssertEqual(mark, "2026-11-19:1052")
        XCTAssertNil(SeenTracker.dietMark(Nutrition(date: "2026-11-19", eaten: 0, goal: 1750, left: 1750), now: now))
        XCTAssertFalse(SeenTracker.dietHasNew(current: mark, seen: .none), "first launch")
        XCTAssertFalse(SeenTracker.dietHasNew(current: mark, seen: .some(mark)))
        XCTAssertTrue(SeenTracker.dietHasNew(current: mark, seen: .some("2026-11-19:900")), "logged more since")
        XCTAssertTrue(SeenTracker.dietHasNew(current: mark, seen: .some(nil)), "first entry of the day")
        XCTAssertFalse(SeenTracker.dietHasNew(current: nil, seen: .some("2026-11-18:1200")), "nothing logged today")
    }
}
