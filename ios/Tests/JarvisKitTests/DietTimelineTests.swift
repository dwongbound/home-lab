import XCTest
@testable import JarvisKit

final class DietTimelineTests: XCTestCase {
    private func day(_ date: String, items: Int) -> NutritionDay {
        let list = (0..<items).map { FoodItem(id: "\(date)-\($0)", at: "\(date)T12:10:00-08:00", name: "Food", macros: Macros(calories: 100, protein: 10)) }
        return NutritionDay(date: date, goals: Macros(calories: 1750, protein: 140), totals: Diet.totals(list), items: list)
    }

    func testTwoRings() {
        let d = WeekDay(date: "2026-11-18", calories: 2300, goal: 1750, protein: 127, proteinGoal: 140)
        XCTAssertEqual(d.ring, 1, "over: full")
        XCTAssertEqual(d.proteinRing ?? 0, 127.0 / 140, accuracy: 0.0001)
        XCTAssertEqual(WeekDay(date: "x", calories: 100, goal: 1750, protein: 150, proteinGoal: 140).proteinRing, 1, "met: full circle")
        XCTAssertNil(WeekDay(date: "x", calories: nil, goal: 1750, protein: nil, proteinGoal: 140).proteinRing, "nothing logged: empty track")
        XCTAssertNil(WeekDay(date: "x", calories: 100, goal: 1750, protein: 20, proteinGoal: nil).proteinRing, "no goal: empty track")
        XCTAssertEqual(DietTimeline.ringLabel(d), "Wednesday 18, 2300 of 1750 calories, 127 of 140 grams protein")
    }

    func testProteinFromALoadedDayWhenTheWeekHasNone() {
        let old = WeekDay(date: "2026-11-18", calories: 200, goal: 1750)
        XCTAssertEqual(old.withProtein(from: day("2026-11-18", items: 2)).protein, 20)
        XCTAssertNil(old.withProtein(from: nil).protein)
    }

    func testEmptyDaysAndRuns() {
        let days = [day("2026-11-19", items: 1), day("2026-11-18", items: 0), day("2026-11-17", items: 2),
                    day("2026-11-16", items: 0), day("2026-11-15", items: 0), day("2026-11-14", items: 0), day("2026-11-13", items: 0),
                    day("2026-11-12", items: 1)]
        let blocks = DietTimeline.blocks(days)
        XCTAssertEqual(blocks.map(\.id), ["2026-11-19", "2026-11-18", "2026-11-17", "2026-11-16", "2026-11-12"])
        XCTAssertEqual(blocks[3], .emptyRun(from: "2026-11-16", to: "2026-11-13", count: 4))
        XCTAssertEqual(blocks[1], .empty(date: "2026-11-18"))
        XCTAssertEqual(DietTimeline.block(holding: "2026-11-14", in: blocks)?.id, "2026-11-16")
        XCTAssertEqual(DietTimeline.runLabel(from: "2026-11-16", to: "2026-11-13"), "Nothing logged Nov 13 – Nov 16")
        // Three empty days stay as three rows.
        XCTAssertEqual(DietTimeline.blocks([day("a", items: 0), day("b", items: 0), day("c", items: 0)]).count, 3)
    }

    func testPaging() {
        let page = [day("2026-11-19", items: 1), day("2026-11-06", items: 1)]
        XCTAssertEqual(DietTimeline.nextEnd(after: page), "2026-11-05")
        XCTAssertTrue(DietTimeline.shouldLoadOlder(loaded: page, earliest: "2026-10-01"))
        XCTAssertFalse(DietTimeline.shouldLoadOlder(loaded: page, earliest: "2026-11-06"), "reached the first meal ever")
        let thirtyEmpty = [day("2026-11-19", items: 1)] + (1...30).map { day(Diet.shift("2026-11-19", by: -$0)!, items: 0) }
        XCTAssertFalse(DietTimeline.shouldLoadOlder(loaded: thirtyEmpty, earliest: nil))
        XCTAssertTrue(DietTimeline.shouldLoadOlder(loaded: [], earliest: nil))
    }

