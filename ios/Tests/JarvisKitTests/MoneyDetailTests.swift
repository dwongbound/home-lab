import XCTest
@testable import JarvisKit

final class MoneyDetailTests: XCTestCase {
    private let json = """
    {"cloud": {"money": {"netWorth": 1, "spending": null, "flags": [],
      "accounts": [{"id": "a", "name": "Checking", "kind": "cash", "balance": 900},
                   {"id": "b", "name": "Old", "kind": "cash", "balance": 0},
                   {"id": "c", "name": "Card", "kind": "credit", "balance": 120}],
      "categories": [{"name": "Food", "spent": 10, "budget": null}, {"name": "Other", "spent": 5, "budget": null}],
      "recent": [{"id": "t1", "date": "2026-11-24", "merchant": "Cafe", "category": "Other", "amount": 12.4},
                 {"id": "t2", "date": "2026-11-24", "merchant": "Pay", "category": "", "amount": -2000, "type": "income"},
                 {"id": "t3", "date": "2026-11-23", "merchant": "Move", "category": "", "amount": 50, "type": "transfer"},
                 {"id": "t4", "date": "2026-11-23", "merchant": "Shop", "amount": 30},
                 {"id": "t5", "date": "2026-11-22", "merchant": "Gas", "category": "Car", "amount": 40}]}},
     "moneyPicks": {"picks": [{"id": "t4", "category": "Gifts", "merchant": "Shop", "date": "2026-11-23", "amount": 30, "pickedAt": "x"}], "remindAt": null}}
    """

    /// Unsorted purchases skip money in, transfers and ones already picked.
    func testToSortAndChoices() throws {
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(json.utf8))
        let money = try XCTUnwrap(snapshot.money)
        XCTAssertEqual(snapshot.moneyPicks.map(\.category), ["Gifts"])
        XCTAssertEqual(money.stillToPick(snapshot.moneyPicks).map(\.id), ["t1"])
        XCTAssertEqual(money.categoryChoices(snapshot.moneyPicks), ["Food", "Gifts"])
    }

    /// Accounts group by kind with empty ones left out; amounts read with cents.
    func testAccountsAndAmounts() throws {
        let money = try XCTUnwrap(try JSONDecoder().decode(Snapshot.self, from: Data(json.utf8)).money)
        XCTAssertEqual(money.accountGroups.map(\.label), ["Cash", "Cards"])
        XCTAssertEqual(money.accountGroups.first?.accounts.map(\.name), ["Checking"])
        XCTAssertEqual(Money.amount(12.4), "$12.40")
        XCTAssertEqual(Money.amount(-2000), "+$2,000.00")
    }

    /// Pace and per-day room on the 10th of a 30-day month.
    func testPaceAndLeftPerDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 10))!
        let json = #"{"thisMonth": 1200, "budget": 3000}"#
        let spending = try JSONDecoder().decode(Money.Spending.self, from: Data(json.utf8))
        XCTAssertEqual(spending.pace(now: now, calendar: calendar)!, 1000, accuracy: 0.01)
        XCTAssertEqual(spending.aheadOfPace(now: now, calendar: calendar)!, 200, accuracy: 0.01)
        XCTAssertEqual(spending.leftPerDay(now: now, calendar: calendar)!, 1800.0 / 21, accuracy: 0.01)
        let none = try JSONDecoder().decode(Money.Spending.self, from: Data(#"{"thisMonth": 5}"#.utf8))
        XCTAssertNil(none.pace(now: now, calendar: calendar))
    }
}

