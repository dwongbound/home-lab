import XCTest
@testable import JarvisKit

final class AutoScrollTests: XCTestCase {
    func testOnlyOverflowingTextMoves() {
        XCTAssertEqual(AutoScroll.cycleSeconds(overflow: 0), 0)
        XCTAssertEqual(AutoScroll.offset(at: 10, overflow: 0), 0)
    }

    func testPausesScrollsPausesAndReturns() {
        let overflow = 120.0 // 5 s of scrolling at 24 pt/s
        XCTAssertEqual(AutoScroll.cycleSeconds(overflow: overflow), 3 + 5 + 3 + 0.8, accuracy: 0.001)
        XCTAssertEqual(AutoScroll.offset(at: 2, overflow: overflow), 0, "held at the top")
        XCTAssertEqual(AutoScroll.offset(at: 5.5, overflow: overflow), 60, accuracy: 0.001, "half way down")
        XCTAssertEqual(AutoScroll.offset(at: 9, overflow: overflow), 120, "held at the bottom")
        XCTAssertLessThan(AutoScroll.offset(at: 11.5, overflow: overflow), 120, "easing back")
        XCTAssertEqual(AutoScroll.offset(at: 11.8 + 1, overflow: overflow), 0, accuracy: 0.001, "round again")
    }

    func testACardWaitsUntilItHasScrolledThrough() {
        XCTAssertEqual(AutoScroll.cardSeconds(turn: 15, overflow: 0), 15)
        XCTAssertEqual(AutoScroll.cardSeconds(turn: 15, overflow: 24 * 20), 3 + 20 + 3, accuracy: 0.001)
    }
}
