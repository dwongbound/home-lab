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

    /// Typing: the box sits right on the keyboard, not a keyboard higher
    /// (Dylan, 2026-11-20, build 38), and the newest message stays above it.
    func testTheBoxSitsOnTheKeyboard() throws {
        let app = launch()
        let field = box(app)
        XCTAssertTrue(field.waitForExistence(timeout: 20))
        sleep(2)
        field.tap()
        let keyboard = app.keyboards.firstMatch
        guard keyboard.waitForExistence(timeout: 5) else { throw XCTSkip("no on-screen keyboard in this simulator") }
        sleep(1)
        let gap = keyboard.frame.minY - field.frame.maxY
        if let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"] {
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("keyboard-\(Int(app.frame.width)).png"))
        }
        XCTAssertGreaterThanOrEqual(gap, 0, "the box mustn't sit behind the keyboard")
        // Measured from the text field to the keyboard's frame, which starts
        // above its suggestions row; the bug lifted the box ~300 pt.
        XCTAssertLessThan(gap, 100, "the box should sit just above the keyboard, not \(Int(gap)) pt above it")
        XCTAssertFalse(arrow(app).isHittable, "at the bottom with the keyboard up: no arrow")
    }

    /// A hard flick up, then the arrow at once, while the list still
    /// moves: it lands on the newest message fast, and the box is back.
    func testTheArrowWorksMidFlick() {
        let app = launch()
        XCTAssertTrue(box(app).waitForExistence(timeout: 20))
        sleep(2)
        let list = app.scrollViews["chatList"]
        list.swipeDown(velocity: .fast)
        list.swipeDown(velocity: .fast)
        list.swipeDown(velocity: .fast)
        XCTAssertTrue(arrow(app).waitForExistence(timeout: 3))
        arrow(app).tap()
        sleep(2)
        XCTAssertTrue(box(app).isHittable, "back at the newest message, the box is back")
        XCTAssertFalse(arrow(app).isHittable, "and the arrow has gone")
    }
}
