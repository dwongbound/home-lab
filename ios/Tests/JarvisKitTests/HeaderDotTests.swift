import XCTest
@testable import JarvisKit

final class HeaderDotTests: XCTestCase {
    private func notice(_ id: String, _ kind: NoticeKind) -> Notice {
        Notice(id: id, kind: kind, title: "x", source: "job", created: "")
    }

    func testOneDotHoweverManyAndNoneForNone() {
        XCTAssertNil(Notices.headerDot([]))
        let four = [notice("a", .fyi), notice("b", .heads), notice("c", .fyi), notice("d", .heads)]
        XCTAssertEqual(Notices.headerDot(four), .heads, "one dot, in the most urgent one's shade")
        XCTAssertEqual(Notices.headerDot(four + [notice("e", .need)]), .need)
        XCTAssertEqual(Notices.countLabel(four), "4 new", "the count still says how many")
    }
}

final class KeepDotTests: XCTestCase {
    func testKeepIsOfferedOnlyWhereClosingWouldClear() {
        XCTAssertTrue(Orbit.offersKeep(Notice(id: "a", kind: .heads, title: "Laundry done", source: "alert", created: "")))
        XCTAssertTrue(Orbit.offersKeep(Notice(id: "b", kind: .fyi, title: "x", source: "job", created: "")))
        XCTAssertFalse(Orbit.offersKeep(Notice(id: "c", kind: .need, title: "x", source: "lookout", created: "")), "a need stays until answered anyway")
        XCTAssertFalse(Orbit.offersKeep(Notice(id: "d", kind: .need, title: "x", source: "approval", created: "", approvalId: "ap")))
    }
}

final class StatusButtonTests: XCTestCase {
    private let unread = [Notice(id: "a", kind: .heads, title: "x", source: "job", created: "")]

    func testOrangeBlueOrBoth() {
        XCTAssertNil(Notices.statusButton(unread: [], running: 0))
        let both = Notices.statusButton(unread: unread, running: 2)
        XCTAssertEqual(both?.orange, .heads)
        XCTAssertEqual(both?.blue, true)
        XCTAssertEqual(both?.words, "1 new · 2 running")
        let onlyRunning = Notices.statusButton(unread: [], running: 1)
        XCTAssertNil(onlyRunning?.orange)
        XCTAssertEqual(onlyRunning?.words, "1 running")
        XCTAssertEqual(Notices.statusButton(unread: unread, running: 0)?.blue, false)
    }
}


final class RecentlyFinishedTests: XCTestCase {
    func testDoneAndFailedNewestFirst() throws {
        let json = #"{"running":[],"jobs":[{"id":"lookout","name":"Lookout","status":"ok","lastRun":"2026-11-19T02:20:01-08:00","lastResult":"Checked calendar"},{"id":"nightly","name":"Nightly","status":"error","lastRun":"2026-11-19T00:30:00-08:00","lastResult":"Failed"},{"id":"old","name":"Old","status":"ok","lastRun":"2026-11-10T00:00:00-08:00"},{"id":"run","name":"Busy","status":"running","lastRun":"2026-11-19T02:00:00-08:00"},{"name":"bad"}]}"#
        let jobs = try JSONDecoder().decode(Jobs.self, from: Data(json.utf8))
        let now = ISO8601DateFormatter().date(from: "2026-11-19T11:00:00Z")!
        let recent = jobs.recentlyFinished(now: now)
        XCTAssertEqual(recent.map(\.job.id), ["lookout", "nightly"])
        XCTAssertEqual(recent.map(\.word), ["Done", "Failed"])
    }
}

final class JobChipTests: XCTestCase {
    func testAChipWhenAModelIsDoingIt() throws {
        let running = try JSONDecoder().decode(RunningTask.self, from: Data(#"{"id":"a","label":"Adding your calendar","state":"running","model":"claude-opus-5-5"}"#.utf8))
        XCTAssertEqual(ModelWording.jobChip(running.model)?.label, "Jarvis (CO)")
        XCTAssertEqual(ModelWording.jobChip("claude-fable-5-2")?.label, "Jarvis (CF)")
        XCTAssertEqual(ModelWording.jobChip("ornith-1.5:9b")?.label, "Jarvis (O)")
        XCTAssertEqual(Orbit.items(running: [running], notices: []).first?.model, "claude-opus-5-5")
    }

    func testNoChipForPlainCode() throws {
        let plain = try JSONDecoder().decode(RunningTask.self, from: Data(#"{"id":"b","label":"Disk check","state":"running"}"#.utf8))
        XCTAssertNil(plain.model)
        XCTAssertNil(ModelWording.jobChip(plain.model))
        XCTAssertNil(ModelWording.jobChip("  "))
        let job = try JSONDecoder().decode(JobRecord.self, from: Data(#"{"id":"disk","name":"Disk space check","status":"ok","model":null}"#.utf8))
        XCTAssertNil(ModelWording.jobChip(job.model))
    }
}

final class StageLineTests: XCTestCase {
    func testTheStageOrTheStatus() throws {
        let staged = try JSONDecoder().decode(RunningTask.self, from: Data(#"{"id":"a","label":"Fix reminders","state":"running","step":"Running tests"}"#.utf8))
        XCTAssertEqual(staged.stepLine(), "Running tests")
        XCTAssertEqual(Orbit.items(running: [staged], notices: []).first?.detail, "Running tests")
        let plain = RunningTask(id: "b", label: "x", state: "queued")
        XCTAssertNil(plain.step)
        XCTAssertEqual(plain.stepLine(), "Queued")
        XCTAssertEqual(RunningTask(id: "c", label: "x", state: "running", step: "  ").stepLine(), "Running")
    }
}

final class FinishedJobsTests: XCTestCase {
    func testFinishedWordsAndFallback() throws {
        let json = #"{"running":[{"id":"q","label":"Next","state":"queued"}],"finished":[{"id":"a","label":"Dive calendar","state":"live","finishedAt":"2026-11-19T03:10:00-08:00","model":"claude-opus-5-5"},{"id":"b","label":"Fix","state":"failed"},{"id":"c","label":"Check","state":"nothing"}],"jobs":[{"id":"lookout","name":"Lookout","status":"ok","lastRun":"2026-11-19T02:20:01-08:00"}]}"#
        let jobs = try JSONDecoder().decode(Jobs.self, from: Data(json.utf8))
        XCTAssertTrue(jobs.running[0].isQueued)
        XCTAssertEqual(jobs.finishedRows().map(\.word), ["Live", "Failed", "No change needed"])
        XCTAssertEqual(jobs.finishedRows().first?.model, "claude-opus-5-5")
        // An older Jarvis: no finished list at all, so the jobs' last runs.
        let older = try JSONDecoder().decode(Jobs.self, from: Data(#"{"running":[],"jobs":[{"id":"lookout","name":"Lookout","status":"ok","lastRun":"2026-11-19T02:20:01-08:00"}]}"#.utf8))
        XCTAssertNil(older.finished)
        let now = ISO8601DateFormatter().date(from: "2026-11-19T11:00:00Z")!
        XCTAssertEqual(older.finishedRows(now: now).map(\.word), ["Done"])
        // An empty finished list stays empty (no fallback).
        XCTAssertEqual(try JSONDecoder().decode(Jobs.self, from: Data(#"{"running":[],"finished":[],"jobs":[{"id":"x","name":"X","status":"ok","lastRun":"2026-11-19T02:20:01-08:00"}]}"#.utf8)).finishedRows(now: now).count, 0)
    }
}
