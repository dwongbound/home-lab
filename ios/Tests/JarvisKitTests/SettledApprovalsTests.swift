import XCTest
@testable import JarvisKit

final class SettledApprovalsTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func approval(_ id: String) -> Approval {
        Approval(id: id, tool: "run_command", summary: "Restart the lights", expires: "")
    }

    func testASettledIdIsNeverWaitingAgain() {
        var settled = SettledApprovals()
        settled.settle("a", line: "Denied out loud: Restart the lights", at: t0)
        // GET /approvals still lists it for a moment: it stays hidden.
        XCTAssertEqual(settled.waiting([approval("a"), approval("b")]).map(\.id), ["b"])
        XCTAssertTrue(settled.isSettled("a"))
        XCTAssertEqual(settled.line(for: "a"), "Denied out loud: Restart the lights")
    }

    func testTheFirstLineWins() {
        var settled = SettledApprovals()
        settled.settle("a", line: "Denied out loud: x", at: t0)
        settled.settle("a", line: "Timed out: x", at: t0.addingTimeInterval(5))
        XCTAssertEqual(settled.line(for: "a"), "Denied out loud: x")
    }

    func testApprovalNoticesForSettledIdsAreHidden() {
        var settled = SettledApprovals()
        settled.settle("a", line: "Approved: x", at: t0)
        let notices = [
            Notice(id: "n1", kind: .need, title: "Needs your OK", source: "jarvis", created: "", approvalId: "a"),
            Notice(id: "n2", kind: .need, title: "Needs your OK", source: "jarvis", created: "", approvalId: "b"),
            Notice(id: "n3", kind: .fyi, title: "Laundry done", source: "home", created: ""),
        ]
        XCTAssertEqual(settled.showing(notices).map(\.id), ["n2", "n3"])
    }

    func testKeptForADayAcrossRelaunch() {
        let defaults = UserDefaults(suiteName: "SettledApprovalsTests")!
        defaults.removePersistentDomain(forName: "SettledApprovalsTests")
        var settled = SettledApprovals()
        settled.settle("old", line: "Approved: x", at: t0)
        settled.settle("new", line: "Denied: y", at: t0.addingTimeInterval(20 * 60 * 60))
        settled.save(to: defaults)
        let later = SettledApprovals.load(from: defaults, now: t0.addingTimeInterval(25 * 60 * 60))
        XCTAssertFalse(later.isSettled("old"))
        XCTAssertTrue(later.isSettled("new"))
    }

    func testUnsettlePutsACardBack() {
        var settled = SettledApprovals()
        settled.settle("a", line: "Denied: x", at: t0)
        settled.unsettle("a")
        XCTAssertFalse(settled.isSettled("a"))
    }

    // MARK: The approve reply

    private func json(_ object: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    func testTakenOn200() {
        XCTAssertEqual(ApprovalReply.read(status: 200, data: json(["ok": true])), .taken)
    }

    func testThePages410() {
        let reply = ApprovalReply.read(status: 410, data: json([
            "ok": false, "gone": true, "message": "That approval is already answered no (voice)",
            "answer": ["ok": false, "by": "voice", "later": false],
        ]))
        let answer = ApprovalReply.Answer(ok: false, by: "voice")
        XCTAssertEqual(reply, .gone(message: "That approval is already answered no (voice)", answer: answer))
        XCTAssertEqual(ApprovalReply.goneLine(answer: answer, summary: "Restart the lights"), "Denied out loud: Restart the lights")
    }

    func testGoneHeldForLater() {
        let reply = ApprovalReply.read(status: 410, data: json(["gone": true, "answer": ["ok": false, "by": "voice", "later": true]]))
        guard case .gone(_, let answer) = reply else { return XCTFail() }
        XCTAssertEqual(ApprovalReply.goneLine(answer: answer, summary: "x"), "Holding for later: x")
    }

    func testGoneWithNoAnswerReadsTimedOut() {
        let reply = ApprovalReply.read(status: 410, data: json(["ok": false, "gone": true, "message": "That approval is timed out"]))
        XCTAssertEqual(reply, .gone(message: "That approval is timed out", answer: nil))
        XCTAssertEqual(ApprovalReply.goneLine(answer: nil, summary: "Restart the lights"), "Timed out: Restart the lights")
    }

    func testGoneAtAnyStatusAndBare404() {
        XCTAssertEqual(ApprovalReply.read(status: 200, data: json(["gone": true, "error": "no longer waiting"])), .gone(message: "no longer waiting", answer: nil))
        XCTAssertEqual(ApprovalReply.read(status: 404, data: Data()), .gone(message: nil, answer: nil))
    }

    func testA409IsARealError() {
        XCTAssertEqual(ApprovalReply.read(status: 409, data: json(["ok": false, "message": "Jarvis is restarting"])), .failed("Jarvis is restarting"))
        XCTAssertEqual(ApprovalReply.read(status: 500, data: Data()), .failed("Jarvis answered 500"))
    }

    // MARK: Events

    func testApprovalDoneStillSettles() {
        XCTAssertEqual(TalkEvent.parse(#"{"type":"approval_done","id":"a","ok":false,"by":"voice"}"#), .approvalDone(id: "a", ok: false, by: "voice", later: false))
    }

    func testNoAudioEvent() {
        XCTAssertEqual(TalkEvent.parse(#"{"type":"no_audio","seconds":20}"#), .noAudio(seconds: 20))
    }
}

final class MicWatchdogTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func at(_ seconds: Double) -> Date { t0.addingTimeInterval(seconds) }

    func testSteadyBuffersAreFine() {
        var dog = MicWatchdog(now: t0)
        for i in 1...10 { dog.heard(silent: false, at: at(Double(i))) }
        XCTAssertEqual(dog.check(now: at(10.5)), .fine)
    }

    func testNoBuffersMeansRestart() {
        var dog = MicWatchdog(now: t0)
        dog.heard(silent: false, at: at(1))
        XCTAssertEqual(dog.check(now: at(4)), .fine)
        XCTAssertEqual(dog.check(now: at(5.1)), .restart)
    }

    func testExactZerosMeanRestart() {
        // The tap keeps running but every sample is 0: a dead input.
        var dog = MicWatchdog(now: t0)
        dog.heard(silent: false, at: at(1))
        for i in 2...6 { dog.heard(silent: true, at: at(Double(i))) }
        XCTAssertEqual(dog.check(now: at(6)), .restart)
    }

    func testRestartGetsTimeThenGivesUpAfterTwoTries() {
        var dog = MicWatchdog(now: t0)
        XCTAssertEqual(dog.check(now: at(5)), .restart)
        dog.restarting(at: at(5))
        XCTAssertEqual(dog.check(now: at(6)), .fine, "a restart gets a moment to work")
        XCTAssertEqual(dog.check(now: at(8.5)), .restart)
        dog.restarting(at: at(8.5))
        XCTAssertEqual(dog.check(now: at(12)), .giveUp)
    }

    func testSoundComingBackResetsTheTries() {
        var dog = MicWatchdog(now: t0)
        dog.restarting(at: at(5))
        dog.restarting(at: at(9))
        dog.heard(silent: false, at: at(10))
        XCTAssertEqual(dog.tries, 0)
        XCTAssertEqual(dog.check(now: at(11)), .fine)
    }

    func testHeldDuringAnInterruption() {
        var dog = MicWatchdog(now: t0)
        dog.held = true
        XCTAssertEqual(dog.check(now: at(60)), .fine)
        dog.held = false
        XCTAssertEqual(dog.check(now: at(60)), .restart)
    }

    func testDigitalSilence() {
        let zeros: [Float] = [0, 0, 0, 0]
        let room: [Float] = [0, 0.00001, -0.00002, 0]
        zeros.withUnsafeBufferPointer { XCTAssertTrue(MicWatchdog.isDigitalSilence($0)) }
        room.withUnsafeBufferPointer { XCTAssertFalse(MicWatchdog.isDigitalSilence($0)) }
    }
}

final class PageSwipeTests: XCTestCase {
    func testSidewaysDragIsASwipe() {
        XCTAssertTrue(PageSwipe.isSideways(width: -60, height: 8))
        XCTAssertTrue(PageSwipe.isSideways(width: 40, height: -10))
    }

    func testScrollsAndTinyMovesAreNot() {
        XCTAssertFalse(PageSwipe.isSideways(width: 30, height: 40), "a scroll that drifts sideways")
        XCTAssertFalse(PageSwipe.isSideways(width: 10, height: 0), "too short")
        XCTAssertFalse(PageSwipe.isSideways(width: 50, height: 30), "not sideways enough")
    }
}
