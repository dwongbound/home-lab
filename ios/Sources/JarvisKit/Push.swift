// Push notifications (Dylan, 2026-11-18: paid membership, "let's add
// notifications and everything"). The plain rules the iOS app's push code
// relies on: the device token as hex for the page server, which APNs
// environment a build talks to, and reading an approval out of a payload so
// the lock screen's Approve and Deny can answer it.
import Foundation

public enum PushWords {
    /// The notification category whose banners carry Approve and Deny.
    public static let approvalCategory = "APPROVAL"
    public static let approveAction = "APPROVE"
    public static let denyAction = "DENY"

    /// The device token as lowercase hex, the way APNs and the server want it.
    public static func hex(_ token: Data) -> String {
        token.map { String(format: "%02x", $0) }.joined()
    }

    /// Xcode builds talk to APNs' sandbox; TestFlight and App Store builds
    /// to production.
    public static func environment(debug: Bool) -> String {
        debug ? "sandbox" : "production"
    }

    /// The approval a notification is about, from `approval_id` at the top
    /// of the payload or inside its `jarvis` part.
    public static func approvalId(from payload: [AnyHashable: Any]) -> String? {
        if let id = payload["approval_id"] as? String, !id.isEmpty { return id }
        if let jarvis = payload["jarvis"] as? [String: Any], let id = jarvis["approval_id"] as? String, !id.isEmpty { return id }
        return nil
    }

    /// The notice a notification is about (`notice_id`), so tapping it can
    /// open the list there.
    public static func noticeId(from payload: [AnyHashable: Any]) -> String? {
        if let id = payload["notice_id"] as? String, !id.isEmpty { return id }
        if let jarvis = payload["jarvis"] as? [String: Any], let id = jarvis["notice_id"] as? String, !id.isEmpty { return id }
        return nil
    }
}
