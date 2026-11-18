// Push notifications on iPhone and iPad (Dylan, 2026-11-18). Asks once, at
// a sensible moment: the first time a notice turns up in the app (or when
// the Settings switch is turned on). With permission, the app registers
// with APNs and hands its token to the page server, again whenever it
// changes. Banners show even while the app is open. Tapping one opens the
// Notices sheet; an approval's banner carries Approve (needs the phone
// unlocked) and Deny, which answer it straight from the lock screen.
import UIKit
import UserNotifications
import JarvisKit

@MainActor
final class PushCenter: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = PushCenter()
    /// What's true about push right now, for the Settings line.
    @Published private(set) var status: PushStatus = .waiting
    /// Set once permission has been asked after this update (first launch).
    private static let askedKey = "push.askedOnLaunch"
    /// The Settings switch "Notifications", on by default.
    static let enabledKey = "push.enabled"
    /// The last token sent to the server, so a change is noticed.
    private static let tokenKey = "push.lastToken"
    private weak var app: AppModel?

    /// Wires up the delegate and the Approve/Deny category; registers again
    /// at launch if permission was already given.
    func start(app: AppModel) {
        self.app = app
        let center = UNUserNotificationCenter.current()
        // Already set at launch by the app delegate; set again in case.
        center.delegate = self
        let approve = UNNotificationAction(identifier: PushWords.approveAction, title: "Approve", options: [.authenticationRequired])
        let deny = UNNotificationAction(identifier: PushWords.denyAction, title: "Deny", options: [.destructive])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: PushWords.approvalCategory, actions: [approve, deny], intentIdentifiers: []),
        ])
        Task {
            // First launch after this update: ask now rather than waiting for
            // a notice to turn up.
            if enabled && !UserDefaults.standard.bool(forKey: Self.askedKey) {
                UserDefaults.standard.set(true, forKey: Self.askedKey)
                await askIfNeeded()
            }
            await refreshStatus()
            let settings = await center.notificationSettings()
            if enabled && (settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional) {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    /// Works out the Settings line from the switch and the permission.
    func refreshStatus() async {
        guard enabled else { status = .off; return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .denied: status = .notAllowed
        case .notDetermined: status = .waiting
        default:
            if case .failed = status { return }
            status = UserDefaults.standard.string(forKey: Self.tokenKey) == nil ? .waiting : .registered
        }
    }

    /// True while the Settings switch is on.
    var enabled: Bool {
        UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    /// Asks for permission if it hasn't been asked yet, then registers.
    func askIfNeeded() async {
        guard enabled else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge, .timeSensitive])) ?? false
            if granted { UIApplication.shared.registerForRemoteNotifications() } else { status = .notAllowed }
        case .authorized, .provisional, .ephemeral:
            UIApplication.shared.registerForRemoteNotifications()
        default:
            break
        }
    }

    /// The Settings switch changed: register, or stop taking pushes.
    func setEnabled(_ on: Bool) {
        if on {
            Task { await askIfNeeded(); await refreshStatus() }
        } else {
            UIApplication.shared.unregisterForRemoteNotifications()
            UserDefaults.standard.removeObject(forKey: Self.tokenKey)
            status = .off
        }
    }

    /// APNs gave a token: send it to the page server (every launch is cheap
    /// and keeps the server's copy fresh).
    func gotToken(_ token: Data) {
        guard let app else { return }
        let hex = PushWords.hex(token)
        #if DEBUG
        let environment = PushWords.environment(debug: true)
        #else
        let environment = PushWords.environment(debug: false)
        #endif
        Task {
            do {
                try await app.client.registerPush(token: hex, platform: "ios", environment: environment, bundle: Bundle.main.bundleIdentifier ?? "com.dwongbound.jarvis", name: UIDevice.current.name)
                UserDefaults.standard.set(hex, forKey: Self.tokenKey)
                status = .registered
            } catch {
                // Tried again at the next launch.
                status = .failed(error.localizedDescription)
            }
        }
    }

    /// Banners show while the app is open too, and the snapshot is fetched
    /// at once so the new orange dot appears straight away. Being shown is
    /// not acting on it: nothing is cleared (NoticeResponse.shown).
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        await MainActor.run {
            if let app = self.app { Task { await app.today.load(app: app) } }
        }
        return [.banner, .list, .sound]
    }

    /// Tapping a notification (or Approve/Deny on it) is acting on it: the
    /// notice is cleared everywhere, so its orange dot fades on every
    /// device. A tap also opens the Notices sheet. Swiping it away is not
    /// acting (NoticeResponse in JarvisKit).
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let payload = response.notification.request.content.userInfo
        let reply = NoticeResponse.from(action: response.actionIdentifier)
        let approvalId = PushWords.approvalId(from: payload)
        let noticeId = PushWords.noticeId(from: payload)
        await MainActor.run {
            guard let app = self.app else { return }
            Task {
                if let approvalId, reply == .approved || reply == .denied {
                    await app.answerApproval(id: approvalId, summary: response.notification.request.content.body, ok: reply == .approved)
                }
                if reply.clearsNotice, let noticeId { await app.clearNotices([noticeId]) }
            }
            // A tap opens the full message in Chat when the push points at
            // one; otherwise the Notices list.
            if reply == .opened {
                if let turnId = PushWords.turnId(from: payload) {
                    Task { await app.openTurn(turnId) }
                } else {
                    app.showNotices = true
                }
            }
        }
    }
}
