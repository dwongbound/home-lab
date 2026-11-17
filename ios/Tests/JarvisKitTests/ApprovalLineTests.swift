// Settled approvals as one line, and when a waiting one has run out of time.
import XCTest
@testable import JarvisKit

final class ApprovalLineTests: XCTestCase {
    func testSettledLines() {
        XCTAssertEqual(ApprovalWording.settledLine(ok: true, later: false, by: "page", summary: "Write notes.md"), "Approved: Write notes.md")
        XCTAssertEqual(ApprovalWording.settledLine(ok: false, later: false, by: "voice", summary: "Restart HA"), "Denied out loud: Restart HA")
        XCTAssertEqual(ApprovalWording.settledLine(ok: true, later: false, by: "telegram", summary: "x"), "Approved on Telegram: x")
        XCTAssertEqual(ApprovalWording.settledLine(ok: false, later: false, by: "timeout", summary: "Restart HA"), "Timed out: Restart HA")
        XCTAssertEqual(ApprovalWording.settledLine(ok: false, later: true, by: "voice", summary: "Restart HA"), "Holding for later: Restart HA")
    }

    func testExpiry() {
        let now = ISO8601DateFormatter().date(from: "2026-11-17T10:00:00Z")!
        XCTAssertTrue(ApprovalWording.hasExpired("2026-11-17T09:59:59Z", now: now))
        XCTAssertTrue(ApprovalWording.hasExpired("2026-11-17T09:59:59.500Z", now: now))
        XCTAssertFalse(ApprovalWording.hasExpired("2026-11-17T10:05:00Z", now: now))
        XCTAssertFalse(ApprovalWording.hasExpired("", now: now))
    }
}
