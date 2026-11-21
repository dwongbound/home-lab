// The notices chip and Settings stay put across the tabs (Dylan,
// 2026-11-21: "should stay at the top and not swipe with the tabs"). The
// same element answers on every tab, in the same place; a screen recording
// covers mid-swipe (XCUITest can't read the screen during a drag).
import XCTest

final class TopButtonsTests: XCTestCase {
    func testTheGearAndChipAreOneAndStayPut() {
        let app = XCUIApplication()
        app.launchArguments = ["-jarvis.server", "http://127.0.0.1:9", "-demoSnapshot", "-demoChat", "-push.enabled", "NO", "-onHome"]
        app.launch()
        let gear = app.buttons["Settings"]
        XCTAssertTrue(gear.waitForExistence(timeout: 15))
        sleep(3)
        XCTAssertEqual(app.buttons.matching(identifier: "Settings").count, 1, "one gear, not one per page")
        let home = gear.frame
        let chip = app.buttons.matching(NSPredicate(format: "label CONTAINS 'unread notices'")).firstMatch
        let chipHome = chip.frame
        for _ in 0..<2 {
            app.windows.firstMatch.swipeLeft()
            sleep(1)
            XCTAssertEqual(gear.frame, home, "the gear doesn't move")
            XCTAssertEqual(chip.frame, chipHome, "the chip doesn't move")
        }
        app.windows.firstMatch.swipeRight()
        app.windows.firstMatch.swipeRight()
        sleep(1)
        XCTAssertEqual(gear.frame, home)
        chip.tap()
        XCTAssertTrue(app.staticTexts["PS5 Pro back in stock at Target"].waitForExistence(timeout: 5), "the chip still opens the notices")
    }
}
