import XCTest
@testable import JarvisKit

final class DemoSnapshotTests: XCTestCase {
    /// The sample data the simulator screenshots use must keep decoding.
    func testSampleSnapshotsDecode() throws {
        let full = try XCTUnwrap(DemoSnapshot.build(now: Date(), sparse: false))
        XCTAssertEqual(full.notices.count, 4)
        XCTAssertFalse(full.events.isEmpty)
        XCTAssertNotNil(DemoSnapshot.build(now: Date(), sparse: true))
    }
}
