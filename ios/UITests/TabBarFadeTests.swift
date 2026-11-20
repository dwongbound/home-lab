// The tab bar's words fade in place as it shrinks (Dylan, 2026-11-19).
// Swipes between tabs (which opens the bar), then saves frames of the
// shrink two seconds later for a look; also swipes Home ↔ Talk several
// times to be sure nothing freezes. Sample data, Jarvis cut off.
import XCTest

final class TabBarFadeTests: XCTestCase {
    func testWordsFadeInPlaceAndSwipesStayResponsive() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-jarvis.server", "http://127.0.0.1:9", "-demoSnapshot", "-onHome", "-push.enabled", "NO"]
        app.launch()
        sleep(3)
        let window = app.windows.firstMatch
        for _ in 0..<3 {
            window.swipeLeft()
            window.swipeRight()
        }
        // Open the bar by touching it, then catch the shrink.
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.94)).tap()
        let out = ProcessInfo.processInfo.environment["FRAMES_DIR"] ?? "/private/tmp/claude-501/frames"
        try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        let start = Date()
        var i = 0
        while Date().timeIntervalSince(start) < 3.2 {
            let shot = XCUIScreen.main.screenshot()
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: "\(out)/f\(String(format: "%02d", i)).png"))
            i += 1
        }
        XCTAssertTrue(window.exists)
    }
}
