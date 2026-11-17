// The kiosk's hero choice and panel rotation.
import XCTest
@testable import JarvisKit

final class KioskTests: XCTestCase {
    private func snapshot(_ json: String) throws -> Snapshot {
        try JSONDecoder().decode(Snapshot.self, from: Data(json.utf8))
    }

    private let now = ISO8601DateFormatter().date(from: "2026-11-17T18:00:00Z")!

    func testHeroOrder() throws {
        let s = try snapshot(#"{"generatedAt":"x","services":[{"id":"ha","name":"Home Assistant","detail":"","status":"down"}],"today":[{"id":"1","at":"2026-11-17T18:20:00Z","title":"Volleyball"}]}"#)
        let approval = Approval(id: "a", tool: "write_file", summary: "Write notes.md", expires: "")
        XCTAssertEqual(KioskPlan.hero(snapshot: s, pending: [approval], now: now), .approval(count: 1, summary: "Write notes.md"))
        XCTAssertEqual(KioskPlan.hero(snapshot: s, pending: [], now: now), .alert(name: "Home Assistant", status: "down"))
        let calmServices = try snapshot(#"{"generatedAt":"x","services":[],"today":[{"id":"1","at":"2026-11-17T18:20:00Z","title":"Volleyball"}]}"#)
        XCTAssertEqual(KioskPlan.hero(snapshot: calmServices, pending: [], now: now), .soon(title: "Volleyball", minutes: 20))
        XCTAssertEqual(KioskPlan.hero(snapshot: nil, pending: [], now: now), .calm)
    }

    func testSoonIgnoresFarAllDayAndPast() throws {
        let items = try snapshot(#"{"generatedAt":"x","services":[],"today":[{"id":"1","at":"2026-11-17T20:00:00Z","title":"Later"},{"id":"2","at":"2026-11-17T00:00:00Z","title":"Birthday","allDay":true},{"id":"3","at":"2026-11-17T17:30:00Z","title":"Earlier"}]}"#).today
        XCTAssertNil(KioskPlan.nextSoon(items, now: now))
    }

    func testPanelsAndRotation() throws {
        let s = try snapshot(#"{"generatedAt":"x","services":[],"today":[],"home":{"devices":[{"id":"a","name":"Hall","kind":"light","state":"on"}]},"jobs":{"running":[{"id":"j","label":"Lookout","state":"running"}]}}"#)
        let panels = KioskPlan.panels(snapshot: s)
        XCTAssertEqual(panels, [.schedule, .home, .work])
        XCTAssertEqual(KioskPlan.showing(panels, turn: 0, count: 2), [.schedule, .home])
        XCTAssertEqual(KioskPlan.showing(panels, turn: 1, count: 2), [.work, .schedule])
        XCTAssertEqual(KioskPlan.showing(panels, turn: 0, count: 5), [.schedule, .home, .work])
        XCTAssertEqual(KioskPlan.showing([], turn: 3, count: 2), [])
    }
}
