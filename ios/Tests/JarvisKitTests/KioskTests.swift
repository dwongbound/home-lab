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

final class PhoneKioskTests: XCTestCase {
    func testEntersOnlySidewaysAndCharging() {
        XCTAssertTrue(PhoneKiosk.decide(enabled: true, orientation: .landscape, power: .charging, dismissed: false, showing: false).showing)
        XCTAssertTrue(PhoneKiosk.decide(enabled: true, orientation: .landscape, power: .full, dismissed: false, showing: false).showing)
        XCTAssertFalse(PhoneKiosk.decide(enabled: true, orientation: .landscape, power: .unplugged, dismissed: false, showing: false).showing)
        XCTAssertFalse(PhoneKiosk.decide(enabled: true, orientation: .portrait, power: .charging, dismissed: false, showing: false).showing)
        XCTAssertFalse(PhoneKiosk.decide(enabled: false, orientation: .landscape, power: .charging, dismissed: false, showing: false).showing)
    }

    func testLeavesWhenUprightOrUnplugged() {
        XCTAssertFalse(PhoneKiosk.decide(enabled: true, orientation: .portrait, power: .charging, dismissed: false, showing: true).showing)
        XCTAssertFalse(PhoneKiosk.decide(enabled: true, orientation: .landscape, power: .unplugged, dismissed: false, showing: true).showing)
        // Laid flat on a table keeps it up.
        XCTAssertTrue(PhoneKiosk.decide(enabled: true, orientation: .flat, power: .charging, dismissed: false, showing: true).showing)
        XCTAssertFalse(PhoneKiosk.decide(enabled: true, orientation: .flat, power: .charging, dismissed: false, showing: false).showing)
    }

    func testCloseHoldsUntilNextRotateOrPlugIn() {
        let closed = PhoneKiosk.decide(enabled: true, orientation: .landscape, power: .charging, dismissed: true, showing: false)
        XCTAssertFalse(closed.showing)
        XCTAssertTrue(closed.dismissed)
        let upright = PhoneKiosk.decide(enabled: true, orientation: .portrait, power: .charging, dismissed: true, showing: false)
        XCTAssertFalse(upright.dismissed)
        let unplugged = PhoneKiosk.decide(enabled: true, orientation: .landscape, power: .unplugged, dismissed: true, showing: false)
        XCTAssertFalse(unplugged.dismissed)
    }
}

final class SunLineTests: XCTestCase {
    private let la = TimeZone(identifier: "America/Los_Angeles")!

    func testNextFirstAndRollsPastTimesToTomorrow() {
        // 14:28Z = 6:28 AM PT sunrise, 00:48Z next day = 4:48 PM PT sunset.
        let rising = "2026-11-17T14:28:00Z", setting = "2026-11-18T00:48:00Z"
        let afternoon = ISO8601DateFormatter().date(from: "2026-11-17T20:00:00Z")!
        XCTAssertEqual(TodayWording.sunLine(rising: rising, setting: setting, now: afternoon, timeZone: la), "Sunset 4:48 PM · Sunrise 6:28 AM")
        let morning = ISO8601DateFormatter().date(from: "2026-11-17T12:00:00Z")!
        XCTAssertEqual(TodayWording.sunLine(rising: rising, setting: setting, now: morning, timeZone: la), "Sunrise 6:28 AM · Sunset 4:48 PM")
        XCTAssertNil(TodayWording.sunLine(rising: nil, setting: nil, timeZone: la))
    }

    func testOffersPanelOnlyWithOffers() throws {
        let s = try JSONDecoder().decode(Snapshot.self, from: Data(#"{"generatedAt":"x","services":[],"today":[],"offers":{"greeting":null,"offers":[{"id":"o","title":"Draft the RSVP","body":"b","startText":"s"}]}}"#.utf8))
        XCTAssertEqual(KioskPlan.panels(snapshot: s), [.schedule, .offers])
    }
}

final class GreetingPartsTests: XCTestCase {
    func testSplits() {
        let a = TodayWording.greetingParts("Late night, Dylan. You've got volleyball at 7:30 tomorrow and a study block after.")
        XCTAssertEqual(a.headline, "Late night, Dylan")
        XCTAssertEqual(a.body, "You've got volleyball at 7:30 tomorrow and a study block after.")
        let b = TodayWording.greetingParts("Late night, Dylan, you've still got the RSVP to send.")
        XCTAssertEqual(b.headline, "Late night, Dylan")
        XCTAssertEqual(b.body, "You've still got the RSVP to send.")
        let c = TodayWording.greetingParts("Morning, Dylan — rain until noon.")
        XCTAssertEqual(c.headline, "Morning, Dylan")
        XCTAssertEqual(c.body, "rain until noon.")
        let d = TodayWording.greetingParts("Good evening, Dylan.")
        XCTAssertEqual(d.headline, "Good evening, Dylan")
        XCTAssertNil(d.body)
        let e = TodayWording.greetingParts("Hey Dylan! Big day.")
        XCTAssertEqual(e.headline, "Hey Dylan!")
        XCTAssertEqual(e.body, "Big day.")
    }
}

final class KioskIconsTests: XCTestCase {
    func testGreetingEmoji() {
        XCTAssertEqual(KioskIcons.greetingEmoji(hour: 2), "🌙")
        XCTAssertEqual(KioskIcons.greetingEmoji(hour: 6), "🌅")
        XCTAssertEqual(KioskIcons.greetingEmoji(hour: 12), "☀️")
        XCTAssertEqual(KioskIcons.greetingEmoji(hour: 18), "🌇")
        XCTAssertEqual(KioskIcons.greetingEmoji(hour: 22), "🌙")
    }

    func testAgendaSymbols() {
        XCTAssertEqual(KioskIcons.agendaSymbol("Flight lesson KSMO"), "airplane")
        XCTAssertEqual(KioskIcons.agendaSymbol("CG x SOW rehearsal"), "music.note.house.fill")
        XCTAssertEqual(KioskIcons.agendaSymbol("Reminder: pay rent"), "bell.fill")
        XCTAssertEqual(KioskIcons.agendaSymbol("Volleyball at the Y"), "figure.run")
        XCTAssertEqual(KioskIcons.agendaSymbol("Study block: written test"), "book.fill")
        XCTAssertEqual(KioskIcons.agendaSymbol("Ryan + Claire"), "calendar")
    }
}

final class WeatherWordsTests: XCTestCase {
    func testWords() {
        XCTAssertEqual(TodayWording.weatherWords("partlycloudy"), "Partly cloudy")
        XCTAssertEqual(TodayWording.weatherWords("clear-night"), "Clear")
        XCTAssertEqual(TodayWording.weatherWords("cloudy"), "Cloudy")
        XCTAssertEqual(TodayWording.weatherWords("rainy"), "Rainy")
    }
}

final class KioskOrbTalkTests: XCTestCase {
    func testTapStartsThenTapAgainHangsUpEvenWhenDozing() {
        XCTAssertEqual(PhoneKiosk.orbTap(callOpen: false, connecting: false), .start)
        XCTAssertEqual(PhoneKiosk.orbTap(callOpen: true, connecting: false), .hangUp)
        XCTAssertEqual(PhoneKiosk.orbTap(callOpen: false, connecting: true), .nothing)
    }

    func testLeavingTheKioskMidCallHandsOverToTalk() {
        XCTAssertTrue(PhoneKiosk.handOverToTalk(callLive: true))
        XCTAssertFalse(PhoneKiosk.handOverToTalk(callLive: false))
    }
}
