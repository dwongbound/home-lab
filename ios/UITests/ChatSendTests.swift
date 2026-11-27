// Sending in Chat (Dylan, 2026-11-20: "it scrolls down way too much after i
// hit enter.. it should pop into the space like a normal text
// conversation"): his bubble lands just above the box, the usual small gap
// away, and Jarvis's reply does too as it streams. The fixture transport
// (-fixtureChat) thinks for twenty seconds (XCUITest takes several to read the
// screen), then answers; nothing reaches Jarvis.
import XCTest

final class ChatSendTests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-jarvis.server", "http://127.0.0.1:9", "-openChat", "-demoChat", "-fixtureChat", "-push.enabled", "NO", "-resetDraft"]
        app.launch()
        return app
    }

    /// How far above the Ask field the lowest bubble on screen ends.
    private func gap(_ app: XCUIApplication) -> CGFloat {
        let field = app.descendants(matching: .any)["composer"].frame
        // The query's order isn't the screen's: take the lowest one.
        var lowest: CGFloat = 0
        for kind in ["userBubble", "jarvisBubble"] {
            for element in app.descendants(matching: .any).matching(identifier: kind).allElementsBoundByIndex {
                let frame = element.frame
                if frame.height > 0, frame.maxY < field.maxY + 300 { lowest = max(lowest, frame.maxY) }
            }
        }
        return field.minY - lowest
    }

    /// Types, sends, and answers the gap before, just after sending (while
    /// Jarvis is still thinking) and once the reply has streamed in.
    private func send(_ app: XCUIApplication, _ words: String, keyboardDown: Bool = false, readingUp: Bool = false)
        -> (before: CGFloat, sent: CGFloat, replied: CGFloat) {
        let box = app.descendants(matching: .any)["composer"]
        XCTAssertTrue(box.waitForExistence(timeout: 20))
        sleep(2)
        box.tap()
        box.typeText(words)
        sleep(1)
        let before = gap(app)
        if readingUp {
            app.scrollViews["chatList"].swipeDown(velocity: .slow)
            sleep(1)
        }
        // A coordinate tap: XCUITest's element tap here was taken by its
        // own interruption check, and a first tap right after typing is
        // sometimes eaten too, so tap until the box has emptied.
        for _ in 0..<3 {
            app.buttons["sendButton"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            if !((box.value as? String) ?? "").contains(words.prefix(3)) { break }
            usleep(300_000)
        }
        if keyboardDown {
            // Down, as when he drags the chat.
            app.scrollViews["chatList"].swipeDown(velocity: .slow)
            app.scrollViews["chatList"].swipeUp(velocity: .slow)
        }
        usleep(500_000)
        shot("send-\(words.count)-sent")
        let sent = gap(app)
        sleep(25)
        let replied = gap(app)
        shot("send-\(words.count)-replied")
        print("SENDGAP", words.count, keyboardDown, readingUp, before, sent, replied)
        return (before, sent, replied)
    }

    /// Saves a screenshot when the run asks for them (TEST_RUNNER_SHOTS_DIR).
    private func shot(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"] else { return }
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    /// Both bubbles end the usual small gap above the box. His bubble's
    /// frame runs a little lower than Jarvis's (whose last line before
    /// sending is the baseline), so his is held to "no further up than
    /// that"; the reply, like for like, to the same gap within a few points.
    /// Before the fix his bubble sat about 90 pt further up.
    private func check(_ g: (before: CGFloat, sent: CGFloat, replied: CGFloat), file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThan(g.before, 0, file: file, line: line)
        XCTAssertGreaterThan(g.sent, 10, "his bubble mustn't run under the box", file: file, line: line)
        XCTAssertLessThanOrEqual(g.sent, g.before + 6, "his bubble should land just above the box, not \(Int(g.sent - g.before)) pt further up", file: file, line: line)
        XCTAssertEqual(g.replied, g.before, accuracy: 6, "the reply should end just above the box, not \(Int(g.replied - g.before)) pt further up", file: file, line: line)
    }

    func testAOneLineMessageLandsJustAboveTheBox() {
        check(send(launch(), "Hello there"))
    }

    func testAFiveLineMessageLandsJustAboveTheBox() {
        check(send(launch(), "One\nTwo\nThree\nFour\nFive"))
    }

    func testWithTheKeyboardDownItStillLandsJustAboveTheBox() {
        check(send(launch(), "Hello there", keyboardDown: true))
    }

    func testSentAfterScrollingUpItLandsJustAboveTheBox() {
        check(send(launch(), "Hello there", readingUp: true))
    }
}
