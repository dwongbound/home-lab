// Message times and day lines in Chat (JarvisKit ChatTime).
import XCTest
@testable import JarvisKit

final class ChatTimeTests: XCTestCase {
    private func calendar(_ zone: String) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: zone)!
        return c
    }
    private func at(_ text: String, _ zone: String = "America/Los_Angeles") -> Date {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: zone)!
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: text)!
    }
    private let la = "America/Los_Angeles"

    func testTheClock() {
        XCTAssertEqual(ChatTime.clock(at("2026-11-20 19:32"), calendar: calendar(la)), "7:32 PM")
        XCTAssertEqual(ChatTime.clock(at("2026-11-20 00:05"), calendar: calendar(la)), "12:05 AM")
    }

    func testDayWords() {
        let now = at("2026-11-20 19:32")
        let c = calendar(la)
        XCTAssertEqual(ChatTime.dayLabel(at("2026-11-20 00:00"), now: now, calendar: c), "Today")
        XCTAssertEqual(ChatTime.dayLabel(at("2026-11-19 23:59"), now: now, calendar: c), "Yesterday")
        XCTAssertEqual(ChatTime.dayLabel(at("2026-11-18 12:00"), now: now, calendar: c), "Wednesday")
        XCTAssertEqual(ChatTime.dayLabel(at("2026-11-14 12:00"), now: now, calendar: c), "Saturday")
        XCTAssertEqual(ChatTime.dayLabel(at("2026-11-13 12:00"), now: now, calendar: c), "Fri, Nov 13")
        XCTAssertEqual(ChatTime.dayLabel(at("2025-12-31 12:00"), now: at("2026-01-10 09:00"), calendar: c), "Wed, Dec 31, 2025", "another year says so")
        XCTAssertEqual(ChatTime.dayLabel(at("2025-12-31 23:30"), now: at("2026-01-01 08:00"), calendar: c), "Yesterday", "across New Year")
    }

    func testDayLinesAtMidnight() {
        let c = calendar(la)
        let dates: [Date?] = [at("2026-11-19 23:58"), at("2026-11-19 23:59"), nil, at("2026-11-20 00:00"), at("2026-11-20 08:00")]
        XCTAssertEqual(ChatTime.dayBreaks(dates, calendar: c), [true, false, false, true, false])
        XCTAssertEqual(ChatTime.dayBreaks([nil, at("2026-11-20 08:00")], calendar: c), [false, true], "the first dated message gets one")
        XCTAssertEqual(ChatTime.dayBreaks([], calendar: c), [])
    }

    func testTheDeviceTimeZoneDecides() {
        // 11 PM in Los Angeles is the next morning in Tokyo.
        let a = at("2026-11-19 22:00"), b = at("2026-11-19 23:30")
        XCTAssertEqual(ChatTime.dayBreaks([a, b], calendar: calendar(la)), [true, false])
        XCTAssertEqual(ChatTime.dayBreaks([a, b], calendar: calendar("Asia/Tokyo")), [true, false])
        let c = at("2026-11-20 06:30")
        XCTAssertEqual(ChatTime.dayBreaks([b, c], calendar: calendar(la)), [true, true])
        XCTAssertEqual(ChatTime.dayBreaks([b, c], calendar: calendar("Asia/Tokyo")), [true, false], "both on Nov 20 in Tokyo")
    }
}

final class NoticeFullTextTests: XCTestCase {
    func testAWireCutNoticeGetsItsWholeTextFromTheTurn() {
        let title = String(repeating: "t", count: 20) + " lesson…"
        let body = String(repeating: "b", count: 300)
        let turn = String(repeating: "t", count: 20) + " lesson at ten, with more words\n" + body + " and the rest of it."
        let full = NoticeFullText.from(turn: turn, title: title, body: body)
        XCTAssertEqual(full?.title, String(repeating: "t", count: 20) + " lesson at ten, with more words")
        XCTAssertTrue(full?.body.hasSuffix("the rest of it.") ?? false)
    }

    func testNothingMoreMeansTheNoticeAsItIs() {
        XCTAssertNil(NoticeFullText.from(turn: "Hi\nThere", title: "Hi", body: "There"))
    }

    func testATurnThatDoesNotStartWithTheTitleIsAllBody() {
        let full = NoticeFullText.from(turn: String(repeating: "x", count: 400), title: "Heads up", body: "short")
        XCTAssertEqual(full?.title, "Heads up")
        XCTAssertEqual(full?.body.count, 400)
    }
}
