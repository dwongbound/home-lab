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
final class PushCenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = PushCenter()
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
        center.delegate = self
        let approve = UNNotificationAction(identifier: PushWords.approveAction, title: "Approve", options: [.authenticationRequired])
        let deny = UNNotificationAction(identifier: PushWords.denyAction, title: "Deny", options: [.destructive])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: PushWords.approvalCategory, actions: [approve, deny], intentIdentifiers: []),
        ])
        Task {
            let settings = await center.notificationSettings()
            if enabled && settings.authorizationStatus == .authorized {
                UIApplication.shared.registerForRemoteNotifications()
            }
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
            if granted { UIApplication.shared.registerForRemoteNotifications() }
        case .authorized, .provisional, .ephemeral:
            UIApplication.shared.registerForRemoteNotifications()
        default:
            break
        }
    }

    /// The Settings switch changed: register, or stop taking pushes.
    func setEnabled(_ on: Bool) {
        if on {
            Task { await askIfNeeded() }
        } else {
            UIApplication.shared.unregisterForRemoteNotifications()
            UserDefaults.standard.removeObject(forKey: Self.tokenKey)
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
            } catch {
                // Tried again at the next launch.
            }
        }
    }

    /// Banners show while the app is open too.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    /// A tap opens the Notices sheet; Approve or Deny answers the approval.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let payload = response.notification.request.content.userInfo
        let action = response.actionIdentifier
        let approvalId = PushWords.approvalId(from: payload)
        await MainActor.run {
            guard let app = self.app else { return }
            if let approvalId, action == PushWords.approveAction || action == PushWords.denyAction {
                let ok = action == PushWords.approveAction
                Task { try? await app.client.answer(approval: approvalId, ok: ok) }
            } else {
                app.showNotices = true
            }
        }
    }
}
