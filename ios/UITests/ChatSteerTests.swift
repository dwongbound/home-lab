// Sending while Jarvis is still answering (Dylan, 2026-11-21: "i should be
// able to send more than one message even while claude is thinking (and it
// should steer it)"). The fixture transport (-fixtureChat) thinks for twenty
// seconds before answering; a second send meanwhile is steered, or with
// -fixtureQueue queued and answered after. Nothing reaches Jarvis.
import XCTest

final class ChatSteerTests: XCTestCase {
    private func launch(queue: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-jarvis.server", "http://127.0.0.1:9", "-openChat", "-demoChat", "-fixtureChat", "-push.enabled", "NO", "-resetDraft"] + (queue ? ["-fixtureQueue"] : [])
        app.launch()
        return app
    }

    private func send(_ app: XCUIApplication, _ words: String) {
        let box = app.descendants(matching: .any)["composer"]
        XCTAssertTrue(box.waitForExistence(timeout: 20))
        box.tap()
        box.typeText(words)
        for _ in 0..<3 {
            app.buttons["sendButton"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            if !((box.value as? String) ?? "").contains(words.prefix(3)) { break }
            usleep(300_000)
        }
    }

    /// The bubbles of his, lowest last.
    private func userTexts(_ app: XCUIApplication) -> [String] {
        app.descendants(matching: .any).matching(identifier: "userBubble").allElementsBoundByIndex
            .filter { $0.frame.height > 0 }
            .sorted { $0.frame.minY < $1.frame.minY }
            .map(\.label)
    }

    /// A second message while the first is being answered: the box takes
    /// it, it shows at once, and once steered it sits above the one reply.
    func testASecondMessageSteers() {
        let app = launch(queue: false)
        sleep(2)
        send(app, "What's the weather tomorrow")
        sleep(3)
        send(app, "Also check Sunday")
        sleep(2)
        let texts = userTexts(app)
        XCTAssertEqual(Array(texts.suffix(2)), ["What's the weather tomorrow", "Also check Sunday"], "both show, in order")
        // The first reply arrives on the first stream, under both.
        let reply = app.descendants(matching: .any).matching(identifier: "jarvisBubble").allElementsBoundByIndex.last
        sleep(22)
        let lastUser = app.descendants(matching: .any).matching(identifier: "userBubble").allElementsBoundByIndex.filter { $0.label == "Also check Sunday" }.first
        let replies = app.descendants(matching: .any).matching(identifier: "jarvisBubble").allElementsBoundByIndex.filter { $0.label.contains("sunny tomorrow") }
        XCTAssertEqual(replies.count, 1, "one reply, no empty bubble for the steered message")
        if let lastUser, let r = replies.first { XCTAssertLessThan(lastUser.frame.minY, r.frame.minY, "the steered message sits above the reply") }
        _ = reply
    }

    /// Queued: "Queued" under it until its own reply starts, then it moves
    /// into its own turn with that reply under it.
    func testASecondMessageQueues() {
        let app = launch(queue: true)
        sleep(2)
        send(app, "What's the weather tomorrow")
        sleep(3)
        send(app, "And set a reminder")
        XCTAssertTrue(app.staticTexts["Queued"].waitForExistence(timeout: 5), "Queued shows under it")
        sleep(30)
        XCTAssertFalse(app.staticTexts["Queued"].exists, "gone once its reply started")
        let second = app.descendants(matching: .any).matching(identifier: "jarvisBubble").allElementsBoundByIndex.filter { $0.label.contains("second thing") }
        XCTAssertEqual(second.count, 1)
        let mine = app.descendants(matching: .any).matching(identifier: "userBubble").allElementsBoundByIndex.filter { $0.label == "And set a reminder" }.first
        let first = app.descendants(matching: .any).matching(identifier: "jarvisBubble").allElementsBoundByIndex.filter { $0.label.contains("sunny tomorrow") }.first
        if let mine, let first, let reply = second.first {
            XCTAssertLessThan(first.frame.minY, mine.frame.minY, "its own turn, after the first reply")
            XCTAssertLessThan(mine.frame.minY, reply.frame.minY)
        }
    }
}
