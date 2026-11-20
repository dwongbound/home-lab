// Chat's bottom (Dylan, 2026-11-20): at the bottom the Ask box shows and no
// arrow; scrolled up with nothing typed the box becomes the round arrow;
// scrolled up while typing the box stays and the arrow sits above it; the
// arrow brings him back. Demo turns only, nothing reaches Jarvis.
import XCTest

final class ChatBottomTests: XCTestCase {
    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-jarvis.server", "http://127.0.0.1:9", "-openChat", "-demoChat", "-push.enabled", "NO", "-resetDraft"] + extra
        app.launch()
        return app
    }

    private func box(_ app: XCUIApplication) -> XCUIElement { app.descendants(matching: .any)["composer"] }
    private func arrow(_ app: XCUIApplication) -> XCUIElement { app.buttons["Newest message"] }

    func testAtTheBottomTheBoxShowsAndScrollingUpTurnsItIntoTheArrow() {
        let app = launch()
        XCTAssertTrue(box(app).waitForExistence(timeout: 20))
        sleep(2)
        // 1. At the bottom: the box, no arrow.
        XCTAssertTrue(box(app).isHittable, "the Ask box should show at the bottom")
        XCTAssertFalse(arrow(app).isHittable, "no arrow at the bottom")
        // 2. Scrolled up, nothing typed: the arrow, no box.
        let list = app.scrollViews["chatList"]
        list.swipeDown(velocity: .fast)
        list.swipeDown(velocity: .fast)
        XCTAssertTrue(arrow(app).waitForExistence(timeout: 5))
        sleep(1)
        XCTAssertTrue(arrow(app).isHittable, "the arrow should show when scrolled up")
        XCTAssertFalse(box(app).isHittable, "the box should be gone when scrolled up with nothing typed")
        // 4. The arrow goes back down, and the box returns.
        arrow(app).tap()
        sleep(2)
        XCTAssertTrue(box(app).isHittable, "the box should come back at the bottom")
        XCTAssertFalse(arrow(app).isHittable, "the arrow should go at the bottom")
    }

    func testScrolledUpWhileTypingTheBoxStaysWithTheArrowAboveIt() {
        let app = launch()
        let field = box(app)
        XCTAssertTrue(field.waitForExistence(timeout: 20))
        sleep(2)
        field.tap()
        field.typeText("dinner plans")
        // Dismiss the keyboard by scrolling the list, as he would.
        let list = app.scrollViews["chatList"]
        list.swipeDown(velocity: .fast)
        list.swipeDown(velocity: .fast)
        sleep(1)
        XCTAssertTrue(box(app).isHittable, "the box with words in it stays")
        XCTAssertTrue(arrow(app).waitForExistence(timeout: 5))
        XCTAssertTrue(arrow(app).isHittable, "the arrow sits above the box")
    }

    func testANewTurnWhilePinnedAtTheBottomKeepsTheBox() {
        // -mockTalkTurns adds two exchanges a few seconds in, while on Talk;
        // then Chat comes in, still at the bottom, box showing.
        let app = XCUIApplication()
        app.launchArguments = ["-jarvis.server", "http://127.0.0.1:9", "-demoChat", "-mockTalkTurns", "-push.enabled", "NO", "-resetDraft"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Done, from Talk (1)."].waitForExistence(timeout: 20))
        sleep(2)
        XCTAssertTrue(box(app).isHittable, "the box stays at the bottom after new turns")
        XCTAssertFalse(arrow(app).isHittable, "no arrow at the bottom after new turns")
    }
}
