import XCTest
@testable import JarvisKit

/// A settled approval goes back after the turn it followed, never at the
/// end among later messages (Dylan 2026-11-27).
final class ApprovalPlaceTests: XCTestCase {
    func testAfterItsAnchorTurn() {
        let ids: [Int?] = [10, 11, 12, 13]
        let texts = ["move it", "Done", "dinner?", "Pho 45"]
        XCTAssertEqual(ApprovalPlace.index(anchor: 10, afterText: "changed text", turnIds: ids, texts: texts), 1)
    }

    func testMissingAnchorGoesBeforeTheFirstNewerTurn() {
        XCTAssertEqual(ApprovalPlace.index(anchor: 11, afterText: nil, turnIds: [10, 12, 13], texts: ["a", "b", "c"]), 1)
        XCTAssertEqual(ApprovalPlace.index(anchor: 5, afterText: nil, turnIds: [10, 12], texts: ["a", "b"]), 0)
    }

    func testNoAnchorFallsBackToTextThenTheEnd() {
        XCTAssertEqual(ApprovalPlace.index(anchor: nil, afterText: "b", turnIds: [nil, nil, nil], texts: ["a", "b", "c"]), 2)
        XCTAssertEqual(ApprovalPlace.index(anchor: nil, afterText: "zz", turnIds: [nil, nil], texts: ["a", "b"]), 2)
    }
}
