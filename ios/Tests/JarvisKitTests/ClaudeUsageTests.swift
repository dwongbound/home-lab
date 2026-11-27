import XCTest
@testable import JarvisKit

final class ClaudeUsageTests: XCTestCase {
    /// Limits, tokens and threads come through the snapshot; rings are session then weekly.
    func testUsageAndThreadsFromTheSnapshot() throws {
        let json = """
        {"claudeUsage": {"dailyUsd": 6, "spentUsd": 1.2, "level": "ok",
          "limits": [{"name": "weekly", "usedPct": 28, "resetsAt": "2026-11-30T17:00:00Z"}, {"name": "session", "usedPct": 42, "resetsAt": null}],
          "today": [{"kind": "lookout", "usd": 0.4, "calls": 3, "tokens": 300000}, {"kind": "chat", "usd": 0, "calls": 9, "tokens": 900000}],
          "days": [{"date": "2026-11-25", "usd": 1, "tokens": 5}, {"date": "2026-11-26", "usd": 2, "tokens": null}]},
         "cloud": {"threads": [{"id": "a", "title": "Trip flights", "state": "blocked", "lastActivityAt": "2026-11-26T20:00:00Z", "url": "x"}, {"bad": true}]},
         "jobs": {"running": [], "jobs": [{"id": "n", "name": "Nightly", "status": "ok", "lastRun": null, "lastResult": null, "nextRun": "2026-11-27T11:30:00Z"}]}}
        """
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(json.utf8))
        let use = try XCTUnwrap(snapshot.claudeUsage)
        XCTAssertEqual(use.rings.map(\.name), ["session", "weekly"])
        XCTAssertTrue(use.hasTokens)
        XCTAssertEqual(use.kindsByUse.map(\.kind), ["chat", "lookout"])
        XCTAssertEqual(snapshot.threads.map(\.stateWord), ["Needs you"])
        XCTAssertEqual(snapshot.jobs?.jobs.first?.nextRun, "2026-11-27T11:30:00Z")
        // Totals: today's spend is Jarvis's own figure; the week adds the days.
        XCTAssertEqual(use.todayUSD, 1.2, accuracy: 0.001)
        XCTAssertEqual(use.weekUSD, 3, accuracy: 0.001)
        XCTAssertEqual(use.dailyAverageUSD, 1.5, accuracy: 0.001)
        XCTAssertEqual(use.dailyUsd, 6)
        XCTAssertEqual(use.todayTokens, 1_200_000)
        XCTAssertEqual(use.weekTokens, 5)
        XCTAssertEqual(use.todayCalls, 12)
        XCTAssertEqual(ClaudeUsage.dollars(0.4), "$0.40")
        XCTAssertEqual(use.monthPaceUSD, 45, accuracy: 0.001)
        XCTAssertEqual(use.busiestDay?.date, "2026-11-26")
    }

    /// An older Jarvis: no limits, no tokens, still decodes.
    func testOlderUsageHasNoRings() throws {
        let json = #"{"dailyUsd": 6, "spentUsd": 1, "level": "ok", "today": [{"kind": "nightly", "usd": 1, "calls": 1}], "days": [{"date": "2026-11-26", "usd": 1}]}"#
        let use = try JSONDecoder().decode(ClaudeUsage.self, from: Data(json.utf8))
        XCTAssertNil(use.limits)
        XCTAssertTrue(use.rings.isEmpty)
        XCTAssertFalse(use.hasTokens)
    }

    /// Words for resets, tokens, kinds and days.
    func testWords() {
        let la = TimeZone(identifier: "America/Los_Angeles")!
        let now = ISODate.parse("2026-11-26T22:00:00Z")!
        XCTAssertEqual(ClaudeUsage.resetWords("2026-11-27T02:10:00Z", now: now, timeZone: la), "Resets 6:10 PM")
        XCTAssertEqual(ClaudeUsage.resetWords("2026-11-30T17:00:00Z", now: now, timeZone: la), "Resets Mon 9 AM")
        XCTAssertNil(ClaudeUsage.resetWords(nil))
        XCTAssertEqual(ClaudeUsage.tokenWords(1_234_000), "1.2M")
        XCTAssertEqual(ClaudeUsage.tokenWords(64_000), "64K")
        XCTAssertEqual(ClaudeUsage.kindName("start_of_day"), "Start of day")
        XCTAssertEqual(ClaudeUsage.dayLetter("2026-11-26"), "T")
    }
}
