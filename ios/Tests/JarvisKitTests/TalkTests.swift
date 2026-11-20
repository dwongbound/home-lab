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

    func testBrightnessRisesWithPitch() {
        let rate = 16000.0
        func tone(_ hz: Double) -> [Float] {
            (0..<1600).map { Float(sin(2 * .pi * hz * Double($0) / rate) * 0.5) }
        }
        let low = tone(200).withUnsafeBufferPointer { TalkAudio.brightness($0, rate: rate) }
        let high = tone(1200).withUnsafeBufferPointer { TalkAudio.brightness($0, rate: rate) }
        let quiet = [Float](repeating: 0.001, count: 1600).withUnsafeBufferPointer { TalkAudio.brightness($0, rate: rate) }
        XCTAssertLessThan(low, high)
        XCTAssertGreaterThan(high, 0.5)
        XCTAssertEqual(quiet, 0)
    }

    func testParsesBye() {
        XCTAssertEqual(TalkEvent.parse(#"{"type":"bye"}"#), .bye)
    }

    /// "woke" brings him back to listening whatever woke him, including
    /// speech (Jarvis build 69) and reasons this app doesn't know yet.
    func testWokeMeansListeningWhateverWokeHim() {
        XCTAssertEqual(TalkEvent.parse(#"{"type":"woke","by":"speech"}"#), .state(.listening))
        XCTAssertEqual(TalkEvent.parse(#"{"type":"woke","by":"voice"}"#), .state(.listening))
        XCTAssertEqual(TalkEvent.parse(#"{"type":"woke","by":"something-new"}"#), .state(.listening))
        XCTAssertEqual(TalkEvent.parse(#"{"type":"woke"}"#), .state(.listening))
    }
}

final class PlaybackTrackerTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_000)

    /// The normal order: audio plays out, then "done", then idle once.
    func testIdleOnceAfterPlayedAndDone() {
        var p = PlaybackTracker()
        p.scheduled(seconds: 1.2, now: t0)
        XCTAssertFalse(p.takeIdle(now: t0))
        p.played()
        p.done()
        XCTAssertTrue(p.takeIdle(now: t0.addingTimeInterval(1.2)))
        XCTAssertFalse(p.takeIdle(now: t0.addingTimeInterval(1.3)), "only once")
    }

    /// A one-sentence reply that finished before "done" came.
    func testShortReplyDoneAfterPlayback() {
        var p = PlaybackTracker()
        p.scheduled(seconds: 0.4, now: t0)
        p.played()
        p.done()
        XCTAssertTrue(p.takeIdle(now: t0.addingTimeInterval(0.5)))
    }

    /// The 10:44 case: the Bluetooth route reconfigures as the short reply
    /// starts, the played callback never comes, and the clock backstop
    /// sends idle shortly after the audio should have ended.
    func testLostCallbackFallsBackToTheClock() {
        var p = PlaybackTracker()
        p.scheduled(seconds: 0.6, now: t0)
        p.done()
        XCTAssertFalse(p.takeIdle(now: t0.addingTimeInterval(0.6)), "not before the grace")
        XCTAssertEqual(p.nextCheck(now: t0), t0.addingTimeInterval(0.6 + PlaybackTracker.grace))
        XCTAssertTrue(p.takeIdle(now: t0.addingTimeInterval(0.6 + PlaybackTracker.grace)))
    }

    /// An engine restart forgets the buffers in flight; idle goes once done.
    func testEngineRestartStopsWaitingOnCallbacks() {
        var p = PlaybackTracker()
        p.scheduled(seconds: 2, now: t0)
        p.scheduled(seconds: 2, now: t0)
        p.engineRestarted()
        p.done()
        XCTAssertTrue(p.takeIdle(now: t0.addingTimeInterval(0.1)))
    }

    /// Sentences queue one after another, so the expected end adds up.
    func testExpectedEndAddsUp() {
        var p = PlaybackTracker()
        p.scheduled(seconds: 1, now: t0)
        p.scheduled(seconds: 2, now: t0.addingTimeInterval(0.5))
        XCTAssertEqual(p.expectedEnd, t0.addingTimeInterval(3))
    }

    /// Talking over him clears everything; nothing is owed.
    func testResetOwesNothing() {
        var p = PlaybackTracker()
        p.scheduled(seconds: 1, now: t0)
        p.done()
        p.reset()
        XCTAssertFalse(p.takeIdle(now: t0.addingTimeInterval(10)))
    }
}

final class ChatWindowTests: XCTestCase {
    func testPagesOfForty() {
        XCTAssertEqual(ChatWindow.first(total: 240), 40)
        XCTAssertEqual(ChatWindow.first(total: 12), 12)
        XCTAssertEqual(ChatWindow.grow(40, total: 240), 80)
        XCTAssertEqual(ChatWindow.grow(220, total: 240), 240)
        XCTAssertTrue(ChatWindow.hasMore(shown: 40, total: 240))
        XCTAssertFalse(ChatWindow.hasMore(shown: 240, total: 240))
    }

    /// Opening an old turn from a notice widens the window to reach it.
    func testIncludingAnOldMessage() {
        // Index 100 of 240 is the 140th from the end: three pages plus one.
        XCTAssertEqual(ChatWindow.including(index: 100, shown: 40, total: 240), 200)
        XCTAssertEqual(ChatWindow.including(index: 230, shown: 40, total: 240), 40)
        XCTAssertEqual(ChatWindow.including(index: 0, shown: 40, total: 240), 240)
    }
}

final class ChatHistoryTests: XCTestCase {
    private func turn(_ id: Int, user: Bool) -> ChatTurn {
        ChatTurn(role: user ? "user" : "assistant", text: "t\(id)", at: "", model: nil, id: id)
    }

    func testQueriesAndTodaysAnswer() throws {
        XCTAssertEqual(HistoryQuery.before(40, limit: 50).parameters, ["limit": "50", "before": "40"])
        XCTAssertEqual(HistoryQuery.around(7, limit: 500).parameters, ["limit": "100", "around": "7"])
        // Today's server: turns only, so no older pages and pending unknown.
        let today = try JSONDecoder().decode(HistoryPage.self, from: Data(#"{"turns":[{"role":"user","text":"hi","at":"","id":1}]}"#.utf8))
        XCTAssertFalse(today.hasMore)
        XCTAssertNil(today.pending)
        let paged = try JSONDecoder().decode(HistoryPage.self, from: Data(#"{"turns":[],"hasMore":true,"pending":true}"#.utf8))
        XCTAssertTrue(paged.hasMore)
        XCTAssertEqual(paged.pending, true)
    }

    /// Older pages go in front, never twice.
    func testPrependDropsOverlap() {
        let held = [turn(5, user: true), turn(6, user: false)]
        let older = [turn(3, user: true), turn(4, user: false), turn(5, user: true)]
        XCTAssertEqual(ChatHistory.prepend(older, to: held).compactMap(\.id), [3, 4, 5, 6])
    }

    /// Back in the app: his last line unanswered (or the server says still
    /// writing) means keep checking; an answered one doesn't.
    func testReplyOwed() {
        XCTAssertTrue(ChatHistory.replyOwed([turn(1, user: true)], pending: nil))
        XCTAssertFalse(ChatHistory.replyOwed([turn(1, user: true), turn(2, user: false)], pending: nil))
        XCTAssertTrue(ChatHistory.replyOwed([turn(1, user: true), turn(2, user: false)], pending: true))
        XCTAssertFalse(ChatHistory.replyOwed([turn(1, user: true)], pending: false))
        XCTAssertFalse(ChatHistory.replyOwed([], pending: nil))
    }
}

final class ErrorWordingTests: XCTestCase {
    func testNoCodesOnScreen() {
        XCTAssertEqual(JarvisError.server(status: 502, message: "Jarvis answered 502").errorDescription, ErrorWording.restarting)
        XCTAssertEqual(JarvisError.unreachable.errorDescription, ErrorWording.unreachable)
        XCTAssertFalse(JarvisError.server(status: 500, message: "Jarvis answered 500").errorDescription!.contains("500"))
        XCTAssertEqual(JarvisError.server(status: 400, message: "Say what the playbook should do").errorDescription, "Say what the playbook should do")
    }

    /// Reads retry a restart or a dropped line a few times, then give up;
    /// anything else isn't retried.
    func testRetryPolicy() async throws {
        let calls = Counter()
        let value = try await RetryPolicy.run(delays: [0, 0, 0], sleep: { _ in }) { () async throws -> Int in
            let n = await calls.bump()
            if n < 3 { throw JarvisError.server(status: 502, message: "") }
            return n
        }
        XCTAssertEqual(value, 3)
        let gaveUp = Counter()
        do {
            _ = try await RetryPolicy.run(delays: [0, 0], sleep: { _ in }) { () async throws -> Int in
                _ = await gaveUp.bump(); throw JarvisError.unreachable
            }
            XCTFail("should give up")
        } catch {}
        let tries = await gaveUp.count
        XCTAssertEqual(tries, 3)
        let notRetried = Counter()
        do {
            _ = try await RetryPolicy.run(delays: [0, 0], sleep: { _ in }) { () async throws -> Int in
                _ = await notRetried.bump(); throw JarvisError.server(status: 400, message: "no")
            }
        } catch {}
        let once = await notRetried.count
        XCTAssertEqual(once, 1)
    }
}

actor Counter {
    var count = 0
    func bump() -> Int { count += 1; return count }
}

final class DeviceGroupsTests: XCTestCase {
    func testGroupsInOrderNamesAtoZUnreachableLast() throws {
        let json = #"""
        [{"id":"1","name":"WiZ RGBW Tunable 7C1A2B","kind":"light","state":"on"},
         {"id":"2","name":"Desk","kind":"light","state":"off"},
         {"id":"3","name":"Thermostat","kind":"climate","state":"off"},
         {"id":"4","name":"TV","kind":"media","state":"paused"},
         {"id":"5","name":"Dylan asleep","kind":"input_boolean","state":"off"},
         {"id":"6","name":"Porch","kind":"light","state":"unavailable"}]
        """#
        let devices = try JSONDecoder().decode([Device].self, from: Data(json.utf8))
        let groups = DeviceGroups.groups(devices)
        XCTAssertEqual(groups.map(\.title), ["Lights", "Climate", "TV and speakers", "Other", "Not responding"])
        XCTAssertEqual(groups[0].devices.map(\.name), ["Desk", "WiZ RGBW Tunable 7C1A2B"])
        XCTAssertEqual(groups.last?.devices.map(\.name), ["Porch"])
        // Every device is in the drawer, once.
        XCTAssertEqual(groups.flatMap(\.devices).count, devices.count)
    }
}

final class ChatTurnEventTests: XCTestCase {
    func testTheFirstEventCarriesHisMessagesId() {
        XCTAssertEqual(ChatEvent.parse(line: #"{"type":"turn","id":812}"#), .turn(812))
        XCTAssertNil(ChatEvent.parse(line: #"{"type":"turn"}"#))
    }
}

final class ConnectionStatusTests: XCTestCase {
    func testEachStateInWords() {
        let ok = ConnectionStatus.of(reachable: true, jarvisRestarting: false)
        XCTAssertEqual([ok.tailnetWords, ok.jarvisWords], ["Tailscale", "Jarvis"])
        XCTAssertEqual(ok.spoken, "On Tailscale. Jarvis is answering.")
        let restarting = ConnectionStatus.of(reachable: true, jarvisRestarting: true)
        XCTAssertEqual(restarting.jarvisWords, "Jarvis restarting")
        XCTAssertEqual(restarting.jarvis, .waiting)
        let off = ConnectionStatus.of(reachable: false, jarvisRestarting: false)
        XCTAssertEqual(off.tailnetWords, "Tailscale off")
        XCTAssertEqual(off.spoken, "Not on Tailscale. Jarvis can't be reached.")
        for s in [ok, restarting, off] { XCTAssertLessThanOrEqual(s.jarvisWords.split(separator: " ").count, 2) }
        XCTAssertTrue(ConnectionStatus.isJustNotAnswering(JarvisError.server(status: 502, message: "")))
        XCTAssertFalse(ConnectionStatus.isJustNotAnswering(JarvisError.server(status: 400, message: "no")))
    }
}
