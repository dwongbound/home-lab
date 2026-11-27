// Haptics on tab changes (Dylan, 2026-11-20: "incorporate vibrations more
// ... when switching tabs"). The simulator can't play them, so the debug
// build logs each moment's name with -logHaptics and the run reads the log
// from outside: two committed swipes and one bar tap should log three
// "haptic tab" lines, and a swipe that springs back none.
import XCTest

final class HapticTabTests: XCTestCase {
    func testOneTickPerTabChange() {
        let app = XCUIApplication()
        app.launchArguments = ["-jarvis.server", "http://127.0.0.1:9", "-demoSnapshot", "-demoChat", "-onHome", "-push.enabled", "NO", "-logHaptics"]
        app.launch()
        sleep(4)
        let window = app.windows.firstMatch
        window.swipeLeft(velocity: .default)    // Home → Talk: one tick
        sleep(1)
        window.swipeLeft(velocity: .default)    // Talk → Chat: one tick
        sleep(1)
        // A short, slow drag that springs back to Chat: no tick.
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.45))
        start.press(forDuration: 0.1, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.42, dy: 0.45)), withVelocity: 60, thenHoldForDuration: 0.3)
        sleep(1)
        // The bar: Home, one tick.
        let home = app.buttons["Home"].firstMatch
        if home.waitForExistence(timeout: 5) { home.tap() }
        sleep(2)
        XCTAssertTrue(window.exists)
    }
}
