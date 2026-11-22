import XCTest
@testable import JarvisKit

/// Which APNs environment a build registers for, from its profile.
final class PushProfileTests: XCTestCase {
    /// A profile as installed: signed binary around the XML plist.
    private func profile(aps: String?) -> Data {
        let entitlement = aps.map { "<key>aps-environment</key><string>\($0)</string>" } ?? ""
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict><key>Name</key><string>iOS Team Provisioning Profile: com.dwongbound.jarvis</string>
        <key>Entitlements</key><dict>\(entitlement)<key>application-identifier</key><string>TEAM.com.dwongbound.jarvis</string></dict></dict></plist>
        """
        var data = Data([0x30, 0x82, 0x4e, 0x1f, 0x06, 0x09, 0x2a, 0x86])
        data.append(Data(xml.utf8))
        data.append(Data([0xa0, 0x82, 0x0d, 0x00, 0xff]))
        return data
    }

    func testDevelopmentProfileIsSandbox() {
        XCTAssertEqual(PushWords.environment(profile: profile(aps: "development")), "sandbox")
    }

    func testProductionProfileIsProduction() {
        XCTAssertEqual(PushWords.environment(profile: profile(aps: "production")), "production")
    }

    func testNoProfileIsProduction() {
        XCTAssertEqual(PushWords.environment(profile: nil), "production", "TestFlight and App Store builds carry none")
    }

    func testProfileWithoutPushOrGarbage() {
        XCTAssertEqual(PushWords.environment(profile: profile(aps: nil)), "production")
        XCTAssertEqual(PushWords.environment(profile: Data([1, 2, 3])), "production")
    }
}
