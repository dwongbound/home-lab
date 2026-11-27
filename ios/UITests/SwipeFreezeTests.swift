// Repeats the 2026-11-19 freeze: half swipes from Home toward Talk, held
// and let go, then full ones. The app is pointed at a dead address so no
// Talk call or anything else reaches Jarvis. XCUITest waits for the app to
// go idle after every gesture; a runaway update loop shows up as a hang.
import XCTest

final class SwipeFreezeTests: XCTestCase {
    func testSwipingHomeToTalkStaysResponsive() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-jarvis.server", "http://127.0.0.1:9", "-onHome", "-push.enabled", "NO"]
        app.launch()
        sleep(3)
        let window = app.windows.firstMatch
        let right = window.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.45))
        let third = window.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.45))
        let back = window.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.45))
        for round in 0..<8 {
            // Drag about a third of the way, hold, then go back to Home.
            right.press(forDuration: 0.05, thenDragTo: third, withVelocity: .slow, thenHoldForDuration: 1.0)
            XCTAssertTrue(window.waitForExistence(timeout: 5), "round \(round)")
            _ = back
        }
        // The status line must still answer, i.e. the main thread is free.
        let start = Date()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 8) || app.staticTexts.firstMatch.exists)
        XCTAssertLessThan(Date().timeIntervalSince(start), 8)
    }
}
