// The Chat scroll-lag check (Dylan, 2026-11-19: "kinda laggy and buggy as
// i scroll"): a long mock history (-demoChat, no Jarvis), flung up and down
// while the scroll-deceleration hitch metric records.
import XCTest

final class ChatScrollTests: XCTestCase {
    func testScrollingChatHitches() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-jarvis.server", "http://127.0.0.1:9", "-openChat", "-demoChat", "-push.enabled", "NO"]
        app.launch()
        sleep(4)
        let list = app.scrollViews.firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 10))
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: [XCTOSSignpostMetric.scrollDecelerationMetric], options: options) {
            list.swipeDown(velocity: .fast)
            list.swipeDown(velocity: .fast)
            list.swipeUp(velocity: .fast)
            list.swipeUp(velocity: .fast)
        }
    }
}