    func testEachEntryHasItsOwnTime() {
        let item = FoodItem(id: "1", at: "2026-11-18T20:10:00Z", name: "Chobani", macros: Macros(calories: 90))
        XCTAssertEqual(DietTimeline.timeLabel(item), "12:10 PM")
        XCTAssertEqual(DietTimeline.timeLabel(FoodItem(id: "2", at: "soon", name: "x", macros: Macros())), "")
    }

    func testTheDaysAnswer() throws {
        let json = #"{"days":[{"date":"2026-11-19","goals":{"calories":1750,"protein":140},"totals":{"calories":90},"items":[{"id":"a","at":"2026-11-19T08:00:00-08:00","name":"Yogurt","calories":90,"protein":15,"fat":0,"carbs":10}]},{"date":"2026-11-18","goals":{},"totals":{},"items":[]}],"earliest":"2026-10-02"}"#
        let decoded = try JSONDecoder().decode(NutritionDays.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.days.map(\.date), ["2026-11-19", "2026-11-18"])
        XCTAssertEqual(decoded.earliest, "2026-10-02")
        let week = try JSONDecoder().decode(WeekDay.self, from: Data(#"{"date":"2026-11-18","calories":2300,"goal":1750,"protein":127,"proteinGoal":140}"#.utf8))
        XCTAssertEqual(week.protein, 127)
    }
}

final class MealPhotosTests: XCTestCase {
    func testOnlyItemsWithPhotosAreAskedFor() throws {
        let with = try JSONDecoder().decode(FoodItem.self, from: Data(#"{"id":"m42","name":"Poke bowl","hasPhoto":true}"#.utf8))
        let without = try JSONDecoder().decode(FoodItem.self, from: Data(#"{"id":"m43","name":"Yogurt"}"#.utf8))
        XCTAssertTrue(MealPhotos.shouldFetch(with))
        XCTAssertFalse(MealPhotos.shouldFetch(without))
        XCTAssertFalse(MealPhotos.shouldFetch(FoodItem(id: "../x", at: "", name: "x", macros: Macros(), hasPhoto: true)), "unsafe id")
    }

    func testTheURLs() {
        let client = JarvisClient()
        let thumb = client.request(MealPhotos.path(id: "m42")!, query: MealPhotos.query(thumb: true))
        XCTAssertEqual(thumb.url?.absoluteString, "https://jarvis.snakebird-ph.ts.net/api/jarvis/nutrition/photo/m42?size=thumb")
        XCTAssertEqual(client.request(MealPhotos.path(id: "m42")!).url?.absoluteString, "https://jarvis.snakebird-ph.ts.net/api/jarvis/nutrition/photo/m42")
        XCTAssertNil(MealPhotos.path(id: "a/b"))
        XCTAssertEqual(MealPhotos.cacheKey(id: "m42", thumb: true), "m42-thumb")
    }
}

final class DietGoalsTests: XCTestCase {
    func testDefaultsUntilJarvisSendsThem() throws {
        let old = try JSONDecoder().decode(Macros.self, from: Data(#"{"calories":1750,"protein":140,"fat":null,"carbs":null}"#.utf8))
        let goals = DietGoals.effective(old)
        XCTAssertEqual(goals.fat, 55)
        XCTAssertEqual(goals.carbs, 175)
        let new = try JSONDecoder().decode(Macros.self, from: Data(#"{"calories":1750,"protein":140,"fatGoal":50,"carbsGoal":160}"#.utf8))
        XCTAssertEqual(DietGoals.effective(new).fat, 50)
        XCTAssertEqual(DietGoals.effective(new).carbs, 160)
        let week = try JSONDecoder().decode(WeekDay.self, from: Data(#"{"date":"2026-11-19","calories":900,"goal":1750,"fatGoal":55,"carbsGoal":175}"#.utf8))
        XCTAssertEqual(week.carbsGoal, 175)
    }

    func testLimits() {
        XCTAssertEqual(DietGoals.limitLine(eaten: 120, goal: 175)?.words, "55 g left")
        XCTAssertEqual(DietGoals.limitLine(eaten: 67, goal: 55)?.words, "12 g over")
        XCTAssertEqual(DietGoals.limitLine(eaten: 67, goal: 55)?.over, true)
        XCTAssertEqual(DietGoals.limitLine(eaten: nil, goal: 55)?.words, "55 g left")
        XCTAssertNil(DietGoals.limitLine(eaten: 10, goal: nil))
    }
}
