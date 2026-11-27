import XCTest
@testable import JarvisKit

final class ChartPickTests: XCTestCase {
    func testLine() {
        XCTAssertEqual(ChartPick.line(x: 0, width: 100, count: 5), 0)
        XCTAssertEqual(ChartPick.line(x: 100, width: 100, count: 5), 4)
        XCTAssertEqual(ChartPick.line(x: 30, width: 100, count: 5), 1)
        XCTAssertEqual(ChartPick.line(x: -20, width: 100, count: 5), 0, "off the left edge is the first point")
        XCTAssertEqual(ChartPick.line(x: 140, width: 100, count: 5), 4)
        XCTAssertNil(ChartPick.line(x: 10, width: 100, count: 0))
    }

    func testBars() {
        XCTAssertEqual(ChartPick.bar(x: 0, width: 240, count: 24), 0)
        XCTAssertEqual(ChartPick.bar(x: 155, width: 240, count: 24), 15)
        XCTAssertEqual(ChartPick.bar(x: 240, width: 240, count: 24), 23)
    }

    func testHourNames() {
        XCTAssertEqual(ChartPick.hourName(0), "12 AM")
        XCTAssertEqual(ChartPick.hourName(15), "3 PM")
        XCTAssertEqual(ChartPick.hourName(12), "12 PM")
    }

    func testGaugeReadings() {
        let ram = SystemGauge(kind: .ram, used: 10, total: 16, unit: "GB", history: [0.5, 0.625])
        XCTAssertEqual(ram.historyText(0), "8 of 16 GB")
        XCTAssertEqual(ram.historyAge(1), "Latest reading")
        XCTAssertEqual(ram.historyAge(0), "1 reading ago")
        XCTAssertNil(ram.historyText(5))
        let cpu = SystemGauge(kind: .cpu, used: 20, total: 100, unit: "%", history: [0.42])
        XCTAssertEqual(cpu.historyText(0), "42% busy")
    }
}
