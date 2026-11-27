// Screenshots of the iPad layouts in landscape (Dylan uses his 11-inch
// iPad Pro sideways as a wall display). Not a check: it saves pictures to
// look at, into SHOTS_DIR (or the temp folder). Skipped on an iPhone.
import XCTest

final class IPadLandscapeShots: XCTestCase {
    private let base = ["-jarvis.server", "http://127.0.0.1:9", "-demoSnapshot", "-push.enabled", "NO", "-resetDraft"]

    private func shoot(_ name: String, _ extra: [String]) throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("iPad only") }
        let app = XCUIApplication()
        app.launchArguments = base + extra
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        // The system's notification question, if it asks, is answered no.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let no = springboard.buttons["Don’t Allow"]
        if no.waitForExistence(timeout: 3) { no.tap() }
        sleep(4)
        let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"] ?? NSTemporaryDirectory()
        let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name).png")
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: url)
        app.terminate()
    }

    func testHome() throws { try shoot("land-home", ["-onHome"]) }
    func testChat() throws { try shoot("land-chat", ["-demoChat", "-openChat"]) }
    func testTalk() throws { try shoot("land-talk", ["-onTalkQuiet"]) }
    func testKiosk() throws { try shoot("land-kiosk", ["-onHome", "-openKiosk"]) }
}
