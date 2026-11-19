import XCTest
@testable import JarvisKit

final class DietTests: XCTestCase {
    private func item(_ id: String, _ at: String, kcal: Double?, p: Double? = nil, f: Double? = nil, c: Double? = nil) -> FoodItem {
        FoodItem(id: id, at: at, name: "Food \(id)", macros: Macros(calories: kcal, protein: p, fat: f, carbs: c))
    }

    func testHoursGroupInPacificTimeAndSkipEmptyOnes() {
        let items = [
            item("a", "2026-11-18T12:20:00-08:00", kcal: 675, p: 54, f: 24, c: 67),
            item("b", "2026-11-18T12:45:00-08:00", kcal: 236, p: 4, f: 10, c: 34),
            // 22:05 UTC is 2:05 PM Pacific.
            item("c", "2026-11-18T22:05:00Z", kcal: 140, p: 1, f: 0, c: 34),
        ]
        let hours = Diet.hours(items)
        XCTAssertEqual(hours.map(\.label), ["12 PM", "2 PM"])
        XCTAssertEqual(hours[0].totals, Macros(calories: 911, protein: 58, fat: 34, carbs: 101))
    }

    func testAnItemAfterMidnightIsTwelveAM() {
        let hours = Diet.hours([item("late", "2026-11-19T00:30:00-08:00", kcal: 200)])
        XCTAssertEqual(hours.first?.label, "12 AM")
        XCTAssertEqual(hours.first?.hour, 0)
    }

    func testAnUnreadableTimeStillShows() {
        let hours = Diet.hours([item("a", "2026-11-18T09:00:00-08:00", kcal: 100), item("b", "soon", kcal: 50)])
        XCTAssertEqual(hours.count, 1)
        XCTAssertEqual(hours[0].items.map(\.id), ["a", "b"])
    }

    func testTotalsSkipMissingValues() {
        let t = Diet.totals([item("a", "", kcal: 100, p: 10), item("b", "", kcal: nil, p: 5)])
        XCTAssertEqual(t.calories, 100)
        XCTAssertEqual(t.protein, 15)
        XCTAssertNil(t.fat, "no item has fat")
    }

    func testFractionsAndOverGoal() {
        XCTAssertEqual(Diet.fraction(875, of: 1750), 0.5)
        XCTAssertEqual(Diet.fraction(135, of: 118), 1, "full when over")
        XCTAssertTrue(Diet.isOver(135, goal: 118))
        XCTAssertNil(Diet.fraction(50, of: nil), "no goal, no bar")
        XCTAssertNil(Diet.fraction(nil, of: 1750))
        XCTAssertNil(WeekDay(date: "2026-11-20", calories: nil, goal: 1750).ring, "nothing logged is an empty ring, not zero")
    }

    func testTheDayDecodesWithNullsAndOddIds() throws {
        let json = #"{"day":{"date":"2026-11-18","goals":{"calories":1750,"protein":140,"fat":null,"carbs":null},"totals":{"calories":1051,"protein":null,"fat":34,"carbs":135,"burned":0.4},"items":[{"id":7,"at":"2026-11-18T12:20:00-08:00","name":"Chicken Burrito Bowl","portion":"1 bowl","calories":675,"protein":54,"fat":24,"carbs":67,"hasPhoto":true},{"id":"x","name":"Chips","portion":null,"calories":null,"protein":4,"fat":10,"carbs":34},{"name":"no id"}]}}"#
        struct Body: Decodable { let day: NutritionDay? }
        let day = try XCTUnwrap(try JSONDecoder().decode(Body.self, from: Data(json.utf8)).day)
        XCTAssertEqual(day.items.map(\.id), ["7", "x"])
        XCTAssertNil(day.goals.fat)
        XCTAssertEqual(day.totals.protein, 58, "a missing total is added up from the items")
        XCTAssertEqual(day.totals.calories, 1051)
        XCTAssertEqual(day.burned, 0.4)
        XCTAssertNil(day.items[1].portion)
        let older = try JSONDecoder().decode(Body.self, from: Data(#"{"day":null}"#.utf8))
        XCTAssertNil(older.day)
    }

    func testTheWeekAndDates() throws {
        struct Body: Decodable { let week: NutritionWeek? }
        let json = #"{"week":{"start":"2026-11-16","days":[{"date":"2026-11-16","calories":1620,"goal":1750},{"date":"2026-11-17","calories":null,"goal":1750}]}}"#
        let week = try XCTUnwrap(try JSONDecoder().decode(Body.self, from: Data(json.utf8)).week)
        XCTAssertEqual(week.days.count, 2)
        XCTAssertNil(week.days[1].calories)
        XCTAssertEqual(Diet.weekStart(of: "2026-11-18"), "2026-11-16", "Monday first")
        XCTAssertEqual(Diet.weekStart(of: "2026-11-22"), "2026-11-16", "Sunday belongs to the week before")
        XCTAssertEqual(Diet.weekdayInitials("2026-11-18"), "We")
        XCTAssertEqual(Diet.dayNumber("2026-11-08"), "8")
        XCTAssertEqual(Diet.shift("2026-11-30", by: 1), "2026-12-01")
        XCTAssertEqual(Diet.hourLabel(0), "12 AM")
        XCTAssertEqual(Diet.hourLabel(13), "1 PM")
        XCTAssertEqual(Diet.macroLine(Macros(calories: 675, protein: 54, fat: 24, carbs: 67)), "54P 24F 67C")
        XCTAssertEqual(Diet.macroLine(Macros(protein: 54)), "54P")
    }

    func testTitles() {
        let now = ISO8601DateFormatter().date(from: "2026-11-18T20:00:00Z")!
        XCTAssertEqual(Diet.title("2026-11-18", now: now), "Today")
        XCTAssertEqual(Diet.title("2026-11-17", now: now), "Yesterday")
        XCTAssertEqual(Diet.title("2026-11-16", now: now), "Mon, Nov 16")
    }

    func testTheQueryIsNotEscaped() {
        let request = JarvisClient().request("api/jarvis/nutrition/day", query: ["date": "2026-11-18"])
        XCTAssertEqual(request.url?.absoluteString, "https://jarvis.snakebird-ph.ts.net/api/jarvis/nutrition/day?date=2026-11-18")
    }
}
