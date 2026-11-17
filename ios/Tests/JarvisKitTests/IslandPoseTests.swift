// The Dynamic Island orb's stepped motion.
import XCTest
@testable import JarvisKit

final class IslandPoseTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)

    func testAtMostOnceASecond() {
        var pose = IslandPose()
        XCTAssertTrue(pose.tick(level: 0.5, turning: true, now: t0, reduceMotion: false))
        XCTAssertFalse(pose.tick(level: 0.9, turning: true, now: t0.addingTimeInterval(0.5), reduceMotion: false))
        XCTAssertTrue(pose.tick(level: 0.9, turning: true, now: t0.addingTimeInterval(1.0), reduceMotion: false))
        XCTAssertEqual(pose.pulse, 3)
        XCTAssertEqual(pose.beat, 2)
    }

    func testTurnsWhileLiveEvenWhenQuiet() {
        var pose = IslandPose()
        XCTAssertTrue(pose.tick(level: 0, turning: true, now: t0, reduceMotion: false))
        XCTAssertTrue(pose.tick(level: 0, turning: true, now: t0.addingTimeInterval(1), reduceMotion: false))
        XCTAssertEqual(pose.beat, 2)
    }

    func testStillWhenPausedOrMuted() {
        var pose = IslandPose()
        XCTAssertTrue(pose.tick(level: 0.8, turning: true, now: t0, reduceMotion: false))
        // Muted/paused: one update settles it to quiet, then nothing more.
        XCTAssertTrue(pose.tick(level: 0.8, turning: false, now: t0.addingTimeInterval(1), reduceMotion: false))
        XCTAssertEqual(pose.pulse, 0)
        XCTAssertFalse(pose.tick(level: 0.8, turning: false, now: t0.addingTimeInterval(2), reduceMotion: false))
    }

    func testReduceMotionSendsNothing() {
        var pose = IslandPose()
        XCTAssertFalse(pose.tick(level: 0.8, turning: true, now: t0, reduceMotion: true))
    }
}
