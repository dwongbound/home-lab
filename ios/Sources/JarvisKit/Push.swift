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

    /// The chat turn a notification previews (`turn_id`), so tapping it can
    /// open the chat right there. A number or its text.
    public static func turnId(from payload: [AnyHashable: Any]) -> Int? {
        func read(_ any: Any?) -> Int? {
            if let n = any as? Int { return n }
            if let n = any as? NSNumber { return n.intValue }
            if let s = any as? String { return Int(s) }
            return nil
        }
        if let id = read(payload["turn_id"]) { return id }
        if let jarvis = payload["jarvis"] as? [String: Any] { return read(jarvis["turn_id"]) }
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

/// What Dylan did with a notification, and whether that counts as acting
/// on it (Dylan, 2026-11-18: "hitting the notification from banner or lock
/// screen should dismiss it. But … the notification popping as a banner
/// without action doesn't count as viewing it"). Acting clears the notice
/// everywhere, so its orange dot fades on every device; merely being shown
/// never does.
public enum NoticeResponse: Equatable, Sendable {
    /// The banner or lock-screen notification appeared.
    case shown
    /// He tapped it.
    case opened
    case approved
    case denied
    /// He swiped it away without opening it.
    case dismissed

    /// From the system's action identifier on a response.
    public static func from(action: String) -> NoticeResponse {
        switch action {
        case PushWords.approveAction: return .approved
        case PushWords.denyAction: return .denied
        case "com.apple.UNNotificationDismissActionIdentifier": return .dismissed
        default: return .opened
        }
    }

    /// True when this clears the notice everywhere.
    public var clearsNotice: Bool {
        switch self {
        case .opened, .approved, .denied: return true
        case .shown, .dismissed: return false
        }
    }
}

/// The Settings line about push: what's true right now, in words.
public enum PushStatus: Equatable, Sendable {
    case off, notAllowed, waiting, registered, failed(String)

    public var words: String {
        switch self {
        case .off: return "Push: off"
        case .notAllowed: return "Push: not allowed (Settings → Notifications → Jarvis)"
        case .waiting: return "Push: not registered yet"
        case .registered: return "Push: registered"
        case .failed(let why): return "Push: couldn't register (\(why))"
        }
    }
}
