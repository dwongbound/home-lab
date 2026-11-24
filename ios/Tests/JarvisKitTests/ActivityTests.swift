import XCTest
@testable import JarvisKit

final class ActivityTests: XCTestCase {
    func testRingFillIsCappedAndNeedsAGoal() {
        XCTAssertEqual(ActivityGlance.fill(250, goal: 500), 0.5)
        XCTAssertEqual(ActivityGlance.fill(900, goal: 500), 1)
        XCTAssertNil(ActivityGlance.fill(250, goal: nil))
        XCTAssertNil(ActivityGlance.fill(nil, goal: 500))
        XCTAssertNil(ActivityGlance.fill(10, goal: 0))
    }

    func testNormalizedKeepsHeadroomAndHandlesFlatWeeks() {
        XCTAssertEqual(ActivityGlance.normalized([1]), [])
        XCTAssertEqual(ActivityGlance.normalized([5, 5, 5]), [0.5, 0.5, 0.5])
        let line = ActivityGlance.normalized([50, 60, 70])
        XCTAssertEqual(line.first!, 0.1, accuracy: 0.0001)
        XCTAssertEqual(line.last!, 0.9, accuracy: 0.0001)
    }

    func testChangeComparesTheLatestWithTheWeekBefore() {
        XCTAssertEqual(ActivityGlance.change([60, 62, 58], unit: " bpm"), "↓ 3 bpm vs week")
        XCTAssertEqual(ActivityGlance.change([40, 40, 45], unit: " ms"), "↑ 5 ms vs week")
        XCTAssertNil(ActivityGlance.change([60, 60, 60]))
        XCTAssertNil(ActivityGlance.change([60, 61]))
    }

    func testWeightWords() {
        XCTAssertEqual(ActivityGlance.pounds(70), "154.3 lb")
        XCTAssertEqual(ActivityGlance.weightChange([72, 71.5]), "1.1 lb down in 30 days")
        XCTAssertEqual(ActivityGlance.weightChange([70, 70.01]), "Steady over 30 days")
        XCTAssertNil(ActivityGlance.weightChange([70]))
    }

    func testEmptyAndWholeNumbers() {
        XCTAssertTrue(ActivityGlance().isEmpty)
        var glance = ActivityGlance()
        glance.flights = 3
        XCTAssertFalse(glance.isEmpty)
        XCTAssertEqual(ActivityGlance.whole(8412.4), "8,412")
    }
}
