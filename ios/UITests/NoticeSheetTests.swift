// The notice sheet, the orb's popup and the drawers (Dylan, 2026-11-20).
// Sample data only (-demoSnapshot): clearing a notice is local, nothing is
// sent anywhere.
import XCTest

final class NoticeSheetTests: XCTestCase {
    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-jarvis.server", "http://127.0.0.1:9", "-demoSnapshot", "-push.enabled", "NO"] + extra
        app.launch()
        return app
    }

    private func newCount(_ app: XCUIApplication) -> Int? {
        let pill = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS ' new'")).firstMatch
        guard pill.exists else { return nil }
        return Int(pill.label.prefix { $0.isNumber })
    }

    /// "when tapping view more, i should see everything": the long title in
    /// full, the body scrolls to its last words, the buttons stay put.
    func testALongNoticeScrollsToItsLastWords() {
        let app = launch(["-onHome", "-demoLongNotice", "-openNoticeDetail", "nlong"])
        let title = app.staticTexts["noticeTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        XCTAssertTrue(title.label.hasSuffix("and ends here"), "the whole title, not cut")
        XCTAssertTrue(app.buttons["sheetClose"].exists, "the x is there")
        let keep = app.buttons["Keep"]
        XCTAssertTrue(keep.isHittable)
        let body = app.staticTexts.matching(NSPredicate(format: "label ENDSWITH 'The very last words.'")).firstMatch
        XCTAssertTrue(body.exists, "the whole body is there")
        for _ in 0..<12 { app.swipeUp(velocity: .fast) }
        sleep(1)
        XCTAssertLessThanOrEqual(body.frame.maxY, keep.frame.minY + 2, "scrolled to the end, the last words sit above the buttons")
        XCTAssertTrue(keep.isHittable, "the buttons stay visible")
    }

    /// Open chat lands on the message and dismisses the notice.
    func testOpenChatDismissesTheNotice() {
        let app = launch(["-onHome", "-demoChat", "-openNoticeDetail", "n0"])
        XCTAssertTrue(app.staticTexts["noticeTitle"].waitForExistence(timeout: 15))
        let before = newCount(app)
        app.buttons["Open chat"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["composer"].waitForExistence(timeout: 10), "on Chat")
        sleep(3)
        if let before { XCTAssertEqual(newCount(app), before - 1, "the notice is dismissed") }
    }

    /// The orb's popup stays well past its old 6 s, closing it clears
    /// nothing, and See more opens the notice sheet.
    func testTheOrbPopupStaysAndSeeMoreOpensTheSheet() {
        let app = launch(["-onTalkQuiet", "-openNotice", "-openNoticeId", "n2"])
        let seeMore = app.buttons["See more"]
        XCTAssertTrue(seeMore.waitForExistence(timeout: 25), "the popup offers See more")
        let before = newCount(app)
        sleep(12)
        XCTAssertTrue(seeMore.exists, "still open after 12 s (it used to close at 6)")
        seeMore.tap()
        XCTAssertTrue(app.staticTexts["noticeTitle"].waitForExistence(timeout: 5), "See more opens the notice sheet")
        app.buttons["sheetClose"].tap()
        sleep(2)
        XCTAssertEqual(newCount(app), before, "nothing was dismissed")
    }

    /// The Home panel's drawer opens at full height, with the x.
    func testTheHomeDrawerOpensFullHeight() {
        let app = launch(["-onHome"])
        let lights = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'lights on'")).firstMatch
        XCTAssertTrue(lights.waitForExistence(timeout: 15))
        lights.tap()
        let close = app.buttons["sheetClose"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        XCTAssertLessThan(close.frame.minY, app.windows.firstMatch.frame.height * 0.25, "full height, not half")
        XCTAssertGreaterThan(close.frame.midX, app.windows.firstMatch.frame.width / 2, "the x sits top right")
        close.tap()
        XCTAssertFalse(close.waitForExistence(timeout: 2))
    }
}
