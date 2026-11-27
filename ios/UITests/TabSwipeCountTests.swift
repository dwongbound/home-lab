// Tab swipe smoothness (Dylan, 2026-11-19: "swiping between tabs has a
// slight lag"): Home → Talk → Chat → Talk → Home, four times, on sample
// data with a dead server (Talk can't call anyone). The debug counters
// (App/PerfCount.swift) say how many screens redraw per swipe.
import XCTest

final class TabSwipeCountTests: XCTestCase {
    func testSwipingAcrossTabs() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-jarvis.server", "http://127.0.0.1:9", "-demoSnapshot", "-demoChat", "-onHome", "-push.enabled", "NO"]
        app.launch()
        sleep(4)
        let window = app.windows.firstMatch
        for _ in 0..<4 {
            window.swipeLeft(velocity: .default)
            window.swipeLeft(velocity: .default)
            window.swipeRight(velocity: .default)
            window.swipeRight(velocity: .default)
        }
        XCTAssertTrue(window.exists)
    }
}
