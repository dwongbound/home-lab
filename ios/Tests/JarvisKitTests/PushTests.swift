import XCTest
@testable import JarvisKit

final class PushTests: XCTestCase {
    func testTokenAsHex() {
        XCTAssertEqual(PushWords.hex(Data([0x00, 0xAB, 0x10, 0xFF])), "00ab10ff")
    }

    func testEnvironmentFollowsTheBuild() {
        XCTAssertEqual(PushWords.environment(debug: true), "sandbox")
        XCTAssertEqual(PushWords.environment(debug: false), "production")
    }

    func testApprovalAndNoticeIdsFromThePayload() {
        XCTAssertEqual(PushWords.approvalId(from: ["approval_id": "ap1", "aps": [:]]), "ap1")
        XCTAssertEqual(PushWords.approvalId(from: ["jarvis": ["approval_id": "ap2"]]), "ap2")
        XCTAssertNil(PushWords.approvalId(from: ["approval_id": ""]))
        XCTAssertEqual(PushWords.noticeId(from: ["jarvis": ["notice_id": "n1"]]), "n1")
        XCTAssertNil(PushWords.noticeId(from: [:]))
    }
}
