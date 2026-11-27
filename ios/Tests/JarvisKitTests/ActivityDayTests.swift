import XCTest
@testable import JarvisKit

final class ActivityDayTests: XCTestCase {
    private var la: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }

    /// Fourteen keys ending today, oldest first; headings read like people talk.
    func testKeysAndWords() {
        let now = ISODate.parse("2026-11-27T00:30:00Z")! // 4:30 PM Nov 26 in LA
        let keys = ActivityDay.keys(count: 14, now: now, calendar: la)
        XCTAssertEqual(keys.count, 14)
        XCTAssertEqual(keys.last, "2026-11-26")
        XCTAssertEqual(keys.first, "2026-11-13")
        XCTAssertEqual(ActivityDay.heading("2026-11-26", now: now, calendar: la), "Today")
        XCTAssertEqual(ActivityDay.heading("2026-11-25", now: now, calendar: la), "Yesterday")
        XCTAssertEqual(ActivityDay.heading("2026-11-24", now: now, calendar: la), "Tuesday, Nov 24")
        XCTAssertEqual(ActivityDay.weekday("2026-11-26", calendar: la), "Th")
        XCTAssertEqual(ActivityDay.dayNumber("2026-11-06"), "6")
    }

    /// Rings fill against goals (Exercise 30 and Stand 12 by default) and count as closed at full.
    func testRingsAndAverages() {
        var day = ActivityDay(day: "2026-11-26")
        XCTAssertFalse(day.recorded)
        day.moveKcal = 600; day.moveGoal = 500
        day.exerciseMin = 15
        day.standHours = 12
        day.steps = 8000
        XCTAssertEqual(day.rings, [1, 0.5, 1])
        XCTAssertEqual(day.ringsClosed, 2)
        var other = ActivityDay(day: "2026-11-25")
        other.steps = 4001
        XCTAssertEqual(ActivityDay.averageSteps([day, other, ActivityDay(day: "2026-11-24")]), 6001)
        XCTAssertNil(ActivityDay.averageSteps([]))
    }
}
