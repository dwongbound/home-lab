// One night of sleep from Health samples (JarvisKit Sleep). Every number is
// made up; nothing is read from a real Health store.
import XCTest
@testable import JarvisKit

final class SleepNightTests: XCTestCase {
    private let watch = SleepSource(id: "watch", isWatch: true)
    private let phone = SleepSource(id: "phone", isWatch: false)
    private let zone = SleepNights.zone

    /// A Pacific time on a given day ("2026-11-19 23:30").
    private func t(_ text: String) -> Date {
        let f = DateFormatter()
        f.timeZone = zone
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: text)!
    }
    private func s(_ v: SleepValue, _ a: String, _ b: String, _ src: SleepSource? = nil) -> SleepStageSample {
        SleepStageSample(value: v, start: t(a), end: t(b), source: src ?? watch)
    }
    private func r(_ value: Double, _ a: String, _ b: String? = nil, _ src: SleepSource? = nil) -> SleepReading {
        SleepReading(value: value, start: t(a), end: t(b ?? a), source: src ?? watch)
    }

    /// A watch night: in bed 23:00–07:10, asleep 23:20–07:00 through the stages.
    private var night: [SleepStageSample] {
        [s(.inBed, "2026-11-19 23:00", "2026-11-20 07:10", phone),
         s(.core, "2026-11-19 23:20", "2026-11-20 01:00"),
         s(.deep, "2026-11-20 01:00", "2026-11-20 02:00"),
         s(.awake, "2026-11-20 02:00", "2026-11-20 02:10"),
         s(.rem, "2026-11-20 02:10", "2026-11-20 03:00"),
         s(.core, "2026-11-20 03:00", "2026-11-20 07:00")]
    }

    func testAFullNightCrossingMidnight() throws {
        var vitals = SleepVitals()
        vitals.heartRate = [r(60, "2026-11-20 00:00"), r(50, "2026-11-20 03:00"), r(55, "2026-11-20 05:00"), r(90, "2026-11-19 21:00")]
        vitals.hrvSDNN = [r(40, "2026-11-20 01:00"), r(50, "2026-11-20 04:00")]
        vitals.respiratoryPerSecond = [r(0.25, "2026-11-20 02:00")]
        vitals.oxygenFraction = [r(0.97, "2026-11-20 01:00"), r(0.93, "2026-11-20 04:00")]
        vitals.wristTemperature = [r(34.5, "2026-11-19 23:20", "2026-11-20 07:00")]
        let n = try XCTUnwrap(SleepNights.build(night: "2026-11-20", stages: night, vitals: vitals))
        XCTAssertEqual(n.asleepStart, t("2026-11-19 23:20"))
        XCTAssertEqual(n.asleepEnd, t("2026-11-20 07:00"))
        XCTAssertEqual(n.inBedStart, t("2026-11-19 23:00"))
        XCTAssertEqual(n.inBedEnd, t("2026-11-20 07:10"))
        XCTAssertEqual(n.stages.map(\.stage), ["core", "deep", "awake", "rem", "core"])
        XCTAssertEqual(n.heartRate?.avg, 55, "the 9 PM reading is outside the sleep")
        XCTAssertEqual(n.heartRate?.min, 50)
        XCTAssertEqual(n.hrvMs, 45)
        XCTAssertEqual(n.respiratoryRate, 15, "per second to per minute")
        XCTAssertEqual(n.spo2?.avg, 95)
        XCTAssertEqual(n.spo2?.min, 93)
        XCTAssertEqual(n.wristTempC, 34.5)
        XCTAssertNil(n.hrvRmssdMs)
        XCTAssertEqual(n.source, "apple_watch")
    }

    func testTheWatchWinsOverThePhoneSoNothingIsCountedTwice() throws {
        let both = night + [s(.unspecified, "2026-11-19 23:00", "2026-11-20 07:30", phone)]
        let n = try XCTUnwrap(SleepNights.build(night: "2026-11-20", stages: both, vitals: SleepVitals()))
        XCTAssertFalse(n.stages.contains { $0.stage == "unspecified" })
        XCTAssertEqual(n.asleepEnd, t("2026-11-20 07:00"))
        var vitals = SleepVitals()
        vitals.heartRate = [r(52, "2026-11-20 03:00"), r(80, "2026-11-20 03:00", nil, phone)]
        XCTAssertEqual(SleepNights.build(night: "2026-11-20", stages: night, vitals: vitals)?.heartRate?.avg, 52)
    }

    func testANapIsIgnored() throws {
        let nap = s(.core, "2026-11-20 14:00", "2026-11-20 14:40")
        let n = try XCTUnwrap(SleepNights.build(night: "2026-11-20", stages: night + [nap], vitals: SleepVitals()))
        XCTAssertEqual(n.asleepEnd, t("2026-11-20 07:00"))
    }

    func testAGapInTheWatchDataStaysOneNight() throws {
        let gapped = [s(.core, "2026-11-19 23:30", "2026-11-20 02:00"), s(.core, "2026-11-20 02:45", "2026-11-20 06:30")]
        let n = try XCTUnwrap(SleepNights.build(night: "2026-11-20", stages: gapped, vitals: SleepVitals()))
        XCTAssertEqual(n.asleepStart, t("2026-11-19 23:30"))
        XCTAssertEqual(n.asleepEnd, t("2026-11-20 06:30"))
        XCTAssertEqual(n.inBedStart, n.asleepStart, "no in-bed record: the sleep itself")
    }

    func testTheSixPMWindowEdges() throws {
        // Before 6 PM the day before belongs to the night before.
        let early = [s(.core, "2026-11-19 17:00", "2026-11-19 17:50")]
        XCTAssertNil(SleepNights.build(night: "2026-11-20", stages: early, vitals: SleepVitals()))
        // A sleep running past 6 PM is cut at the window's edge.
        let w = try XCTUnwrap(SleepNights.window("2026-11-20"))
        XCTAssertEqual(w.start, t("2026-11-19 18:00"))
        XCTAssertEqual(w.end, t("2026-11-20 18:00"))
        let late = [s(.core, "2026-11-19 17:30", "2026-11-19 22:00")]
        XCTAssertEqual(SleepNights.build(night: "2026-11-20", stages: late, vitals: SleepVitals())?.asleepStart, t("2026-11-19 18:00"))
    }

    func testMissingVitalsAreLeftOutNotZero() throws {
        let n = try XCTUnwrap(SleepNights.build(night: "2026-11-20", stages: night, vitals: SleepVitals()))
        let body = SleepWire.body(n)
        for field in ["heartRate", "hrvMs", "hrvRmssdMs", "respiratoryRate", "spo2", "wristTempC", "breathingDisturbances"] {
            XCTAssertNil(body[field], field)
        }
    }

    func testAPhoneOnlyNightIsUnspecifiedSleep() throws {
        let phoneOnly = [s(.inBed, "2026-11-19 22:45", "2026-11-20 06:50", phone), s(.unspecified, "2026-11-19 23:10", "2026-11-20 06:40", phone)]
        let n = try XCTUnwrap(SleepNights.build(night: "2026-11-20", stages: phoneOnly, vitals: SleepVitals()))
        XCTAssertEqual(n.stages.map(\.stage), ["unspecified"])
        XCTAssertEqual(n.source, "iphone")
    }

    func testDaylightSavingNight() throws {
        // 2026-11-01: clocks go back at 2 AM in Los Angeles; the night is an hour longer.
        let w = try XCTUnwrap(SleepNights.window("2026-11-01"))
        XCTAssertEqual(w.duration, 25 * 3600)
        let n = try XCTUnwrap(SleepNights.build(night: "2026-11-01", stages: [s(.core, "2026-10-31 23:00", "2026-11-01 07:00")], vitals: SleepVitals()))
        XCTAssertEqual(n.asleepEnd.timeIntervalSince(n.asleepStart), 9 * 3600)
        XCTAssertEqual(SleepWire.time(n.asleepStart), "2026-10-31T23:00:00-07:00")
        XCTAssertEqual(SleepWire.time(n.asleepEnd), "2026-11-01T07:00:00-08:00")
    }

    func testNothingAtAll() {
        XCTAssertNil(SleepNights.build(night: "2026-11-20", stages: [], vitals: SleepVitals()))
        XCTAssertNil(SleepNights.build(night: "not a night", stages: night, vitals: SleepVitals()))
    }

    func testTimesGoWithSecondsAndOffsetNoFractions() {
        let when = Date(timeIntervalSince1970: 1_763_700_000.789)
        let text = SleepWire.time(when)
        XCTAssertNotNil(text.range(of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{2}:\d{2}$"#, options: .regularExpression), text)
    }

    func testUnits() {
        XCTAssertEqual(SleepUnits.breathsPerMinute(perSecond: 0.25), 15)
        XCTAssertEqual(SleepUnits.percent(fraction: 0.96), 96, accuracy: 0.0001)
    }

    func testTheRequestBody() throws {
        var vitals = SleepVitals()
        vitals.heartRate = [r(58, "2026-11-20 02:00")]
        vitals.breathingDisturbances = [r(3, "2026-11-19 23:20", "2026-11-20 07:00")]
        let n = try XCTUnwrap(SleepNights.build(night: "2026-11-20", stages: night, vitals: vitals))
        let page = SleepWire.body(n)
        XCTAssertEqual(page["night"] as? String, "2026-11-20")
        XCTAssertEqual(page["asleepStart"] as? String, "2026-11-19T23:20:00-08:00")
        XCTAssertEqual((page["stages"] as? [[String: String]])?.first, ["stage": "core", "start": "2026-11-19T23:20:00-08:00", "end": "2026-11-20T01:00:00-08:00"])
        XCTAssertEqual(page["heartRate"] as? [String: Double], ["avg": 58, "min": 58])
        XCTAssertEqual(page["breathingDisturbances"] as? Int, 3)
        XCTAssertNil(page["appleScore"])
        let jarvis = SleepWire.body(n, style: .jarvis)
        XCTAssertNotNil(jarvis["in_bed_start"])
        XCTAssertNotNil(jarvis["heart_rate"])
        XCTAssertNotNil(jarvis["breathing_disturbances"])
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: page))
    }

    func testTheSentNightsStore() throws {
        let n = try XCTUnwrap(SleepNights.build(night: "2026-11-20", stages: night, vitals: SleepVitals()))
        var store = SentNights()
        XCTAssertTrue(store.needs(n))
        store.mark(n)
        XCTAssertFalse(store.needs(n), "re-sending the same night isn't needed")
        // The watch synced more of the night later: send again.
        let longer = try XCTUnwrap(SleepNights.build(night: "2026-11-20", stages: night + [s(.core, "2026-11-20 07:00", "2026-11-20 07:30")], vitals: SleepVitals()))
        XCTAssertTrue(store.needs(longer))
        store.prune(keeping: ["2026-11-21"])
        XCTAssertTrue(store.stored.isEmpty)
        XCTAssertEqual(SleepNights.recent(3, now: t("2026-11-20 09:00")), ["2026-11-18", "2026-11-19", "2026-11-20"])
    }
}

final class SleepAccessTests: XCTestCase {
    func testOnlyWhenTheAppCanReallyAsk() {
        XCTAssertTrue(SleepAccess.canAsk(entitled: true, healthAvailable: true, isPhone: true))
        XCTAssertFalse(SleepAccess.canAsk(entitled: false, healthAvailable: true, isPhone: true), "no entitlement: no card, no switch")
        XCTAssertFalse(SleepAccess.canAsk(entitled: true, healthAvailable: false, isPhone: true))
        XCTAssertFalse(SleepAccess.canAsk(entitled: true, healthAvailable: true, isPhone: false), "not on the iPad")
    }
}
