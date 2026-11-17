import XCTest
@testable import JarvisKit

final class LampPaletteTests: XCTestCase {
    /// Measured screenshots come in up to about half a point under the
    /// maths (anti-aliasing), so the palette must clear each target by more.
    static let renderSlack = 0.75

    /// Every minute of a real day (sunrise 6:29, sunset 4:48).
    private func dayOfPalettes() -> [(String, LampPalette)] {
        let start = Date(timeIntervalSince1970: 1_795_420_800) // a midnight UTC
        let rise = start.addingTimeInterval((6 * 60 + 29 + 480) * 60)
        let set = start.addingTimeInterval((16 * 60 + 48 + 480) * 60)
        return (0..<1440).map { minute in
            let now = start.addingTimeInterval(Double(minute + 480) * 60)
            let lamp = SunLamp.state(now: now, sunrise: rise, sunset: set)
            return ("\(minute / 60):\(minute % 60) \(lamp.phase) b=\(lamp.brightness)", LampPalette.at(lamp))
        }
    }

    func testTheContrastFormula() {
        XCTAssertEqual(RGB.white.contrast(with: .black), 21, accuracy: 0.01)
        XCTAssertEqual(RGB.white.contrast(with: .white), 1, accuracy: 0.001)
        // #767676 on white is the classic 4.54:1.
        XCTAssertEqual(RGB(0x76 / 255.0, 0x76 / 255.0, 0x76 / 255.0).contrast(with: .white), 4.54, accuracy: 0.01)
    }

    func testTextMeetsSevenToOneAllDay() {
        for (when, p) in dayOfPalettes() {
            XCTAssertGreaterThanOrEqual(p.ink.worstContrast(against: p.backgrounds), LampPalette.textTarget + Self.renderSlack, "ink \(when)")
            XCTAssertGreaterThanOrEqual(p.accent.worstContrast(against: p.backgrounds), LampPalette.textTarget + Self.renderSlack, "accent \(when)")
        }
    }

    func testDimTextMeetsFourAndAHalfAllDay() {
        for (when, p) in dayOfPalettes() {
            XCTAssertGreaterThanOrEqual(p.inkDim.worstContrast(against: p.backgrounds), LampPalette.dimTarget + Self.renderSlack, "dim \(when)")
            XCTAssertGreaterThanOrEqual(p.alert.worstContrast(against: p.backgrounds), LampPalette.dimTarget + Self.renderSlack, "alert \(when)")
        }
    }

    func testIconsDotsAndEdgesMeetThreeToOneAllDay() {
        for (when, p) in dayOfPalettes() {
            XCTAssertGreaterThanOrEqual(p.warm.worstContrast(against: p.backgrounds), LampPalette.markTarget + Self.renderSlack, "warm \(when)")
            XCTAssertGreaterThanOrEqual(p.dot.worstContrast(against: [p.skyTop, p.skyBottom]), LampPalette.markTarget + Self.renderSlack, "dot \(when)")
            XCTAssertGreaterThanOrEqual(p.panelEdge.worstContrast(against: [p.skyTop, p.skyBottom]), LampPalette.markTarget + Self.renderSlack, "edge \(when)")
        }
    }

    func testDayIsBrightAndNightStaysDim() {
        let day = LampPalette.at(SunLampState(phase: .day, brightness: 1, warmth: 0))
        let night = LampPalette.at(SunLampState(phase: .night, brightness: SunLamp.nightBrightness, warmth: 0))
        XCTAssertTrue(day.darkInk)
        XCTAssertGreaterThan(day.skyBottom.luminance, 0.7)
        XCTAssertFalse(night.darkInk)
        XCTAssertLessThan(night.skyTop.luminance, 0.01)
        // Night text is dimmer than full white: just enough, not a glare.
        XCTAssertLessThan(night.ink.luminance, LampPalette.nightInk.luminance)
    }

    func testDayTextIsNearBlackNotGrey() {
        let day = LampPalette.at(SunLampState(phase: .day, brightness: 1, warmth: 0))
        XCTAssertGreaterThanOrEqual(day.ink.worstContrast(against: day.backgrounds), 12)
    }
}
