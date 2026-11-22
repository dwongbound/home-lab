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
        // A tap that launched the app is handled now that it's ready.
        if let tap = waitingTap {
            waitingTap = nil
            handle(tap)
        }
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
            PushLog.add("launch: switch \(enabled ? "on" : "off"), permission \(settings.authorizationStatus.rawValue)")
            if enabled && settings.authorizationStatus == .notDetermined {
                // Never asked on this device (the iPad had no token at all).
                await askIfNeeded()
            } else if enabled && (settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional || settings.authorizationStatus == .ephemeral) {
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
        // From the build's own provisioning profile: an Xcode install (any
        // configuration) has a development profile and a sandbox token.
        let profile = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision").flatMap { try? Data(contentsOf: $0) }
        let environment = PushWords.environment(profile: profile)
        PushLog.add("got a token (\(environment))")
        Task {
            do {
                try await app.client.registerPush(token: hex, platform: "ios", environment: environment, bundle: Bundle.main.bundleIdentifier ?? "com.dwongbound.jarvis", name: UIDevice.current.name)
                UserDefaults.standard.set(hex, forKey: Self.tokenKey)
                status = .registered
                PushLog.add("registered with Jarvis (\(environment))")
            } catch {
                // Tried again at the next launch.
                status = .failed(error.localizedDescription)
                PushLog.add("register failed: \(error.localizedDescription)")
            }
        }
    }

    /// Banners show while the app is open too, and the snapshot is fetched
    /// at once so the new orange dot appears straight away. Being shown is
    /// not acting on it: nothing is cleared (NoticeResponse.shown).
    ///
    /// The completion-handler form, answered on the main thread. The async
    /// form let the system's own completion run on a background thread,
    /// which UIKit doesn't allow (the likely cause of the tap crash,
    /// Dylan 2026-11-18).
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        nonisolated(unsafe) let done = completionHandler
        let turnId = PushWords.turnId(from: notification.request.content.userInfo)
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                guard let app = self.app else { done([.banner, .list, .sound]); return }
                Task { await app.today.load(app: app) }
                // A reply to the chat he's looking at: it's already on
                // screen (the app catches up), so no banner or sound.
                if turnId != nil, app.tab == .chat {
                    Task { await app.chat.catchUp(app: app) }
                    done([.list])
                } else {
                    done([.banner, .list, .sound])
                }
            }
        }
    }

    /// Tapping a notification (or Approve/Deny on it) is acting on it: the
    /// notice is cleared everywhere, so its orange dot fades on every
    /// device. Swiping it away is not acting (NoticeResponse in JarvisKit).
    /// Everything needed is read off the response here, into plain values
    /// (PushTap), then handled on the main thread, and the system's
    /// completion is called there too. A tap that cold-launches the app
    /// before it's ready waits and is handled once `start(app:)` runs.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let content = response.notification.request.content
        let tap = PushTap(payload: content.userInfo, action: response.actionIdentifier, body: content.body.isEmpty ? content.title : content.body)
        nonisolated(unsafe) let done = completionHandler
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if self.app == nil {
                    self.waitingTap = tap
                } else {
                    self.handle(tap)
                }
                done()
            }
        }
    }

    /// A tap that arrived before the app was ready (a cold launch).
    private var waitingTap: PushTap?

    /// What a tap does: answers an approval, clears its notice, then opens
    /// the report, the chat turn or the notices list (PushTap.destination).
    private func handle(_ tap: PushTap) {
        guard let app else { return }
        Task {
            if let answer = tap.answer {
                await app.answerApproval(id: answer.id, summary: tap.body, ok: answer.ok)
            }
            if let noticeId = tap.noticeToClear { await app.clearNotices([noticeId]) }
        }
        switch tap.destination {
        case .app:
            break
        case .report(let reportId):
            // "Report ready": the report itself, in the app's reader.
            Task { await app.openReport(id: reportId) }
        case .turn(let turnId):
            let about = app.notice(id: tap.noticeId, turnId: turnId)
                ?? Notice(id: tap.noticeId ?? "push-\(turnId)", kind: .fyi, title: "Jarvis", body: tap.body, source: "push", created: "", turnId: turnId)
            Task { await app.openTurn(turnId, about: about) }
        case .notices:
            app.showNotices = true
        }
    }
}


/// A short log of push setup on this device (no tokens), kept in the app's
/// Documents as push-log.txt so it can be read back from the Mac.
enum PushLog {
    static func add(_ line: String) {
        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let url = dir.appendingPathComponent("push-log.txt")
        let stamp = ISO8601DateFormatter().string(from: Date())
        var lines = ((try? String(contentsOf: url, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
        lines.append("\(stamp) \(line)")
        try? lines.suffix(60).joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}
