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
        // Noon today, so the event an hour on is still today whatever time
        // the test runs (in the last hour of the day it used to land on
        // tomorrow, which the board leaves off by design).
        let now = Calendar.current.startOfDay(for: Date()).addingTimeInterval(12 * 3600)
        let json = #"{"generatedAt":"x","services":[],"today":[{"id":"1","at":"\#(iso(now.addingTimeInterval(3600)))","title":"Volleyball"}],"notices":[{"id":"n","kind":"need","title":"Lights off?","source":"approval","created":"","approvalId":"a1"}],"jobs":{"running":[{"id":"j","label":"Rewriting reminders","state":"running","startedAt":"2026-11-18T09:00:00Z"}]}}"#
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(json.utf8))
        let board = WatchBoard(snapshot: snapshot, now: now)
        XCTAssertEqual(board.notices.first?.approvalId, "a1")
        XCTAssertEqual(board.tasks.first?.label, "Rewriting reminders")
        XCTAssertEqual(board.nextTitle, "Volleyball")
        let reply = WatchReply(message: WatchReply.board(board).message)
        XCTAssertEqual(reply, .board(board))
    }

    func testInfoAndDevicesRoundTrip() throws {
        let json = #"{"generatedAt":"x","services":[],"notices":[{"id":"k","kind":"fyi","title":"Kept","source":"kept","created":"","kept":true}],"sleep":{"last":{"night":"2026-11-25","score":82,"minutes":{"asleep":431}},"trend":[{"night":"2026-11-25","score":82},{"night":"2026-11-24"}]},"ram":{"totalMb":18432,"usedMb":9216,"users":[]},"disks":[{"id":"c","name":"C:","usedGb":400,"totalGb":476,"users":[]}],"home":{"devices":[{"id":"light.desk","name":"Desk","kind":"light","state":"on"},{"id":"media.tv","name":"TV","kind":"media","state":"off"},{"id":"climate.hall","name":"Hall","kind":"climate","state":"heat"}]}}"#
        let board = WatchBoard(snapshot: try JSONDecoder().decode(Snapshot.self, from: Data(json.utf8)))
        XCTAssertEqual(board.kept, 1)
        XCTAssertEqual(board.orbit.map(\.kind), [.kept])
        XCTAssertEqual(board.sleepScore, 82)
        XCTAssertEqual(board.sleepTrend, [82, 0])
        XCTAssertEqual(board.pc.map(\.name), ["Memory", "C:"])
        XCTAssertEqual(board.pc.first?.usedGb, 9)
        XCTAssertEqual(board.devices.map(\.command), ["toggle", "power"])
        XCTAssertEqual(WatchBoard(message: board.message), board)
        let flip = WatchRequest.control(entity: "light.desk", command: "toggle")
        XCTAssertEqual(WatchRequest(message: flip.message), flip)
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

/// The new complications' data: sleep score, Claude usage, jobs.
final class ComplicationMoreTests: XCTestCase {
    func testRoundTripAndReadings() throws {
        var data = ComplicationData(needCount: 1, runningCount: 2, nextTitle: nil, nextAt: nil, updated: Date())
        data.runningLabels = ["Rewriting reminders", "Deal watch"]
        data.sleepScore = 82; data.sleepMinutes = 440
        data.claudeSession = 34; data.claudeWeekly = 61
        let back = try XCTUnwrap(ComplicationData(dictionary: data.dictionary))
        XCTAssertEqual(back.runningLabels, ["Rewriting reminders", "Deal watch"])
        XCTAssertEqual(back.sleep?.score, 82)
        XCTAssertEqual(back.sleep?.asleep, "7h 20m")
        XCTAssertEqual(back.claude()?.session, 34)
        XCTAssertEqual(back.claude()?.weekly, 61)
        XCTAssertEqual(back.jobs()?.count, 2)
    }

    func testStaleHidesClaudeAndJobsButKeepsSleep() {
        var data = ComplicationData(needCount: 0, runningCount: 1, nextTitle: nil, nextAt: nil, updated: Date().addingTimeInterval(-3 * 3600))
        data.sleepScore = 70; data.claudeSession = 10
        XCTAssertNil(data.claude())
        XCTAssertNil(data.jobs())
        XCTAssertEqual(data.sleep?.score, 70, "last night's score holds all day")
    }

    func testBoardCarriesClaudeLimits() throws {
        let json = #"{"generatedAt":"x","services":[],"today":[],"claudeUsage":{"limits":[{"name":"weekly","usedPct":61},{"name":"session","usedPct":34}],"today":[],"days":[]},"jobs":{"running":[{"id":"j","label":"Rewriting reminders","state":"running"}]}}"#
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(json.utf8))
        let board = WatchBoard(snapshot: snapshot)
        XCTAssertEqual(board.claudeSession, 34)
        XCTAssertEqual(board.claudeWeekly, 61)
        let again = WatchBoard(message: board.message)
        XCTAssertEqual(again.claudeSession, 34)
        XCTAssertEqual(ComplicationData(board: again).runningLabels, ["Rewriting reminders"])
    }
}
