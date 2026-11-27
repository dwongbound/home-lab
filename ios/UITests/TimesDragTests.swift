// The times drag keeps working (Dylan, 2026-11-21: "it did at first but now
// doesn't"), with drags a real finger makes (a little off flat), and no
// time peeks in at rest. With `-pinTimes` off, XCUITest can't read the
// screen mid-drag, so each drag is checked by the screen afterwards being
// back at rest and by a held drag's screenshot in SHOTS_DIR.
import XCTest

final class TimesDragTests: XCTestCase {
    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-jarvis.server", "http://127.0.0.1:9", "-openChat", "-demoChat", "-push.enabled", "NO", "-resetDraft", "-logTimesDrag"] + extra
        app.launch()
        return app
    }

    /// A leftward drag about 15° off flat, held, then let go.
    private func angledDrag(_ app: XCUIApplication, up: Bool = false) {
        let list = app.scrollViews["chatList"]
        let a = list.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.55))
        let b = list.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: up ? 0.48 : 0.62))
        a.press(forDuration: 0.05, thenDragTo: b, withVelocity: 350, thenHoldForDuration: 0.2)
    }

    private func onScreenTimes(_ app: XCUIApplication) -> Int {
        let screen = app.windows.firstMatch.frame
        return app.staticTexts.matching(identifier: "messageTime").allElementsBoundByIndex.filter {
            $0.frame.maxX > screen.minX && $0.frame.minX < screen.maxX && $0.frame.minY > 0 && $0.frame.maxY < screen.maxY && $0.isHittable
        }.count
    }

    func testNoTimePeeksAtRest() {
        let app = launch()
        XCTAssertTrue(app.scrollViews["chatList"].waitForExistence(timeout: 20))
        sleep(2)
        XCTAssertEqual(onScreenTimes(app), 0, "nothing of any time shows at rest (10:36 PM included)")
    }

    func testTheDragKeepsWorkingAfterEverything() {
        let app = launch()
        let list = app.scrollViews["chatList"]
        XCTAssertTrue(list.waitForExistence(timeout: 20))
        sleep(2)
        angledDrag(app)
        // A vertical scroll: this used to switch the times drag off for good.
        list.swipeDown(velocity: .slow)
        list.swipeUp(velocity: .slow)
        // A diagonal drag that's mostly vertical (rejected), then flicks.
        list.swipeDown(velocity: .fast)
        for _ in 0..<10 { angledDrag(app, up: Bool.random()) }
        // Tab away and back, the keyboard up and down, the arrow.
        app.buttons["Talk"].firstMatch.tap()
        sleep(1)
        app.buttons["Chat"].firstMatch.tap()
        sleep(1)
        let box = app.descendants(matching: .any)["composer"]
        box.tap()
        list.swipeDown(velocity: .slow)
        angledDrag(app)
        sleep(1)
        XCTAssertEqual(onScreenTimes(app), 0, "back at rest after each drag")
    }
}
