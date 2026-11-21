// Sleep as Jarvis tells it back, and what each screen shows from it.
// Made-up numbers only.
import XCTest
@testable import JarvisKit

final class SleepReadTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private let fullNight = """
    {"night":"2026-11-20","bedtime":"2026-11-19T23:20:00-08:00","wake":"2026-11-20T07:00:00-08:00",
     "minutes":{"asleep":440,"inBed":470,"awake":20,"deep":70,"rem":100,"core":270,"unspecified":0},
     "interruptions":2,
     "vitals":{"heartRate":{"avg":55,"min":48},"hrvMs":45,"hrvRmssdMs":null,"respiratoryRate":14.5,
               "spo2":{"avg":96,"min":92},"wristTempC":34.6,"wristTempDeltaC":-0.3,"breathingDisturbances":null},
     "score":82,"scoreSource":"jarvis","scoreBand":"good",
     "scoreParts":{"duration":45,"consistency":22,"interruptions":15},
     "stages":[{"stage":"core","start":"2026-11-19T23:20:00-08:00","end":"2026-11-20T01:00:00-08:00"}]}
    """

    func testAFullNightDecodes() throws {
        let day = try decode(SleepDay.self, fullNight)
        XCTAssertEqual(day.minutes?.asleep, 440)
        XCTAssertEqual(day.vitals?.heartRate?.min, 48)
        XCTAssertNil(day.vitals?.hrvRmssdMs)
        XCTAssertEqual(day.score, 82)
        XCTAssertEqual(day.stages.count, 1)
    }

    func testNullsEverywhereDecodeAsNothing() throws {
        let day = try decode(SleepDay.self, """
        {"night":"2026-11-20","bedtime":null,"wake":null,"minutes":{"asleep":null},"interruptions":null,
         "vitals":{"heartRate":null,"spo2":null},"score":null,"scoreSource":null,"scoreBand":null,"scoreParts":null,"stages":[]}
        """)
        XCTAssertNil(day.bedtime)
        XCTAssertNil(day.minutes?.asleep)
        XCTAssertNil(day.score)
        XCTAssertNil(day.scoreParts)
        XCTAssertEqual(day.stages, [])
        XCTAssertEqual(SleepCard.vitals(day.vitals), [], "no vital is shown as 0")
    }

    func testTheListAndItsNullAnswer() throws {
        XCTAssertEqual(try decode(SleepNightsAnswer.self, #"{"nights":[\#(fullNight),{"bad":1}]}"#).nights?.count, 1)
        XCTAssertNil(try decode(SleepNightsAnswer.self, #"{"nights":null}"#).nights)
    }

    func testThePostAnswers() throws {
        XCTAssertTrue(try decode(SleepSendAnswer.self, #"{"ok":true,"message":"Saved","night":\#(fullNight)}"#).ok)
        XCTAssertFalse(try decode(SleepSendAnswer.self, #"{"ok":false,"message":"Bad night"}"#).ok)
        XCTAssertEqual(SleepWire.outcome(status: 200), .stored)
        XCTAssertEqual(SleepWire.outcome(status: 400), .refused, "a bad night isn't tried again")
        XCTAssertEqual(SleepWire.outcome(status: 502), .later, "Jarvis away: later")
        XCTAssertEqual(SleepWire.outcome(status: nil), .later)
        XCTAssertEqual(SleepWire.backoff(failures: 1), 900)
        XCTAssertEqual(SleepWire.backoff(failures: 2), 1800)
        XCTAssertEqual(SleepWire.backoff(failures: 20), 6 * 3600)
    }

    func testAnOlderServerWithNoSleepSlice() throws {
        let snapshot = try decode(Snapshot.self, #"{"cloud":{"health":{"sleep":{"asleep_min":400}}}}"#)
        XCTAssertNil(snapshot.sleep)
        let card = SleepCard(summary: snapshot.sleep, fallbackAsleepMinutes: snapshot.health?.sleep?.asleepMin, today: "2026-11-20")
        XCTAssertEqual(card.kind, .minutesOnly)
        XCTAssertEqual(card.asleep, "6h 40m")
        XCTAssertNil(card.score)
    }

    private func summary(parts: String = #"{"duration":45,"consistency":22,"interruptions":15}"#, vitals: String? = nil) throws -> SleepSummary {
        var night = fullNight.replacingOccurrences(of: #"{"duration":45,"consistency":22,"interruptions":15}"#, with: parts)
        if let vitals { night = night.replacingOccurrences(of: #"\{"heartRate":\{"avg":55[\s\S]*?"breathingDisturbances":null\}"#, with: vitals, options: .regularExpression) }
        return try decode(Snapshot.self, """
        {"sleep":{"last":\(night),"trend":[{"night":"2026-11-20","score":82,"asleep":440},{"night":"2026-11-19","score":null,"asleep":380},{"night":"2026-11-18","score":70}]}}
        """).sleep!
    }

    func testAFullNightCard() throws {
        let card = SleepCard(summary: try summary(), fallbackAsleepMinutes: 999, today: "2026-11-20")
        XCTAssertEqual(card.kind, .night)
        XCTAssertEqual(card.score, 82)
        XCTAssertEqual(card.bandWord, "Good")
        XCTAssertEqual(card.estimate, "Jarvis's estimate")
        XCTAssertEqual(card.asleep, "7h 20m")
        XCTAssertEqual(card.asleepNote, "On target")
        XCTAssertEqual(card.bedtime, "11:20 PM")
        XCTAssertEqual(card.wake, "7:00 AM")
        XCTAssertEqual(card.stages.map(\.stage), ["deep", "core", "rem", "awake"], "a 0 stage isn't drawn")
        XCTAssertEqual(card.parts.map(\.words), ["45 of 50", "22 of 30", "15 of 20"])
        XCTAssertEqual(card.vitals.map(\.label), ["Heart rate", "HRV", "Breathing", "Oxygen", "Wrist temp"])
        XCTAssertEqual(card.vitals.last?.value, "−0.3°C", "the difference from his baseline, not the absolute")
        XCTAssertEqual(card.trend.map(\.night), ["2026-11-18", "2026-11-19", "2026-11-20"], "oldest on the left")
        XCTAssertEqual(card.trend.map(\.isLast), [false, false, true])
        XCTAssertEqual(card.trendAverage, "Avg 6h 50m")
    }

    func testNoConsistencyYet() throws {
        let card = SleepCard(summary: try summary(parts: #"{"duration":45,"consistency":null,"interruptions":null}"#), fallbackAsleepMinutes: nil, today: "2026-11-20")
        XCTAssertEqual(card.parts.map(\.words), ["45 of 50", "Not enough nights yet", "Not enough nights yet"])
        XCTAssertNil(card.parts[1].value)
    }

    func testNoVitals() throws {
        let card = SleepCard(summary: try summary(vitals: "null"), fallbackAsleepMinutes: nil, today: "2026-11-20")
        XCTAssertEqual(card.vitals, [])
        XCTAssertEqual(card.kind, .night)
    }

    func testNoDataAtAll() throws {
        let none = SleepCard(summary: nil, fallbackAsleepMinutes: nil, today: "2026-11-20")
        XCTAssertEqual(none.kind, .noNight)
        XCTAssertEqual(none.emptyWords, "No sleep recorded yet")
        XCTAssertTrue(none.isEmpty)
        // At 3 AM before sleeping, last night is still the one before.
        let early = SleepCard(summary: try summary(), fallbackAsleepMinutes: nil, today: "2026-11-21")
        XCTAssertEqual(early.kind, .night, "the night before still counts until the next is recorded")
        XCTAssertEqual(SleepCard.dayBefore("2026-11-01"), "2026-10-31")
        XCTAssertEqual(early.whenWords, "Last night")
        // Days on with nothing new: still that night, named by its weekday.
        let old = SleepCard(summary: try summary(), fallbackAsleepMinutes: nil, today: "2026-11-24")
        XCTAssertEqual(old.kind, .night)
        XCTAssertEqual(old.whenWords, "Thursday night", "the night of Thu Nov 19 into Fri Nov 20")
        XCTAssertEqual(old.score, 82)
        // The morning a new night arrives, that one is last night.
        XCTAssertEqual(SleepCard(summary: try summary(), fallbackAsleepMinutes: nil, today: "2026-11-20").whenWords, "Last night")
    }

    func testTimesWithoutSecondsAsJarvisSendsThem() throws {
        let day = try decode(SleepDay.self, """
        {"night":"2026-11-20","bedtime":"2026-11-19T23:20-08:00","wake":"2026-11-20T07:00-08:00",
         "stages":[{"stage":"deep","start":"2026-11-20T01:00-08:00","end":"2026-11-20T02:00-08:00"}]}
        """)
        XCTAssertEqual(day.bedtime.map(SleepCard.clock), "11:20 PM")
        XCTAssertEqual(day.wake.map(SleepCard.clock), "7:00 AM")
        XCTAssertEqual(day.stages.count, 1)
        XCTAssertNotNil(SleepTime.parse("2026-11-20T07:00:00Z"))
        XCTAssertNil(SleepTime.parse("nope"))
    }

    func testDurationWords() {
        XCTAssertEqual(SleepCard.durationNote(5 * 60 + 59), "Short")
        XCTAssertNil(SleepCard.durationNote(6 * 60 + 30))
        XCTAssertEqual(SleepCard.durationNote(7 * 60), "On target")
        XCTAssertEqual(SleepCard.hours(45), "45m")
        XCTAssertEqual(SleepCard.weekday("2026-11-20"), "Fr")
    }
}

final class SleepSlideTests: XCTestCase {
    func testTheDemoSleepDecodes() throws {
        let now = Date()
        let nights = DemoSleep.nights(now: now)
        XCTAssertEqual(nights.count, 14)
        XCTAssertFalse(nights[0].stages.isEmpty)
        let summary = try JSONDecoder().decode(SleepSummary.self, from: Data(DemoSleep.summaryJSON(now: now).utf8))
        XCTAssertEqual(summary.trend.count, 7)
        XCTAssertEqual(SleepCard(summary: summary, fallbackAsleepMinutes: nil, today: SleepNights.key(now)).kind, .night)
    }

    func testSleepGetsItsOwnSlideAndYouKeepsSteps() throws {
        let both = try JSONDecoder().decode(Snapshot.self, from: Data(#"{"sleep":{"last":null,"trend":[]},"cloud":{"health":{"yesterday":{"steps":10},"sleep":{"asleep_min":400}}}}"#.utf8))
        XCTAssertTrue(SleepSlide.shows(both))
        XCTAssertTrue(SleepSlide.showsYou(both))
        XCTAssertEqual(TVBoard.cards(both, guest: false).filter { $0 == .sleep || $0 == .health }, [.sleep, .health])
        XCTAssertFalse(TVBoard.cards(both, guest: true).contains(.sleep), "guest-friendly mode hides sleep")
        XCTAssertTrue(KioskPlan.panels(snapshot: both).contains(.sleep))
        let older = try JSONDecoder().decode(Snapshot.self, from: Data(#"{"cloud":{"health":{"sleep":{"asleep_min":400}}}}"#.utf8))
        XCTAssertFalse(SleepSlide.shows(older))
        XCTAssertTrue(SleepSlide.showsYou(older), "an older Jarvis keeps the You slide with minutes asleep")
    }
}

final class WidgetGlanceTests: XCTestCase {
    func testTheDemoDayBecomesAGlance() throws {
        let now = Date()
        guard let snapshot = DemoSnapshot.build(now: now, sparse: false) else { return XCTFail("demo") }
        let g = WidgetGlance.from(snapshot, now: now)
        XCTAssertEqual(g.unread, snapshot.notices.filter { !$0.kept }.count)
        XCTAssertTrue(g.needsYou)
        XCTAssertNotNil(g.newestNotice)
        XCTAssertNotNil(g.home)
        XCTAssertNotNil(WidgetGlance.decode(g.encoded()), "round trip through the app group")
        XCTAssertTrue(g.agenda.allSatisfy { ($0.end ?? $0.start.addingTimeInterval(3600)) > now }, "only what's still to come")
    }

    func testNoticeWords() {
        var g = WidgetGlance(updated: Date(), unread: 0, needsYou: false, running: 0, agenda: [], sleep: nil)
        XCTAssertNil(g.noticeWords)
        g.unread = 3
        XCTAssertEqual(g.noticeWords, "3 new")
        g.needsYou = true; g.needCount = 1
        XCTAssertEqual(g.noticeWords, "3 new · 1 needs you")
    }
}
