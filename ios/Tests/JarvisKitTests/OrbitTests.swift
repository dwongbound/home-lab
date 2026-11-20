import XCTest
@testable import JarvisKit

final class OrbitTests: XCTestCase {
    private let tasks = [RunningTask(id: "j1", label: "Rewriting reminders", state: "running", startedAt: "2026-11-18T09:00:00Z")]
    private let notices = [
        Notice(id: "f", kind: .fyi, title: "Done", source: "job", created: ""),
        Notice(id: "n", kind: .need, title: "Turn off lights?", source: "approval", created: "", approvalId: "a1"),
    ]

    func testNoticesAreOrangeFirstAndTasksBlue() {
        let items = Orbit.items(running: tasks, notices: notices)
        XCTAssertEqual(items.map(\.kind), [.notice, .notice, .task])
        XCTAssertEqual(items.first?.notice?.kind, .need, "needs lead")
        XCTAssertEqual(items.first?.emphasis, 1)
        XCTAssertEqual(items[1].emphasis, 0.7)
        XCTAssertEqual(items.last?.title, "Rewriting reminders")
    }

    func testNightShowsOnlyNeeds() {
        let items = Orbit.items(running: tasks, notices: notices, night: true)
        XCTAssertEqual(items.map(\.id), ["notice-n"])
    }

    func testOneDotForEveryNoticeAndTask() {
        let many = (0..<13).map { Notice(id: "\($0)", kind: .fyi, title: "x", source: "job", created: "") }
        let items = Orbit.items(running: tasks, notices: many)
        XCTAssertEqual(items.filter { $0.kind == .notice }.count, 13)
        XCTAssertEqual(items.count, 14)
    }

    func testEveryDotStaysInsideTheOrbsFrame() {
        let side = 300.0
        // The working shell, swollen by a voice: 0.42 of the side, plus 11%.
        let scale = Orbit.scale(shellRadius: side * 0.42 * 1.11, side: side)
        for i in 0..<40 {
            let path = Orbit.path(for: "notice-\(i)")
            XCTAssertLessThanOrEqual(path.radius, Orbit.widest)
            for t in stride(from: 0.0, to: 30, by: 0.7) {
                let p = Orbit.position(path, t: t)
                XCTAssertLessThanOrEqual(abs(p.x * scale), side * Orbit.reach + 0.0001)
                XCTAssertLessThanOrEqual(abs(p.y * scale), side * Orbit.reach + 0.0001)
            }
        }
        // A small shell is left as it is.
        XCTAssertEqual(Orbit.scale(shellRadius: 90, side: side), 90)
    }

    func testPathsAreStableAndDiffer() {
        XCTAssertEqual(Orbit.path(for: "task-j1"), Orbit.path(for: "task-j1"))
        XCTAssertNotEqual(Orbit.path(for: "task-j1"), Orbit.path(for: "notice-n"))
        let p = Orbit.path(for: "task-j1")
        XCTAssertGreaterThan(p.radius, 1.1)
        XCTAssertGreaterThan(abs(p.speed), 0.2)
    }

    func testADotGoesBehindAndInFront() {
        let path = Orbit.path(for: "notice-n")
        let zs = stride(from: 0.0, to: 60, by: 0.5).map { Orbit.position(path, t: $0).z }
        XCTAssertLessThan(zs.min() ?? 0, -0.3)
        XCTAssertGreaterThan(zs.max() ?? 0, 0.3)
        // Always outside the shell.
        for t in stride(from: 0.0, to: 30, by: 0.7) {
            let p = Orbit.position(path, t: t)
            XCTAssertEqual((p.x * p.x + p.y * p.y + p.z * p.z).squareRoot(), path.radius, accuracy: 0.0001)
        }
    }

    func testTimerAndReadingRules() {
        let now = ISO8601DateFormatter().date(from: "2026-11-18T09:12:05Z")!
        XCTAssertEqual(Orbit.elapsed(since: "2026-11-18T09:00:00Z", now: now), "12:05")
        XCTAssertEqual(Orbit.elapsed(since: "2026-11-18T07:59:55Z", now: now), "1:12:10")
        XCTAssertNil(Orbit.elapsed(since: nil, now: now))
        XCTAssertFalse(Orbit.readOnView(notices[1]), "needs stay until answered")
        XCTAssertTrue(Orbit.readOnView(notices[0]))
        XCTAssertEqual(Orbit.refreshSeconds(orangeShowing: true), 5)
        XCTAssertEqual(Orbit.refreshSeconds(orangeShowing: false), 15)
    }
}

final class OrbHitTests: XCTestCase {
    private let dots = [(id: "notice-a", x: 150.0, y: 100.0), (id: "task-b", x: 120.0, y: 160.0)]

    func testADotWinsEvenOverTheOrb() {
        // (125, 150) is inside the orb and within reach of task-b.
        XCTAssertEqual(OrbHit.resolve(x: 125, y: 150, dots: dots, centerX: 150, centerY: 150, coreRadius: 60, frozen: false), .dot("task-b"))
        XCTAssertEqual(OrbHit.resolve(x: 160, y: 110, dots: dots, centerX: 150, centerY: 150, coreRadius: 60, frozen: false), .dot("notice-a"))
    }

    func testTheInnerOrbOffAnyDotIsTalk() {
        XCTAssertEqual(OrbHit.resolve(x: 175, y: 175, dots: dots, centerX: 150, centerY: 150, coreRadius: 60, frozen: false), .core)
        XCTAssertEqual(OrbHit.resolve(x: 290, y: 290, dots: dots, centerX: 150, centerY: 150, coreRadius: 60, frozen: false), .nothing)
    }

    func testWhileHeldATapElsewhereReleasesAndAnotherDotSwitches() {
        XCTAssertEqual(OrbHit.resolve(x: 175, y: 175, dots: dots, centerX: 150, centerY: 150, coreRadius: 60, frozen: true), .release)
        XCTAssertEqual(OrbHit.resolve(x: 151, y: 101, dots: dots, centerX: 150, centerY: 150, coreRadius: 60, frozen: true), .dot("notice-a"))
    }

    func testReachIsAtLeastTheMinimumTarget() {
        XCTAssertGreaterThanOrEqual(OrbHit.dotReach * 2, 44)
    }
}
