import XCTest
@testable import JarvisKit

/// Replying to one earlier message (Dylan 2026-11-27).
final class ChatReplyTests: XCTestCase {
    /// The send carries the quoted turn's id; a plain send has none.
    func testChatRequestCarriesReplyTo() throws {
        let client = JarvisClient(base: URL(string: "https://jarvis.example.ts.net")!)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: client.chatRequest("yes that one", replyTo: 41).httpBody ?? Data()) as? [String: Any])
        XCTAssertEqual(body["replyTo"] as? Int, 41)
        let plain = try XCTUnwrap(JSONSerialization.jsonObject(with: client.chatRequest("hi").httpBody ?? Data()) as? [String: Any])
        XCTAssertNil(plain["replyTo"])
    }

    /// History turns read the quote back; older ones have none.
    func testHistoryTurnsReadTheQuote() throws {
        let json = #"{"role":"user","text":"yes","at":"x","id":42,"replyTo":{"id":41,"role":"jarvis","text":"Want me to book it?"}}"#
        let turn = try JSONDecoder().decode(ChatTurn.self, from: Data(json.utf8))
        XCTAssertEqual(turn.replyTo, ChatQuote(id: 41, role: "jarvis", text: "Want me to book it?"))
        XCTAssertEqual(turn.replyTo?.who, "Jarvis")
        let old = try JSONDecoder().decode(ChatTurn.self, from: Data(#"{"role":"user","text":"hi","at":"x"}"#.utf8))
        XCTAssertNil(old.replyTo)
    }

    /// A quote made here keeps at most 300 characters.
    func testQuoteIsShort() {
        XCTAssertEqual(ChatQuote(id: 1, role: "user", text: String(repeating: "a", count: 500)).text.count, 300)
        XCTAssertEqual(ChatQuote(id: 1, role: "user", text: "hi").who, "You")
    }
}
