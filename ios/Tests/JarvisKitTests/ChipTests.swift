import XCTest
@testable import JarvisKit

final class ChipTests: XCTestCase {
    func testAReplyKeepsItsChip() {
        XCTAssertEqual(ModelWording.chip(model: "claude-opus-5-5"), .init(label: "Jarvis (CO)", tone: .claude, source: ""))
        XCTAssertEqual(ModelWording.chip(model: "ornith-1.5:9b"), .init(label: "Jarvis (O)", tone: .local, source: ""))
    }

    func testAnUnaskedMessageNamesItsWriterThenTheSource() {
        XCTAssertEqual(ModelWording.chip(model: "notice:lookout", writer: "claude-opus-5-5"), .init(label: "Jarvis (CO)", tone: .claude, source: "Lookout"))
        XCTAssertEqual(ModelWording.chip(model: "notice:job", writer: "ornith-1.5:9b"), .init(label: "Jarvis (O)", tone: .local, source: "Finished"))
    }

    func testNoWriterIsJarvisNeverTheWordAlone() {
        XCTAssertEqual(ModelWording.chip(model: "notice:reminder"), .init(label: "Jarvis", tone: .notice, source: "Reminder"))
        XCTAssertEqual(ModelWording.chip(model: "notice:reminder", writer: "  "), .init(label: "Jarvis", tone: .notice, source: "Reminder"))
        // An unknown source gives no word.
        XCTAssertEqual(ModelWording.chip(model: "notice:somethingnew", writer: "claude-haiku-5"), .init(label: "Jarvis (CH)", tone: .claude, source: ""))
    }

    func testHistoryCarriesTheWriter() throws {
        let json = #"{"id":12,"role":"assistant","text":"Matthew replied","at":"2026-11-18T16:00:00-08:00","model":"notice:lookout","writer":"claude-opus-5-5"}"#
        let turn = try JSONDecoder().decode(ChatTurn.self, from: Data(json.utf8))
        XCTAssertEqual(turn.writer, "claude-opus-5-5")
        let old = try JSONDecoder().decode(ChatTurn.self, from: Data(#"{"role":"assistant","text":"x","at":"","model":"notice:reminder"}"#.utf8))
        XCTAssertNil(old.writer)
    }
}
