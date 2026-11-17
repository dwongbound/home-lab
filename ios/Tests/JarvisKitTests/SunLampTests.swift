// The TV's sun lamp: night, dawn, day and dusk around real sun times.
import XCTest
@testable import JarvisKit

final class SunLampTests: XCTestCase {
    private let iso = ISO8601DateFormatter()
    private var rise: Date { iso.date(from: "2026-11-17T14:28:00Z")! }   // 6:28 AM PT
    private var set: Date { iso.date(from: "2026-11-18T00:48:00Z")! }    // 4:48 PM PT

    private func at(_ text: String) -> SunLampState {
        SunLamp.state(now: iso.date(from: text)!, sunrise: rise, sunset: set)
    }

    func testPhasesThroughTheDay() {
        XCTAssertEqual(at("2026-11-17T10:00:00Z").phase, .night)            // 2 AM
        XCTAssertEqual(at("2026-11-17T10:00:00Z").brightness, SunLamp.nightBrightness)
        XCTAssertEqual(at("2026-11-17T14:10:00Z").phase, .dawn)             // 18 min before sunrise
        XCTAssertEqual(at("2026-11-17T20:00:00Z").phase, .day)              // noon
        XCTAssertEqual(at("2026-11-17T20:00:00Z").brightness, 1)
        XCTAssertEqual(at("2026-11-18T00:50:00Z").phase, .dusk)             // just after sunset
        XCTAssertEqual(at("2026-11-18T03:00:00Z").phase, .night)            // 7 PM
        // Tomorrow's dawn from today's times.
        XCTAssertEqual(at("2026-11-18T14:20:00Z").phase, .dawn)
    }

    func testDawnBrightensAndCoolsSmoothly() {
        var last = at("2026-11-17T13:57:00Z")
        var date = iso.date(from: "2026-11-17T13:58:00Z")!
        while date < iso.date(from: "2026-11-17T14:49:00Z")! {
            let next = SunLamp.state(now: date, sunrise: rise, sunset: set)
            XCTAssertGreaterThanOrEqual(next.brightness, last.brightness)
            XCTAssertLessThan(abs(next.brightness - last.brightness), 0.08, "no jumps")
            last = next
            date = date.addingTimeInterval(60)
        }
        XCTAssertEqual(last.brightness, 1, accuracy: 0.001)
        XCTAssertEqual(last.warmth, 0, accuracy: 0.001)
    }

    func testDuskWarmsThenFades() {
        let mid = at("2026-11-18T00:55:00Z")
        XCTAssertGreaterThan(mid.warmth, 0.5)
        XCTAssertLessThan(mid.brightness, 0.8)
        XCTAssertEqual(at("2026-11-18T01:20:00Z").brightness, SunLamp.nightBrightness, accuracy: 0.001)
    }

    func testEstimateIsNearRealLATimes() {
        let est = SunLamp.estimate(for: iso.date(from: "2026-11-17T20:00:00Z")!)
        XCTAssertLessThan(abs(est.sunrise.timeIntervalSince(rise)), 20 * 60)
        XCTAssertLessThan(abs(est.sunset.timeIntervalSince(set)), 20 * 60)
    }
}
