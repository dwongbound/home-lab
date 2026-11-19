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
