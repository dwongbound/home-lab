// The app's haptic rules (JarvisKit Haptics), with a sink that records
// what would have been felt.
import XCTest
@testable import JarvisKit

@MainActor
private final class Recorder: HapticSink {
    var felt: [HapticFeel] = []
    func play(_ feel: HapticFeel) { felt.append(feel) }
}

@MainActor
final class HapticsTests: XCTestCase {
    func testATabChangeIsOneSelectionTick() {
        let sink = Recorder()
        HapticGate(sink: sink, enabled: { true }).play(.tab)
        XCTAssertEqual(sink.felt, [.selection])
    }

    func testASwipeTicksOnlyWhenItCommitsToAnotherPage() {
        // Pages 390 pt wide: Home at 0, Talk at 390, Chat at 780.
        XCTAssertTrue(PageCommit.changes(fromX: 0, toX: 390, width: 390))
        XCTAssertTrue(PageCommit.changes(fromX: 780, toX: 390, width: 390))
        // Let go part way and it springs back: no change, no tick.
        XCTAssertFalse(PageCommit.changes(fromX: 390, toX: 390, width: 390))
        // A target a hair off the page edge still reads as that page.
        XCTAssertFalse(PageCommit.changes(fromX: 390, toX: 389.6, width: 390))
        XCTAssertFalse(PageCommit.changes(fromX: 0, toX: 0, width: 0))
    }

    func testNothingWithTheSwitchOff() {
        let sink = Recorder()
        let gate = HapticGate(sink: sink, enabled: { false })
        for moment in HapticMoment.allCases { gate.play(moment) }
        gate.failed("reach")
        XCTAssertEqual(sink.felt, [])
    }

    func testNothingWhileInTheBackground() {
        let sink = Recorder()
        HapticGate(sink: sink, enabled: { true }, active: { false }).play(.replyStarts)
        XCTAssertEqual(sink.felt, [])
    }

    func testOneErrorPerFailureNotPerRetry() {
        let sink = Recorder()
        let gate = HapticGate(sink: sink, enabled: { true })
        for _ in 0..<5 { gate.failed("reach") }
        XCTAssertEqual(sink.felt, [.error])
        gate.recovered("reach")
        gate.failed("reach")
        XCTAssertEqual(sink.felt, [.error, .error], "a new failure after it worked again is felt")
    }

    func testOutcomesUseTheSystemPatterns() {
        XCTAssertEqual(HapticMoment.approve.feel, .success)
        XCTAssertEqual(HapticMoment.runOK.feel, .success)
        XCTAssertEqual(HapticMoment.runFailed.feel, .error)
        XCTAssertEqual(HapticMoment.approvalArrives.feel, .warning)
        XCTAssertEqual(HapticMoment.send.feel, .light)
        XCTAssertEqual(HapticMoment.callStarts.feel, .medium)
    }
}
