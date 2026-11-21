// Screenshot of the playbook editor's "add a step" buttons (sample data).
import XCTest

final class PlaybookStepButtonsShots: XCTestCase {
    func testStepButtons() {
        let app = XCUIApplication()
        app.launchArguments = ["-jarvis.server", "http://127.0.0.1:9", "-demoSnapshot", "-onHome", "-push.enabled", "NO", "-demoPlaybooks", "-openPlaybooks", "-editFirstPlaybook"]
        app.launch()
        let ask = app.buttons["Add a step: Ask Jarvis"]
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 20))
        for _ in 0..<8 where !(ask.exists && ask.isHittable) { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(ask.isHittable)
        sleep(1)
        if let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"] {
            let name = ProcessInfo.processInfo.environment["SHOT_NAME"] ?? "step-buttons"
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }
}
