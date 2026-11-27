import XCTest
@testable import JarvisKit

final class HeardPlacementTests: XCTestCase {
    /// Runs a stream of (words, joined, kind) through the Talk screen's rule
    /// and returns the exchanges as (heard, reply) pairs.
    private func run(_ steps: [(String, String, Bool)]) -> [(String, String)] {
        var done: [(String, String)] = []
        var heard = "", reply = "", finished = false
        for (kind, words, joined) in steps {
            switch kind {
            case "heard":
                if HeardPlacement.of(openReply: reply, openDone: finished, joined: joined) == .new {
                    done.append((heard, reply)); heard = ""; reply = ""; finished = false
                }
                heard = words
            case "reply": reply += words
            default: finished = true
            }
        }
        return done + [(heard, reply)]
    }

    func testNoPartialsTranscriptThenReply() {
        let out = run([("heard", "what's the weather", false), ("reply", "Sunny.", false), ("done", "", false)])
        XCTAssertEqual(out.map(\.0), ["what's the weather"])
        XCTAssertEqual(out.map(\.1), ["Sunny."])
    }

    func testFirstTranscriptJoinedWithNoBubble() {
        let out = run([("heard", "turn the lights off", true), ("reply", "Done.", false)])
        XCTAssertEqual(out.map(\.0), ["turn the lights off"])
    }

    func testTranscriptWhileThePreviousReplyIsShowing() {
        let out = run([("heard", "one", false), ("reply", "First.", false), ("heard", "two", false), ("reply", "Second.", false)])
        XCTAssertEqual(out.map(\.0), ["one", "two"])
        XCTAssertEqual(out.map(\.1), ["First.", "Second."])
    }

    func testJoinedAfterAFinishedReplyStartsANewExchange() {
        // The bug: his earlier words vanished and the answers ran together.
        let out = run([("heard", "one", false), ("reply", "First.", false), ("done", "", false), ("heard", "one and two", true), ("reply", "Second.", false)])
        XCTAssertEqual(out.map(\.0), ["one", "one and two"])
        XCTAssertEqual(out.map(\.1), ["First.", "Second."])
    }

    func testJoinedBeforeAnyReplyStaysInPlace() {
        let out = run([("heard", "remind me", false), ("heard", "remind me to call mom", true), ("reply", "Will do.", false)])
        XCTAssertEqual(out.map(\.0), ["remind me to call mom"])
    }

    func testSparsePartialsThenALongerTranscript() {
        let out = run([("heard", "set a", false), ("heard", "set a timer for", false), ("heard", "set a timer for ten minutes", false), ("reply", "Timer set.", false)])
        XCTAssertEqual(out.map(\.0), ["set a timer for ten minutes"])
    }
}
