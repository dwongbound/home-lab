import XCTest
@testable import JarvisKit

/// Sending while Jarvis is still answering (Jarvis build 115's contract).
final class SteerTests: XCTestCase {
    private func events(_ lines: [String]) -> [ChatEvent] { lines.compactMap(ChatEvent.parse(line:)) }

    func testSteeredStream() {
        let e = events([#"{"type":"turn","id":42}"#, #"{"type":"steered","into":41,"as":"steered"}"#, #"{"type":"done","ok":true}"#])
        XCTAssertEqual(e, [.turn(42), .steered(into: 41, as: "steered"), .done])
    }

    func testStoppedApprovalAndNullInto() {
        XCTAssertEqual(ChatEvent.parse(line: #"{"type":"steered","into":41,"as":"stopped"}"#), .steered(into: 41, as: "stopped"))
        XCTAssertEqual(ChatEvent.parse(line: #"{"type":"steered","into":41,"as":"approval"}"#), .steered(into: 41, as: "approval"))
        XCTAssertEqual(ChatEvent.parse(line: #"{"type":"steered","into":null,"as":"steered"}"#), .steered(into: nil, as: "steered"))
    }

    func testQueuedStreamCarriesItsOwnReply() {
        let e = events([#"{"type":"turn","id":43}"#, #"{"type":"queued","after":41}"#, #"{"type":"model","model":"claude"}"#, #"{"type":"delta","text":"Hi"}"#, #"{"type":"done"}"#])
        XCTAssertEqual(e, [.turn(43), .queued(after: 41), .model("claude"), .delta("Hi"), .done])
    }

    func testUnknownEventIsIgnored() {
        XCTAssertNil(ChatEvent.parse(line: #"{"type":"steer_preview","foo":1}"#))
    }

    /// A steered message moves just above the reply still coming.
    func testSteeredGoesAboveTheOpenReply() {
        let lines: [SendFlow.Line] = [.init(id: "q1", isUser: true, open: false), .init(id: "r1", isUser: false, open: true), .init(id: "q2", isUser: true, open: false)]
        let at = SendFlow.steeredIndex(lines, mine: "q2")
        XCTAssertEqual(at, 1)
        XCTAssertEqual(SendFlow.move(lines.map(\.id), "q2", to: at), ["q1", "q2", "r1"])
    }

    /// Two quick sends both steer: each lands above the reply, in order.
    func testTwoQuickSends() {
        var ids = ["q1", "r1", "q2"]
        func lines() -> [SendFlow.Line] { ids.map { .init(id: $0, isUser: $0.hasPrefix("q"), open: $0 == "r1") } }
        ids = SendFlow.move(ids, "q2", to: SendFlow.steeredIndex(lines(), mine: "q2"))
        ids.append("q3")
        ids = SendFlow.move(ids, "q3", to: SendFlow.steeredIndex(lines(), mine: "q3"))
        XCTAssertEqual(ids, ["q1", "q2", "q3", "r1"])
    }

    /// Sent right as the first reply ended: nothing open, it stays put.
    func testSendAsTheReplyEnds() {
        let lines: [SendFlow.Line] = [.init(id: "q1", isUser: true, open: false), .init(id: "r1", isUser: false, open: false), .init(id: "q2", isUser: true, open: false)]
        XCTAssertNil(SendFlow.steeredIndex(lines, mine: "q2"))
        XCTAssertEqual(SendFlow.move(lines.map(\.id), "q2", to: nil), ["q1", "r1", "q2"])
    }

    /// A queued message moves into its own turn at the end when its reply starts.
    func testQueuedMovesToTheEnd() {
        XCTAssertEqual(SendFlow.move(["q1", "q2", "r1"], "q2", to: nil), ["q1", "r1", "q2"])
    }
}
