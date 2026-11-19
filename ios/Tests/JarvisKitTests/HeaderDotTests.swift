import XCTest
@testable import JarvisKit

final class HeaderDotTests: XCTestCase {
    private func notice(_ id: String, _ kind: NoticeKind) -> Notice {
        Notice(id: id, kind: kind, title: "x", source: "job", created: "")
    }

    func testOneDotHoweverManyAndNoneForNone() {
        XCTAssertNil(Notices.headerDot([]))
        let four = [notice("a", .fyi), notice("b", .heads), notice("c", .fyi), notice("d", .heads)]
        XCTAssertEqual(Notices.headerDot(four), .heads, "one dot, in the most urgent one's shade")
        XCTAssertEqual(Notices.headerDot(four + [notice("e", .need)]), .need)
        XCTAssertEqual(Notices.countLabel(four), "4 new", "the count still says how many")
    }
}

final class KeepDotTests: XCTestCase {
    func testKeepIsOfferedOnlyWhereClosingWouldClear() {
        XCTAssertTrue(Orbit.offersKeep(Notice(id: "a", kind: .heads, title: "Laundry done", source: "alert", created: "")))
        XCTAssertTrue(Orbit.offersKeep(Notice(id: "b", kind: .fyi, title: "x", source: "job", created: "")))
        XCTAssertFalse(Orbit.offersKeep(Notice(id: "c", kind: .need, title: "x", source: "lookout", created: "")), "a need stays until answered anyway")
        XCTAssertFalse(Orbit.offersKeep(Notice(id: "d", kind: .need, title: "x", source: "approval", created: "", approvalId: "ap")))
    }
}
