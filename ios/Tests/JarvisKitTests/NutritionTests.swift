import XCTest
@testable import JarvisKit

final class NutritionTests: XCTestCase {
    private func pacificToday(_ now: Date) -> String {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let p = c.dateComponents([.year, .month, .day], from: now)
        return String(format: "%04d-%02d-%02d", p.year!, p.month!, p.day!)
    }

    func testDecodesAndWords() throws {
        let s = try JSONDecoder().decode(Snapshot.self, from: Data(#"{"generatedAt":"x","services":[],"today":[],"nutrition":{"date":"2026-11-18","eaten":1180,"goal":1750,"left":570,"burned":null,"protein":96,"proteinGoal":140}}"#.utf8))
        let n = try XCTUnwrap(s.nutrition)
        XCTAssertEqual(n.leftWords, "570 left")
        XCTAssertEqual(n.ofGoalWords, "1,180 of 1,750")
        XCTAssertEqual(n.proteinWords, "96 of 140 g")
        XCTAssertEqual(n.fraction, 1180.0 / 1750, accuracy: 0.0001)
        XCTAssertEqual(Nutrition(date: "x", eaten: 1870, goal: 1750, left: -120).leftWords, "120 over")
        let older = try JSONDecoder().decode(Snapshot.self, from: Data(#"{"generatedAt":"x","services":[],"today":[],"nutrition":null}"#.utf8))
        XCTAssertNil(older.nutrition)
    }

    func testOnlyTodaysFreshNumbersShow() {
        let now = Date()
        let today = Nutrition(date: pacificToday(now), eaten: 1180, goal: 1750, left: 570)
        let fresh = ComplicationData(needCount: 0, runningCount: 0, nextTitle: nil, nextAt: nil, nutrition: today, updated: now)
        XCTAssertEqual(fresh.calories(now: now), today)
        let yesterday = ComplicationData(needCount: 0, runningCount: 0, nextTitle: nil, nextAt: nil, nutrition: Nutrition(date: "2001-01-01", eaten: 1, goal: 2, left: 1), updated: now)
        XCTAssertNil(yesterday.calories(now: now))
        let stale = ComplicationData(needCount: 0, runningCount: 0, nextTitle: nil, nextAt: nil, nutrition: today, updated: now.addingTimeInterval(-3600))
        XCTAssertNil(stale.calories(now: now))
        XCTAssertEqual(ComplicationData(dictionary: fresh.dictionary)?.nutrition, today)
    }
}
