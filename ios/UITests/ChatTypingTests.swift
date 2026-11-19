// Typing lag (Dylan, 2026-11-19: "typing is also a bit laggy"): types a
// sentence into Chat's box over the long mock history (-demoChat, no
// Jarvis) and never sends it. Debug render counters (App/PerfCount.swift)
// show how much of the screen each keystroke redraws.
import XCTest

final class ChatTypingTests: XCTestCase {
    func testTypingIntoChat() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-jarvis.server", "http://127.0.0.1:9", "-openChat", "-demoChat", "-push.enabled", "NO"]
        app.launch()
        let field = app.descendants(matching: .any)["composer"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("what does tomorrow look like for me and the dinner")
        XCTAssertTrue(field.exists)
    }
}
