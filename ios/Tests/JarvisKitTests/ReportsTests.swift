import XCTest
@testable import JarvisKit

final class ReportsTests: XCTestCase {
    private let base = URL(string: "https://jarvis.snakebird-ph.ts.net")!

    func testIdShape() {
        XCTAssertTrue(Reports.isId("0123456789abcdef"))
        XCTAssertFalse(Reports.isId("0123456789ABCDEF"), "uppercase")
        XCTAssertFalse(Reports.isId("0123456789abcde"), "15 long")
        XCTAssertFalse(Reports.isId("0123456789abcdef0"), "17 long")
        XCTAssertFalse(Reports.isId("../../etc/passwd"))
        XCTAssertFalse(Reports.isId("0123456789abcdeg"))
    }

    func testURLIsBuiltOnlyFromAGoodId() {
        XCTAssertEqual(Reports.url(id: "0123456789abcdef", base: base)?.absoluteString, "https://jarvis.snakebird-ph.ts.net/reports/0123456789abcdef")
        XCTAssertNil(Reports.url(id: "bad", base: base))
    }

    func testOnlySameHostReportLinksOpenInTheApp() {
        let ours = URL(string: "https://jarvis.snakebird-ph.ts.net/reports/0123456789abcdef")!
        XCTAssertEqual(Reports.inAppURL(for: ours, base: base), ours)
        // Elsewhere, other paths and bad ids open as links always have.
        XCTAssertNil(Reports.inAppURL(for: URL(string: "https://example.com/reports/0123456789abcdef")!, base: base))
        XCTAssertNil(Reports.inAppURL(for: URL(string: "https://jarvis.snakebird-ph.ts.net/api/snapshot")!, base: base))
        XCTAssertNil(Reports.inAppURL(for: URL(string: "https://jarvis.snakebird-ph.ts.net/reports/0123456789abcdef/x")!, base: base))
        XCTAssertNil(Reports.inAppURL(for: URL(string: "https://jarvis.snakebird-ph.ts.net/reports/NOTHEX")!, base: base))
        XCTAssertNil(Reports.inAppURL(for: URL(string: "http://jarvis.snakebird-ph.ts.net.evil.com/reports/0123456789abcdef")!, base: base))
    }

