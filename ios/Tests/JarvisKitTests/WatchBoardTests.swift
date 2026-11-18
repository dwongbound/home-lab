import XCTest
@testable import JarvisKit

final class WatchBoardTests: XCTestCase {
    private func iso(_ d: Date) -> String { ISO8601DateFormatter().string(from: d) }

    func testNewRequestsRoundTrip() {
        XCTAssertEqual(WatchRequest(message: WatchRequest.board.message), .board)
        XCTAssertEqual(WatchRequest(message: WatchRequest.clear(["a", "b"]).message), .clear(["a", "b"]))
        XCTAssertEqual(WatchRequest(message: WatchRequest.clear([]).message), .clear([]))
    }

    func testBoardFromASnapshotAndBack() throws {
        let now = Date()
        let json = #"{"generatedAt":"x","services":[],"today":[{"id":"1","at":"\#(iso(now.addingTimeInterval(3600)))","title":"Volleyball"}],"notices":[{"id":"n","kind":"need","title":"Lights off?","source":"approval","created":"","approvalId":"a1"}],"jobs":{"running":[{"id":"j","label":"Rewriting reminders","state":"running","startedAt":"2026-11-18T09:00:00Z"}]}}"#
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(json.utf8))
        let board = WatchBoard(snapshot: snapshot, now: now)
        XCTAssertEqual(board.notices.first?.approvalId, "a1")
        XCTAssertEqual(board.tasks.first?.label, "Rewriting reminders")
        XCTAssertEqual(board.nextTitle, "Volleyball")
        let reply = WatchReply(message: WatchReply.board(board).message)
        XCTAssertEqual(reply, .board(board))
    }

    func testComplicationWordsAndStaleness() {
        let now = Date()
        let board = WatchBoard(notices: [WatchNotice(Notice(id: "n", kind: .need, title: "x", source: "approval", created: ""))], tasks: [("t", nil)], nextTitle: "Volleyball", nextAt: iso(now.addingTimeInterval(1800)))
        let data = ComplicationData(board: board, updated: now)
        XCTAssertEqual(data.summary(now: now), "1 need you · 1 running")
        XCTAssertEqual(data.nextLine(now: now)?.title, "Volleyball")
        XCTAssertEqual(ComplicationData(dictionary: data.dictionary)?.needCount, 1)
        let old = ComplicationData(board: WatchBoard(), updated: now.addingTimeInterval(-3600))
        XCTAssertEqual(old.summary(now: now), "Open Jarvis to update")
        XCTAssertNil(old.nextLine(now: now))
        XCTAssertEqual(ComplicationData(board: WatchBoard(), updated: now).summary(now: now), "All clear")
    }
}

final class ComplicationStoreTests: XCTestCase {
    func testSavesAndLoads() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        XCTAssertNil(ComplicationStore.load(defaults: defaults))
        let data = ComplicationData(needCount: 2, runningCount: 1, nextTitle: "Dentist", nextAt: nil, updated: Date(timeIntervalSince1970: 100))
        ComplicationStore.save(data, defaults: defaults)
        XCTAssertEqual(ComplicationStore.load(defaults: defaults), data)
    }
}
