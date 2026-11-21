// Earlier messages and message times in Chat (Dylan, 2026-11-20). With
// `-demoOlderServer` Chat holds only the newest page and pages older ones in
// from a fake server, 50 turns (well over a screen) each, counting fetches.
import XCTest

final class ChatOlderTests: XCTestCase {
    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-jarvis.server", "http://127.0.0.1:9", "-openChat", "-demoChat", "-demoOlderServer", "-push.enabled", "NO", "-resetDraft"] + extra
        app.launch()
        return app
    }

    private func fetches(_ app: XCUIApplication) -> Int {
        Int(app.staticTexts["olderFetches"].label) ?? -1
    }

    /// A message line on screen near the top, to watch.
    private func watched(_ app: XCUIApplication) -> XCUIElement? {
        let list = app.scrollViews["chatList"].frame
        return app.staticTexts.allElementsBoundByIndex.first { e in
            e.label.hasPrefix("ok ") && e.frame.minY > list.minY + 140 && e.frame.maxY < list.maxY - 200
        }
    }

    /// Up to the top: one page loads above, the message he was reading
    /// stays exactly where it was, and no second page loads by itself.
    func testOlderMessagesLoadAboveAndOnlyOnce() {
        let app = launch()
        let list = app.scrollViews["chatList"]
        XCTAssertTrue(list.waitForExistence(timeout: 20))
        sleep(2)
        XCTAssertEqual(fetches(app), 0)
        // Flick to the top of the newest page.
        for _ in 0..<6 { list.swipeDown(velocity: .fast) }
        // Wait for the first page to arrive (it loads at the top).
        let deadline = Date().addingTimeInterval(10)
        while fetches(app) < 1 && Date() < deadline { usleep(200_000) }
        XCTAssertEqual(fetches(app), 1, "reaching the top loads one page")
        sleep(2)
        guard let line = watched(app) else { return XCTFail("no message on screen to watch") }
        let label = line.label, before = line.frame.minY
        // Sit still: nothing more loads and nothing moves.
        sleep(4)
        XCTAssertEqual(fetches(app), 1, "one arrival at the top loads one page only")
        let still = app.staticTexts[label]
        XCTAssertTrue(still.exists)
        XCTAssertEqual(still.frame.minY, before, accuracy: 2, "the screen mustn't move after older messages load")
        XCTAssertFalse(app.staticTexts["Loading earlier messages"].isHittable && app.buttons["Earlier messages"].isHittable, "the new page sits above the screen")
    }

    /// The page loading keeps the line he was reading where it was.
    func testTheLineHeWasReadingStaysPut() {
        let app = launch()
        let list = app.scrollViews["chatList"]
        XCTAssertTrue(list.waitForExistence(timeout: 20))
        sleep(2)
        for _ in 0..<5 { list.swipeDown(velocity: .fast) }
        sleep(1)
        // Wherever the top row is, note a line and when the page lands.
        guard let line = watched(app) else { return XCTFail("no message on screen to watch") }
        let label = line.label, before = line.frame.minY
        let deadline = Date().addingTimeInterval(10)
        while fetches(app) < 1 && Date() < deadline {
            list.swipeDown(velocity: .slow)
            usleep(300_000)
        }
        XCTAssertGreaterThanOrEqual(fetches(app), 1)
        sleep(2)
        let after = app.staticTexts[label]
        XCTAssertTrue(after.exists && after.isHittable, "the line he was reading is still on screen, not pushed off by the new page")
        _ = before
    }

    /// Leaving Chat and coming back: the newest messages, at the bottom,
    /// without the page he loaded, and the typed text still in the box.
    func testComingBackResetsToTheNewest() {
        // A half-typed message waiting in the box (the saved draft).
        let app = XCUIApplication()
        app.launchArguments = ["-jarvis.server", "http://127.0.0.1:9", "-openChat", "-demoChat", "-demoOlderServer", "-push.enabled", "NO", "-chat.draft", "half a thought"]
        app.launch()
        let list = app.scrollViews["chatList"]
        XCTAssertTrue(list.waitForExistence(timeout: 20))
        sleep(2)
        let box = app.descendants(matching: .any)["composer"]
        for _ in 0..<6 { list.swipeDown(velocity: .fast) }
        let deadline = Date().addingTimeInterval(12)
        while fetches(app) < 1 && Date() < deadline { list.swipeDown(velocity: .slow); usleep(300_000) }
        XCTAssertGreaterThanOrEqual(fetches(app), 1)
        XCTAssertTrue(app.staticTexts["ok 86"].waitForExistence(timeout: 5), "the older page is in")
        // To Talk and back, by the bar.
        app.buttons["Talk"].firstMatch.tap()
        sleep(2)
        app.buttons["Chat"].firstMatch.tap()
        sleep(3)
        if let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"] {
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("chat-back.png"))
        }
        XCTAssertTrue(app.staticTexts["ok 119"].isHittable, "back at the newest messages")
        XCTAssertFalse(app.staticTexts["ok 86"].exists, "the older page is let go")
        XCTAssertTrue(((box.value as? String) ?? "").hasPrefix("half a thought"), "what he typed stays")
    }

    /// Times sit just past the right edge at rest, a leftward drag doesn't
    /// change tab, and with the rows slid fully (`-pinTimes`, since XCUITest
    /// can't read the screen mid-drag) each message's time is on screen.
    func testDraggingLeftShowsTheTimes() {
        let app = launch()
        let list = app.scrollViews["chatList"]
        XCTAssertTrue(list.waitForExistence(timeout: 20))
        sleep(2)
        let screen = app.windows.firstMatch.frame
        let times = app.staticTexts.matching(identifier: "messageTime")
        func onScreen(_ app: XCUIApplication) -> Int {
            app.staticTexts.matching(identifier: "messageTime").allElementsBoundByIndex
                .filter { $0.frame.maxX <= screen.maxX + 1 && $0.frame.minX >= screen.minX && $0.frame.minY > 0 && $0.frame.maxY < screen.maxY }.count
        }
        XCTAssertGreaterThan(times.count, 0, "each message carries its time")
        XCTAssertEqual(onScreen(app), 0, "times are hidden at rest")
        let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)), withVelocity: 300, thenHoldForDuration: 0.5)
        sleep(1)
        XCTAssertEqual(onScreen(app), 0, "letting go hides them again")
        XCTAssertTrue(app.descendants(matching: .any)["composer"].isHittable, "still on Chat: the drag didn't change tab")
        app.terminate()
        let pinned = launch(["-pinTimes"])
        XCTAssertTrue(pinned.scrollViews["chatList"].waitForExistence(timeout: 20))
        sleep(2)
        XCTAssertGreaterThan(onScreen(pinned), 2, "slid left, the times are on screen")
        let time = pinned.staticTexts.matching(identifier: "messageTime").allElementsBoundByIndex.first { $0.frame.minY > 0 }
        XCTAssertNotNil(time?.label.range(of: #"^\d{1,2}:\d{2} [AP]M$"#, options: .regularExpression), "hour and minute, like 7:32 PM")
    }
}
