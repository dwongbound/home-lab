// The drawer's notice swipe (Dylan, 2026-11-19), on sample data with a dead
// server: a full swipe dismisses the row at once; the server can't be
// reached, so the row comes back with a plain message.
import XCTest

final class NoticeSwipeTests: XCTestCase {
    func testFullSwipeDismissesThenRollsBack() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-jarvis.server", "http://127.0.0.1:9", "-demoSnapshot", "-onHome", "-openNoticesSheet", "-push.enabled", "NO"]
        app.launch()
        let row = app.staticTexts["PS5 Pro back in stock at Target"]
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        let cell = app.cells.containing(.staticText, identifier: "PS5 Pro back in stock at Target").firstMatch
        XCTAssertTrue(cell.exists)
        // Part way first: the two buttons show.
        let start = cell.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: cell.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.5)))
        XCTAssertTrue(app.buttons["Dismiss"].waitForExistence(timeout: 3), "Dismiss shows on a part swipe")
        app.buttons["Dismiss"].tap()
        let alert = app.alerts["Notice"]
        XCTAssertTrue(alert.waitForExistence(timeout: 20), "the failed dismiss says so")
        alert.buttons["Close"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5), "and the row is back")
    }
}
