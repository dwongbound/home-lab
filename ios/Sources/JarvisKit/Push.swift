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

    /// Which APNs a build's tokens belong to, from its provisioning profile
    /// (embedded.mobileprovision) rather than the build configuration
    /// (Dylan, 2026-11-21: a Release build installed from Xcode registered
    /// as "production", APNs refused its sandbox token, and no pushes came).
    /// The profile's `aps-environment` entitlement "development" means the
    /// sandbox; no profile (TestFlight, App Store) or "production" means
    /// production.
    public static func environment(profile: Data?) -> String {
        guard let profile, let plist = profilePlist(profile) else { return "production" }
        let entitlements = plist["Entitlements"] as? [String: Any]
        return (entitlements?["aps-environment"] as? String) == "development" ? "sandbox" : "production"
    }

    /// The property list inside a provisioning profile (a signed CMS
    /// envelope around an XML plist): cut out from "<?xml" to "</plist>".
    static func profilePlist(_ data: Data) -> [String: Any]? {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex) else { return nil }
        let xml = data.subdata(in: start.lowerBound..<end.upperBound)
        return (try? PropertyListSerialization.propertyList(from: xml, options: [], format: nil)) as? [String: Any]
    }

    /// The approval a notification is about, from `approval_id` at the top
    /// of the payload or inside its `jarvis` part.
    public static func approvalId(from payload: [AnyHashable: Any]) -> String? {
        text(payload["approval_id"]) ?? text((payload["jarvis"] as? [String: Any])?["approval_id"])
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

    /// The report a notification is about (`report_id`, 16 lowercase hex),
    /// so tapping it opens the report; anything else reads as none.
    public static func reportId(from payload: [AnyHashable: Any]) -> String? {
        let raw = text(payload["report_id"]) ?? text((payload["jarvis"] as? [String: Any])?["report_id"])
        guard let raw, raw.count == 16, raw.allSatisfy({ ("0"..."9").contains($0) || ("a"..."f").contains($0) }) else { return nil }
        return raw
    }

    /// A string field, or a number written as text; nil for anything else or empty.
    static func text(_ any: Any?) -> String? {
        if let s = any as? String { return s.isEmpty ? nil : s }
        if let n = any as? NSNumber { return n.stringValue }
        return nil
    }

    /// The notice a notification is about (`notice_id`), so tapping it can
    /// open the list there.
    public static func noticeId(from payload: [AnyHashable: Any]) -> String? {
        text(payload["notice_id"]) ?? text((payload["jarvis"] as? [String: Any])?["notice_id"])
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

/// A tapped notification, read once off the system's response into plain
/// values (Dylan, 2026-11-18: tapping a notification crashed the app). Every
/// field is optional and read leniently: a number may come as text, a
/// missing or odd field reads as none, and a shape nobody planned for just
/// opens the app. Sendable, so it can cross to the main thread safely.
public struct PushTap: Equatable, Sendable {
    /// What he did: opened it, Approve, Deny, or swiped it away.
    public let response: NoticeResponse
    public let noticeId: String?
    public let approvalId: String?
    public let turnId: Int?
    public let reportId: String?
    /// The alert's words (may be empty: a push can carry only a title).
    public let body: String

    /// Reads a payload. `action` is the response's action identifier.
    public init(payload: [AnyHashable: Any], action: String, body: String = "") {
        response = NoticeResponse.from(action: action)
        noticeId = PushWords.noticeId(from: payload)
        approvalId = PushWords.approvalId(from: payload)
        turnId = PushWords.turnId(from: payload)
        reportId = PushWords.reportId(from: payload)
        self.body = body
    }

    /// The "While you were asleep" summary: its notice id starts "held-"
    /// and isn't in the notices list, so it opens the list and clears nothing.
    public var isHeldSummary: Bool { noticeId?.hasPrefix("held-") == true }

    /// The approval to answer from the lock screen, if this was Approve or Deny on one.
    public var answer: (id: String, ok: Bool)? {
        guard let approvalId, response == .approved || response == .denied else { return nil }
        return (approvalId, response == .approved)
    }

    /// The notice to clear everywhere: acted on, and a real notice.
    public var noticeToClear: String? {
        guard response.clearsNotice, !isHeldSummary else { return nil }
        return noticeId
    }

    /// Where a tap goes.
    public enum Destination: Equatable, Sendable {
        /// Just open the app (Approve/Deny, a swipe, or nothing to show).
        case app
        case report(String)
        case turn(Int)
        case notices
    }

    /// A report first, then the chat turn, else the notices list; only a
    /// plain tap goes anywhere.
    public var destination: Destination {
        guard response == .opened else { return .app }
        if isHeldSummary { return .notices }
        if let reportId { return .report(reportId) }
        if let turnId { return .turn(turnId) }
        return .notices
    }
}
