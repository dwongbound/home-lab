import XCTest
@testable import JarvisKit

final class HeardWordsTests: XCTestCase {
    func testStableSplitting() {
        XCTAssertEqual(HeardWords.split("what day of the week is it", stable: 4).settled, "what day of the")
        XCTAssertEqual(HeardWords.split("what day of the week is it", stable: 4).tail, "week is it")
        XCTAssertEqual(HeardWords.split("okay", stable: 0).settled, "")
        XCTAssertEqual(HeardWords.split("okay", stable: 0).tail, "okay")
        // More than there are: all settled.
        XCTAssertEqual(HeardWords.split("two words", stable: 9).settled, "two words")
        XCTAssertEqual(HeardWords.split("two words", stable: 9).tail, "")
        // An older Jarvis sends no stable: all tentative.
        XCTAssertEqual(HeardWords.split("two words", stable: nil).tail, "two words")
    }

    func testTheFinal() {
        XCTAssertEqual(HeardWords.afterFinal(shown: "what day is it", final: "What day is it?", same: true), "what day is it", "same: keep what's shown")
        XCTAssertEqual(HeardWords.afterFinal(shown: "what day is", final: "What day is it?", same: false), "What day is it?")
        XCTAssertEqual(HeardWords.afterFinal(shown: "", final: "What day is it?", same: true), "What day is it?", "nothing shown: the final")
    }

    func testTheEventsCarryTheNewFields() {
        XCTAssertEqual(TalkEvent.parse(#"{"type":"partial","text":"What day of the week is it today?","stable":4}"#), .partial("What day of the week is it today?", joined: false, stable: 4))
        XCTAssertEqual(TalkEvent.parse(#"{"type":"partial","text":"Okay."}"#), .partial("Okay.", joined: false, stable: nil))
        XCTAssertEqual(TalkEvent.parse(#"{"type":"transcript","text":"Hi.","same":true}"#), .transcript("Hi.", joined: false, same: true))
        XCTAssertEqual(TalkEvent.parse(#"{"type":"transcript","text":"Hi."}"#), .transcript("Hi.", joined: false, same: false))
    }

    /// The real sequence from Jarvis build 56.
    func testARealSequence() {
        let lines = [
            #"{"type":"partial","text":"Okay.","stable":0}"#,
            #"{"type":"partial","text":"What day of the weekend?","stable":0}"#,
            #"{"type":"partial","text":"What day of the week is it today?","stable":4}"#,
            #"{"type":"partial","text":"What day of the week is it today? and what is it?","stable":8}"#,
            #"{"type":"transcript","text":"What day of the week is it today, and what is the date?"}"#,
        ]
        var heard = "", stable: Int? = nil
        var seen: [(String, String)] = []
        for line in lines {
            switch TalkEvent.parse(line) {
            case .partial(let words, _, let s):
                heard = words; stable = s
                let parts = HeardWords.split(heard, stable: stable)
                seen.append((parts.settled, parts.tail))
            case .transcript(let words, _, let same):
                heard = HeardWords.afterFinal(shown: heard, final: words, same: same)
            default: XCTFail()
            }
        }
        XCTAssertEqual(seen[2].0, "What day of the")
        XCTAssertEqual(seen[3].0, "What day of the week is it today?")
        XCTAssertEqual(seen[3].1, "and what is it?")
        XCTAssertEqual(heard, "What day of the week is it today, and what is the date?", "no same field: the final replaces")
    }
}
