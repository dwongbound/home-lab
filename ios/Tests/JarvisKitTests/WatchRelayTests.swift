// The Watch ⇄ phone messages survive the trip both ways.
import XCTest
@testable import JarvisKit

final class WatchRelayTests: XCTestCase {
    /// Every request reads back as itself.
    func testRequestsRoundTrip() {
        for request in [WatchRequest.ask("Is the garage shut?"), .approvals, .answer(id: "a1", ok: true)] {
            XCTAssertEqual(WatchRequest(message: request.message), request)
        }
        XCTAssertNil(WatchRequest(message: ["op": "ask", "text": ""]))
        XCTAssertNil(WatchRequest(message: ["op": "launch"]))
    }

    /// Every reply reads back as itself; junk becomes a problem, not a crash.
    func testRepliesRoundTrip() {
        let approval = Approval(id: "a1", tool: "send_email", summary: "Email Matt", expires: "")
        for reply in [WatchReply.answer(text: "Shut.", model: "claude"), .answer(text: "Hi", model: nil), .approvals([approval]), .done, .problem("No signal")] {
            XCTAssertEqual(WatchReply(message: reply.message), reply)
        }
        if case .problem = WatchReply(message: ["kind": "confetti"]) {} else { XCTFail("junk should be a problem") }
    }
}
