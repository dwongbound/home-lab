// One swipe moves exactly one tab (Dylan, 2026-11-20, build 53: "i swipe
// and can go from tab 1 to tab 3"), and the tabs keep swiping after a
// times drag on Chat and after leaving Chat. The down arrow always wins.
import XCTest

final class TabStepTests: XCTestCase {
    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-jarvis.server", "http://127.0.0.1:9", "-demoSnapshot", "-demoChat", "-push.enabled", "NO", "-onHome"] + extra
        app.launch()
        return app
    }

    /// Which page is showing: Talk's button, Chat's box, or Home.
    private func page(_ app: XCUIApplication) -> String {
        let width = app.windows.firstMatch.frame.width
        func onScreen(_ e: XCUIElement) -> Bool {
            guard e.exists else { return false }
            let f = e.frame
            return f.minX >= -1 && f.maxX <= width + 1 && f.width > 0
        }
        if onScreen(app.staticTexts["Tap Talk to start"]) { return "talk" }
        if onScreen(app.descendants(matching: .any)["composer"]) { return "chat" }
        return "home"
    }

    private func flick(_ app: XCUIApplication, left: Bool) {
        let w = app.windows.firstMatch
        let a = w.coordinate(withNormalizedOffset: CGVector(dx: left ? 0.95 : 0.05, dy: 0.42))
        let b = w.coordinate(withNormalizedOffset: CGVector(dx: left ? 0.02 : 0.98, dy: 0.42))
        a.press(forDuration: 0.01, thenDragTo: b, withVelocity: 6000, thenHoldForDuration: 0)
        sleep(2)
    }

    func testAFastLongFlickMovesOneTab() {
        let app = launch()
        sleep(4)
        XCTAssertEqual(page(app), "home")
        flick(app, left: true)
        XCTAssertEqual(page(app), "talk", "Home flicks to Talk, not past it")
        flick(app, left: true)
        XCTAssertEqual(page(app), "chat")
        flick(app, left: false)
        XCTAssertEqual(page(app), "talk", "Chat flicks back to Talk, not Home")
        flick(app, left: false)
        XCTAssertEqual(page(app), "home")
    }

    func testSwipesKeepWorkingAfterATimesDragOnChat() {
        let app = launch()
        sleep(4)
        for _ in 0..<2 {
            app.windows.firstMatch.swipeLeft()
            app.windows.firstMatch.swipeLeft()
            sleep(1)
            XCTAssertEqual(page(app), "chat")
            // A times drag on Chat.
            let list = app.scrollViews["chatList"]
            list.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).press(forDuration: 0.05, thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)), withVelocity: 400, thenHoldForDuration: 0.3)
            sleep(1)
            XCTAssertEqual(page(app), "chat", "the times drag stays on Chat")
            app.windows.firstMatch.swipeRight()
            sleep(1)
            XCTAssertEqual(page(app), "talk", "and a rightward swipe still goes to Talk")
            app.windows.firstMatch.swipeRight()
            sleep(1)
            XCTAssertEqual(page(app), "home")
        }
    }

    /// The arrow, tapped while an upward flick is still moving, goes to the bottom.
    func testTheArrowWinsMidFlick() {
        let app = XCUIApplication()
        app.launchArguments = ["-jarvis.server", "http://127.0.0.1:9", "-openChat", "-demoChat", "-demoOlderServer", "-push.enabled", "NO", "-resetDraft"]
        app.launch()
        let list = app.scrollViews["chatList"]
        XCTAssertTrue(list.waitForExistence(timeout: 20))
        sleep(2)
        list.swipeDown(velocity: .fast)
        list.swipeDown(velocity: .fast)
        // Mid-flick, toward the top where a page loads.
        list.swipeDown(velocity: .fast)
        let arrow = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Newest message'")).firstMatch
        if arrow.exists { arrow.tap() }
        sleep(3)
        XCTAssertTrue(app.staticTexts["ok 119"].isHittable, "the arrow lands on the newest message")
        XCTAssertTrue(app.descendants(matching: .any)["composer"].isHittable)
    }
}
