// The voice line's events, sound helpers and address.
import XCTest
@testable import JarvisKit

final class TalkTests: XCTestCase {
    /// Every event the page's Talk handles reads the same here.
    func testParsesEvents() {
        XCTAssertEqual(TalkEvent.parse(#"{"type":"hello","rate":24000,"wake_word":true}"#), .hello(rate: 24000, wakeWord: true))
        XCTAssertEqual(TalkEvent.parse(#"{"type":"state","state":"dozing"}"#), .state(.dozing))
        XCTAssertEqual(TalkEvent.parse(#"{"type":"partial","text":"what's the"}"#), .partial("what's the", joined: false))
        XCTAssertEqual(TalkEvent.parse(#"{"type":"transcript","text":"and tomorrow","joined":true}"#), .transcript("and tomorrow", joined: true))
        XCTAssertEqual(TalkEvent.parse(#"{"type":"reply","text":"Clear, 61."}"#), .reply("Clear, 61."))
        XCTAssertEqual(TalkEvent.parse(#"{"type":"working","label":"Searching the web."}"#), .working("Searching the web."))
        XCTAssertEqual(TalkEvent.parse(#"{"type":"stop"}"#), .stop)
        XCTAssertEqual(
            TalkEvent.parse(#"{"type":"approval","id":"a1","tool":"send_email","summary":"Email Matt","expires":"x"}"#),
            .approval(Approval(id: "a1", tool: "send_email", summary: "Email Matt", expires: "x"))
        )
        XCTAssertEqual(
            TalkEvent.parse(#"{"type":"approval_done","id":"a1","ok":true,"by":"voice"}"#),
            .approvalDone(id: "a1", ok: true, by: "voice", later: false)
        )
    }

    /// Unknown types, unknown states and junk are skipped, not fatal.
    func testSkipsWhatItDoesNotKnow() {
        XCTAssertNil(TalkEvent.parse(#"{"type":"sparkle"}"#))
        XCTAssertNil(TalkEvent.parse(#"{"type":"state","state":"sleeping"}"#))
        XCTAssertNil(TalkEvent.parse("not json"))
        XCTAssertNil(TalkEvent.parse(#"{"type":"reply","text":""}"#))
    }

    /// The "got it" sound only on listening to thinking.
    func testHeardYouOut() {
        XCTAssertTrue(TalkAudio.heardYouOut(before: .listening, after: .thinking))
        XCTAssertFalse(TalkAudio.heardYouOut(before: .speaking, after: .thinking))
        XCTAssertFalse(TalkAudio.heardYouOut(before: .listening, after: .speaking))
    }

    /// 16-bit audio survives the trip to floats and back.
    func testPCMRoundTrip() {
        let floats: [Float] = [0, 0.5, -0.5, 1, -1]
        let back = TalkAudio.floats(fromPCM16: TalkAudio.pcm16(fromFloats: floats))
        XCTAssertEqual(back.count, floats.count)
        for (a, b) in zip(floats, back) { XCTAssertEqual(a, b, accuracy: 0.001) }
        XCTAssertEqual(TalkAudio.pcm16(fromFloats: [2]), TalkAudio.pcm16(fromFloats: [1]))
    }

    /// Frames are exactly 640 bytes, and leftovers wait for the next chunk.
    func testFrameCutter() {
        var cutter = FrameCutter()
        XCTAssertEqual(cutter.add([Float](repeating: 0.1, count: 300)).count, 0)
        let frames = cutter.add([Float](repeating: 0.1, count: 400))
        XCTAssertEqual(frames.count, 2)
        XCTAssertEqual(frames.map(\.count), [640, 640])
    }

    /// Sentence edges fade to silence.
    func testSoftenEdges() {
        var floats = [Float](repeating: 1, count: 1000)
        TalkAudio.softenEdges(&floats, rate: 24000)
        XCTAssertEqual(floats.first, 0)
        XCTAssertEqual(floats.last, 0)
        XCTAssertEqual(floats[500], 1)
    }

    /// wss on the server's host, with the Origin the server checks.
    func testTalkRequest() {
        let client = JarvisClient(base: URL(string: "https://jarvis.snakebird-ph.ts.net")!)
        XCTAssertEqual(client.talkURL.absoluteString, "wss://jarvis.snakebird-ph.ts.net/api/jarvis/talk")
        XCTAssertEqual(client.talkRequest.value(forHTTPHeaderField: "Origin"), "https://jarvis.snakebird-ph.ts.net")
    }
}
