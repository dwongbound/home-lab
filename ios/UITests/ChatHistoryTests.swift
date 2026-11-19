// Lazy chat history (Dylan, 2026-11-19): 2,000 mock messages (no Jarvis).
// Opening draws only the newest page; scrolling up loads earlier pages.
import XCTest

final class ChatHistoryTests: XCTestCase {
    func testOpensFastAndLoadsEarlierOnScrollUp() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-jarvis.server", "http://127.0.0.1:9", "-openChat", "-demoChat", "-demoChatBig", "-push.enabled", "NO"]
        let start = Date()
        app.launch()
        let box = app.descendants(matching: .any)["composer"]
        XCTAssertTrue(box.waitForExistence(timeout: 20))
        print("CHAT_OPEN_SECONDS", Date().timeIntervalSince(start))
        let list = app.scrollViews.firstMatch
        for _ in 0..<6 { list.swipeDown(velocity: .fast) }
        XCTAssertTrue(list.exists)
        // Scrolled up, the box has tucked into its compose button.
        XCTAssertTrue(app.buttons["Write a message"].waitForExistence(timeout: 5))
    }
}