    func testNoticeAndPushCarryTheReport() throws {
        let json = #"{"id":"n1","kind":"heads","title":"Report ready: Disk","body":"All fine","source":"job","reportId":"0123456789abcdef"}"#
        let notice = try JSONDecoder().decode(Notice.self, from: Data(json.utf8))
        XCTAssertEqual(notice.reportURL(base: base)?.path, "/reports/0123456789abcdef")
        let bad = try JSONDecoder().decode(Notice.self, from: Data(#"{"id":"n2","kind":"heads","title":"x","reportId":"../x"}"#.utf8))
        XCTAssertNil(bad.reportId)
        XCTAssertEqual(PushWords.reportId(from: ["report_id": "0123456789abcdef"]), "0123456789abcdef")
        XCTAssertEqual(PushWords.reportId(from: ["jarvis": ["report_id": "0123456789abcdef"]]), "0123456789abcdef")
        XCTAssertNil(PushWords.reportId(from: ["report_id": "ZZZ"]))
    }
}

final class WatchReportTests: XCTestCase {
    func testTheWatchKnowsAReportAcrossTheRelay() {
        let notice = Notice(id: "n1", kind: .heads, title: "Report ready: Disk", body: "All fine", source: "job", created: "", reportId: "0123456789abcdef")
        let board = WatchBoard(snapshot: nil)
        var copy = board
        copy.notices = [WatchNotice(notice)]
        let back = WatchBoard(message: copy.message)
        XCTAssertEqual(back.notices.first?.isReport, true)
        XCTAssertFalse(WatchNotice(Notice(id: "n2", kind: .fyi, title: "x", source: "job", created: "")).isReport)
    }
}

final class ReportWordsTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-11-18T23:00:00Z")!

    private func report(expires: String?, kept: Bool = false) -> Report {
        Report(id: "95430f3fbe7f29d3", title: "Disk check", summary: "All fine", created: "2026-11-18T22:00:00Z", expires: expires, kept: kept, bytes: 1234)
    }

    func testSizes() {
        XCTAssertEqual(Reports.sizeText(850), "850 bytes")
        XCTAssertEqual(Reports.sizeText(184_200), "184 KB")
        XCTAssertEqual(Reports.sizeText(1_234_567), "1.2 MB")
        XCTAssertEqual(Reports.sizeText(200_000_000), "200 MB")
    }

    func testWhenItGoes() {
        XCTAssertEqual(Reports.endText(report(expires: "2026-12-18T22:00:00Z"), now: now), "Deletes Dec 18")
        XCTAssertEqual(Reports.endText(report(expires: "2026-11-19T10:00:00Z"), now: now), "Deletes today")
        XCTAssertEqual(Reports.endText(report(expires: "2026-11-20T10:00:00Z"), now: now), "Deletes tomorrow")
        XCTAssertEqual(Reports.endText(report(expires: nil), now: now), "Kept until you switch Keep off")
        XCTAssertEqual(Reports.endText(report(expires: "2026-12-18T22:00:00Z", kept: true), now: now), "Kept until you switch Keep off")
    }

    func testTheRuleAndTheRoom() {
        let empty = ReportShelf(reports: [], totalBytes: 0, keepDays: 30, maxBytes: 200_000_000)
        XCTAssertEqual(Reports.rulesText(empty), "Each report is deleted 30 days after it was made, unless Keep is on.")
        let one = ReportShelf(reports: [report(expires: nil)], totalBytes: 184_000, keepDays: 30, maxBytes: 200_000_000)
        XCTAssertEqual(Reports.rulesText(one), "Each report is deleted 30 days after it was made, unless Keep is on. Using 184 KB of 200 MB.")
    }

    func testTheSnapshotsShelfDecodesLeniently() throws {
        let json = #"{"generatedAt":"x","today":[],"services":[],"reports":{"reports":[{"id":"95430f3fbe7f29d3","title":"Disk","summary":"ok","created":"2026-11-18T22:00:00Z","expires":null,"kept":true,"bytes":900},{"id":"bad id","title":"x"},{"title":"no id"}],"totalBytes":900,"keepDays":30,"maxBytes":200000000}}"#
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(json.utf8))
        XCTAssertEqual(snapshot.reports?.reports.map(\.id), ["95430f3fbe7f29d3"])
        XCTAssertEqual(snapshot.reports?.maxBytes, 200_000_000)
        let older = try JSONDecoder().decode(Snapshot.self, from: Data(#"{"generatedAt":"x","today":[],"services":[],"reports":null}"#.utf8))
        XCTAssertNil(older.reports)
    }

    func testKeepingClearsTheEnd() {
        let r = report(expires: "2026-12-18T22:00:00Z")
        XCTAssertNil(r.keeping(true, days: 30).expires)
        XCTAssertEqual(Reports.endText(r.keeping(false, days: 30), now: now), "Deletes Dec 18")
    }

    func testFetchAnswers() {
        XCTAssertEqual(ReportFetch.read(status: 200, data: Data("<p>hi</p>".utf8)), .page("<p>hi</p>"))
        XCTAssertEqual(ReportFetch.read(status: 404, data: Data()), .gone)
        if case .failed = ReportFetch.read(status: 502, data: Data()) {} else { XCTFail() }
    }
}

final class TVReportsCardTests: XCTestCase {
    func testTheCardShowsForDylanOnlyWhenThereAreReports() throws {
        let with = try JSONDecoder().decode(Snapshot.self, from: Data(#"{"generatedAt":"x","today":[],"services":[],"reports":{"reports":[{"id":"95430f3fbe7f29d3","title":"Disk"}],"totalBytes":1,"keepDays":30,"maxBytes":0}}"#.utf8))
        XCTAssertTrue(TVBoard.cards(with, guest: false).contains(.reports))
        XCTAssertFalse(TVBoard.cards(with, guest: true).contains(.reports), "private in guest mode")
        let without = try JSONDecoder().decode(Snapshot.self, from: Data(#"{"generatedAt":"x","today":[],"services":[]}"#.utf8))
        XCTAssertFalse(TVBoard.cards(without, guest: false).contains(.reports))
    }
}

final class RetentionTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-11-19T10:00:00Z")!

    func testLabels() {
        XCTAssertEqual(Retention.choices.map(\.label), ["Keep 2 weeks", "Keep 1 month", "Keep 3 months", "Keep forever"])
    }

    func testTheRetentionInForce() throws {
        let newer = try JSONDecoder().decode(Report.self, from: Data(#"{"id":"0123456789abcdef","title":"x","created":"2026-11-19T08:00:00Z","expires":"2026-12-19T08:00:00Z","kept":false,"keepDays":30}"#.utf8))
        XCTAssertEqual(Reports.retention(newer, defaultDays: 14), .days(30))
        let forever = try JSONDecoder().decode(Report.self, from: Data(#"{"id":"0123456789abcdef","title":"x","created":"2026-11-19T08:00:00Z","expires":null,"kept":true,"keepDays":null}"#.utf8))
        XCTAssertEqual(Reports.retention(forever, defaultDays: 14), .forever)
        XCTAssertEqual(Reports.deleteLine(forever, retention: .forever, now: now), "Never deleted")
        // An older server: no keepDays field; the shelf's default applies.
        let older = try JSONDecoder().decode(Report.self, from: Data(#"{"id":"0123456789abcdef","title":"x","created":"2026-11-19T08:00:00Z","expires":"2026-12-19T08:00:00Z","kept":false}"#.utf8))
        XCTAssertFalse(older.keepDaysKnown)
        XCTAssertEqual(Reports.retention(older, defaultDays: 30), .days(30))
        XCTAssertEqual(Reports.deleteLine(older, retention: .days(30), now: now), "Deletes Dec 19")
    }

    func testRetainedCopies() {
        let r = Report(id: "0123456789abcdef", title: "x", created: "2026-11-19T08:00:00Z", expires: nil, kept: true, bytes: 1)
        let two = r.retained(.days(14))
        XCTAssertEqual(Reports.retention(two, defaultDays: 30), .days(14))
        XCTAssertEqual(Reports.deleteLine(two, retention: .days(14), now: now), "Deletes Dec 3")
        XCTAssertEqual(Reports.retention(r.retained(.forever), defaultDays: 14), .forever)
    }

    func testBodies() {
        XCTAssertEqual(Retention.days(30).body(id: "a") as NSDictionary, ["op": "keep", "id": "a", "days": 30] as NSDictionary)
        XCTAssertEqual(Retention.forever.body(id: "a") as NSDictionary, ["op": "keep", "id": "a", "keep": true] as NSDictionary)
    }

    func testShortLineAndFileName() {
        let shelf = ReportShelf(reports: [Report(id: "0123456789abcdef", title: "x", created: "", expires: nil, kept: false, bytes: 1)], totalBytes: 13_000, keepDays: 14, maxBytes: 200_000_000)
        XCTAssertEqual(Reports.shortRulesText(shelf), "Kept 2 weeks unless changed · 13 KB of 200 MB")
        XCTAssertEqual(Reports.shareFileName("Your meals: the last 7 days"), "Your meals  the last 7 days.html")
        XCTAssertEqual(Reports.shareFileName("///"), "Report.html")
    }
}

final class ReportMetaTests: XCTestCase {
    func testTheShortLine() {
        let r = Report(id: "0123456789abcdef", title: "x", created: "2026-11-18T20:00:00Z", expires: nil, kept: false, bytes: 240_000)
        XCTAssertEqual(Reports.metaLine(r), "Nov 18 · 240 KB")
        XCTAssertEqual(Reports.metaLine(Report(id: "0123456789abcdef", title: "x", created: "", expires: nil, kept: false, bytes: 900)), "900 bytes")
    }
}
