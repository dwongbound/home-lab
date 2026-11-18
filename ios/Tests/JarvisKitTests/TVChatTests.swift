import XCTest
@testable import JarvisKit

final class TVChatTests: XCTestCase {
    func testATurnStreamsIntoOneReplyBubble() {
        var chat = TVChat()
        XCTAssertEqual(chat.send("  what's the weather  "), "what's the weather")
        XCTAssertEqual(chat.phase, .thinking)
        XCTAssertNil(chat.send("again"), "one question at a time")
        chat.apply(.working("Checking the forecast."))
        XCTAssertEqual(chat.working, "Checking the forecast.")
        chat.apply(.delta("Cloudy, "))
        chat.apply(.delta("61°F."))
        chat.apply(.done)
        chat.finish()
        XCTAssertEqual(chat.lines.map(\.who), [.me, .jarvis])
        XCTAssertEqual(chat.lines.last?.text, "Cloudy, 61°F.")
        XCTAssertEqual(chat.lastReply, "Cloudy, 61°F.")
        XCTAssertNil(chat.working)
        XCTAssertEqual(chat.phase, .idle)
    }

    func testTheConversationContinuesTurnAfterTurn() {
        var chat = TVChat()
        _ = chat.send("one"); chat.apply(.delta("first")); chat.finish()
        _ = chat.send("two"); chat.apply(.delta("second")); chat.finish()
        XCTAssertEqual(chat.lines.map(\.text), ["one", "first", "two", "second"])
    }

    func testApprovalsAreTheirOwnLineAndBlockClosing() {
        var chat = TVChat()
        _ = chat.send("turn off the lights")
        chat.apply(.approval(Approval(id: "a1", tool: "home_service", summary: "light.turn_off", expires: "")))
        chat.apply(.delta("Asked for your OK."))
        chat.finish()
        XCTAssertEqual(chat.lines.count, 3)
        XCTAssertTrue(chat.approvalWaiting)
        let long = Date(timeIntervalSince1970: 0)
        XCTAssertFalse(chat.shouldClose(lastActivity: long, now: long.addingTimeInterval(120)))
        chat.settle("a1", "Approved")
        XCTAssertTrue(chat.shouldClose(lastActivity: long, now: long.addingTimeInterval(61)))
        XCTAssertFalse(chat.shouldClose(lastActivity: long, now: long.addingTimeInterval(30)))
    }

    func testAnEmptyReplyLeavesNoBubbleAndSeedsOnlyOnce() {
        var chat = TVChat()
        chat.seed([ChatTurn(role: "user", text: "hi", at: "", model: nil), ChatTurn(role: "assistant", text: "Hello.", at: "", model: nil)])
        chat.seed([ChatTurn(role: "user", text: "again", at: "", model: nil)])
        XCTAssertEqual(chat.lines.map(\.text), ["hi", "Hello."])
        _ = chat.send("x")
        chat.apply(.delta(""))
        chat.finish(error: "Jarvis answered 500")
        XCTAssertEqual(chat.lines.last?.text, "x")
        XCTAssertEqual(chat.problem, "Jarvis answered 500")
    }
}
