import XCTest
@testable import JarvisKit

final class NoticesTests: XCTestCase {
    private func iso(_ d: Date) -> String { ISO8601DateFormatter().string(from: d) }

    func testSnapshotDecodesNoticesAndSkipsBadOnes() throws {
        let json = #"{"generatedAt":"x","services":[],"today":[],"notices":[{"id":"a","kind":"need","title":"Turn off the lights?","body":"","source":"approval","created":"2026-11-18T08:00:00Z","approvalId":"ap1"},{"kind":"fyi"},{"id":"b","kind":"shiny","title":"New thing","source":"lookout","created":"2026-11-18T07:00:00Z"}]}"#
        let s = try JSONDecoder().decode(Snapshot.self, from: Data(json.utf8))
        XCTAssertEqual(s.notices.map(\.id), ["a", "b"])
        XCTAssertEqual(s.notices[0].approvalId, "ap1")
        XCTAssertTrue(s.notices[0].isApproval)
        XCTAssertEqual(s.notices[1].kind, .fyi, "an unknown kind reads as FYI")
        let older = try JSONDecoder().decode(Snapshot.self, from: Data(#"{"generatedAt":"x","services":[],"today":[],"notices":null}"#.utf8))
        XCTAssertTrue(older.notices.isEmpty)
    }

    func testPipsPutNeedsFirstAndNightShowsOnlyNeeds() {
        let n = [Notice(id: "1", kind: .fyi, title: "a", source: "job", created: ""),
                 Notice(id: "2", kind: .need, title: "b", source: "approval", created: ""),
                 Notice(id: "3", kind: .heads, title: "c", source: "lookout", created: "")]
        XCTAssertEqual(Notices.pips(n), [.need, .heads, .fyi])
        XCTAssertEqual(Notices.pips(n, night: true), [.need])
        let many = (0..<12).map { Notice(id: "\($0)", kind: .fyi, title: "", source: "job", created: "") }
        XCTAssertEqual(Notices.pips(many).count, Notices.maxPips)
        XCTAssertEqual(Notices.countLabel(many), "12 new")
        XCTAssertNil(Notices.countLabel([]))
    }

    func testRowWordingAndOrder() {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let now = c.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 9))!
        XCTAssertEqual(Notices.when(iso(now.addingTimeInterval(-20)), now: now, calendar: c), "now")
        XCTAssertEqual(Notices.when(iso(now.addingTimeInterval(-12 * 60)), now: now, calendar: c), "12 min")
        XCTAssertEqual(Notices.when(iso(now.addingTimeInterval(-3 * 3600)), now: now, calendar: c), "3 h")
        XCTAssertEqual(Notices.when(iso(now.addingTimeInterval(-20 * 3600)), now: now, calendar: c), "Yesterday")
        XCTAssertEqual(Notices.when(iso(now.addingTimeInterval(-3 * 86_400)), now: now, calendar: c), "Sun")
        let older = Notice(id: "o", kind: .fyi, title: "", source: "job", created: iso(now.addingTimeInterval(-3600)))
        let newer = Notice(id: "n", kind: .fyi, title: "", source: "job", created: iso(now))
        XCTAssertEqual(Notices.sorted([older, newer]).map(\.id), ["n", "o"])
        XCTAssertEqual(Notices.symbol("approval"), "hand.raised.fill")
        XCTAssertFalse(Notices.showsText(guest: true))
    }

    func testPushRegisterRequestShape() throws {
        let client = JarvisClient(base: URL(string: "https://jarvis.example.ts.net")!)
        let r = client.pushRegisterRequest(token: "abcd", platform: "ios", environment: "sandbox", bundle: "com.dwongbound.jarvis", name: "iPhone")
        XCTAssertEqual(r.url?.path, "/api/jarvis/push/register")
        XCTAssertEqual(r.value(forHTTPHeaderField: "x-home-lab"), "1")
        let body = try JSONSerialization.jsonObject(with: r.httpBody ?? Data()) as? [String: String]
        XCTAssertEqual(body?["platform"], "ios")
        XCTAssertEqual(body?["environment"], "sandbox")
    }
}
