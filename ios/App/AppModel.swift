// The app's shell state: which server, which tab, whether the PC answered
// last time. Chat and Today keep their own models.
import Combine
import LocalAuthentication
import SwiftUI
import UIKit
import JarvisKit

/// The tabs along the bottom (a sidebar on iPad).
enum AppTab: Hashable, CaseIterable {
    case chat
    case talk
    case today

    /// The tab `step` places along (1 = right), stopping at the ends.
    func neighbour(_ step: Int) -> AppTab {
        let all = Self.allCases
        let index = all.firstIndex(of: self) ?? 0
        return all[min(max(index + step, 0), all.count - 1)]
    }
}

@MainActor
final class AppModel: ObservableObject {
    private static let serverKey = "jarvis.server"

    /// The home page's address. Saved, so a change in Settings sticks.
    @Published var server: String {
        didSet { UserDefaults.standard.set(server, forKey: Self.serverKey) }
    }
    /// Talk first: opening the app goes straight to the voice line (Dylan, 2026-11-17).
    @Published var tab: AppTab = .talk
    @Published var showSettings = false
    /// nil until the first request; then whether the PC answered.
    @Published var reachable: Bool?
    /// True while the iPad's full-screen kiosk is up (from the Home tab's
    /// Kiosk button, or by itself when idle on charge).
    @Published var padKiosk = false {
        didSet { if !padKiosk { noteActivity() } }
    }
    /// The last touch, keystroke or tab change; the iPad's idle kiosk counts
    /// five quiet minutes from here.
    private(set) var lastActivity = Date()
    /// True while the notices sheet is up.
    @Published var showNotices = false
    /// A chat turn to open (scroll to and highlight), set by a tapped
    /// notification or notice; the Chat tab takes it and clears it.
    @Published var focusTurn: Int?
    /// Notices cleared here but not yet gone from the snapshot: hidden at
    /// once so the list doesn't flicker back before the next poll.
    @Published private(set) var clearedNotices: Set<String> = []

    /// The Settings switch "Kiosk when idle on charge", on by default.
    static let idleKioskKey = "kiosk.padIdle"

    /// Money details stay hidden until Face ID (or the passcode) says it's
    /// Dylan, and hide again whenever the app goes to the background.
    @Published private(set) var moneyUnlocked = false

    let chat = ChatModel()
    let today = TodayModel()
    let talk = TalkModel()
    private var relay: AnyCancellable?
    private var relayToday: AnyCancellable?

    /// Approvals that are over (JarvisKit SettledApprovals): their cards,
    /// notice rows and orbit dots never come back, for a day, even while
    /// the PC's lists still name them for a moment.
    @Published private(set) var settled = SettledApprovals.load()

    /// The unread notices, newest first, less any just cleared here and any
    /// approval that's already over.
    var notices: [Notice] {
        settled.showing(Notices.sorted((today.snapshot?.notices ?? []).filter { !clearedNotices.contains($0.id) }))
    }

    /// An approval is over (answered here, out loud, timed out,
    /// or Jarvis says it's gone): remembered, and its card collapses into
    /// `line` in Chat and Talk, its notice goes. A second word on the same
    /// id is ignored unless `replace` (the PC's own account beats ours).
    func settleApproval(_ id: String, line: String, replace: Bool = false) {
        if settled.isSettled(id) {
            guard replace, settled.line(for: id) != line else { return }
            settled.unsettle(id)
        }
        settled.prune()
        settled.settle(id, line: line)
        settled.save()
        chat.showSettled(id, line: line)
        talk.showSettled(id, line: line)
        let noticeIds = (today.snapshot?.notices ?? []).filter { $0.approvalId == id }.map(\.id)
        if !noticeIds.isEmpty { clearedNotices.formUnion(noticeIds) }
    }

    /// Approve or Deny from any screen. The card settles at once; if Jarvis
    /// says it was already over, his account of it replaces ours and that's
    /// the end of it (no error, no card coming back). Only an answer that
    /// never reached him puts the card back; the message comes back for
    /// the screen.
    @discardableResult
    func answerApproval(id: String, summary: String, ok: Bool) async -> String? {
        settleApproval(id, line: ApprovalWording.settledLine(ok: ok, later: false, by: "page", summary: summary))
        do {
            switch try await client.answer(approval: id, ok: ok) {
            case .taken:
                noteReach(nil)
                return nil
            case .gone(_, let answer):
                noteReach(nil)
                settleApproval(id, line: ApprovalReply.goneLine(answer: answer, summary: summary), replace: true)
                return nil
            case .failed(let message):
                unsettleApproval(id)
                return message
            }
        } catch {
            unsettleApproval(id)
            noteReach(error)
            return error.localizedDescription
        }
    }

    /// Takes back an answer that never reached Jarvis: the card returns.
    private func unsettleApproval(_ id: String) {
        settled.unsettle(id)
        settled.save()
        chat.showSettled(id, line: nil)
        talk.showSettled(id, line: nil)
    }

    /// Clears notices everywhere (the server clears them for every device);
    /// they fade here at once and come back if the server didn't hear. The
    /// snapshot is fetched again right after, so this device is current.
    func clearNotices(_ ids: [String]) async {
        clearedNotices.formUnion(ids)
        do {
            try await client.clearNotices(ids: ids)
            await today.load(app: self)
        } catch {
            clearedNotices.subtract(ids)
        }
    }

    /// Opens Chat at the message a notice previews (acting on it, so the
    /// notice clears everywhere). Without a turn, Chat opens at the bottom.
    func openTurn(_ turnId: Int?, clearing notice: Notice? = nil) async {
        showNotices = false
        tab = .chat
        focusTurn = turnId
        if let notice { await clearNotices([notice.id]) }
    }

    /// A notice was seen on the orb or in the list: read, so cleared
    /// everywhere, unless it needs an answer (Orbit.readOnView).
    func readNotice(_ notice: Notice) async {
        guard Orbit.readOnView(notice) else { return }
        await clearNotices([notice.id])
    }

    /// Approve or Deny a notice's approval, then clear the notice.
    func answerNotice(_ notice: Notice, ok: Bool) async {
        guard let approvalId = notice.approvalId else { return }
        let summary = notice.body.isEmpty ? notice.title : notice.body
        if await answerApproval(id: approvalId, summary: summary, ok: ok) == nil {
            await clearNotices([notice.id])
        }
    }

    /// Clears every notice.
    func clearAllNotices() async {
        let ids = notices.map(\.id)
        clearedNotices.formUnion(ids)
        do {
            try await client.clearAllNotices()
        } catch {
            clearedNotices.subtract(ids)
        }
    }

    /// Something happened: the five quiet minutes start again.
    func noteActivity() {
        lastActivity = Date()
    }

    /// The iPad goes to its kiosk by itself after five quiet minutes on the
    /// Talk or Chat tab while charging, with no conversation going
    /// (IdleKiosk in JarvisKit).
    func checkIdleKiosk() {
        guard UIDevice.current.userInterfaceIdiom == .pad, !padKiosk else { return }
        let battery = UIDevice.current.batteryState
        let live: Bool
        switch talk.phase {
        case .connecting: live = true
        case .on(let state): live = state != .dozing
        case .off: live = false
        }
        let enabled = UserDefaults.standard.object(forKey: Self.idleKioskKey) as? Bool ?? true
        if IdleKiosk.shouldEnter(
            enabled: enabled,
            onTalkOrChat: tab == .talk || tab == .chat,
            charging: battery == .charging || battery == .full,
            conversationActive: live || chat.isSending,
            lastActivity: lastActivity,
            now: Date()
        ) {
            padKiosk = true
        }
    }

    /// Reads the saved address, or the one the app ships with.
    init() {
        server = UserDefaults.standard.string(forKey: Self.serverKey) ?? JarvisClient.defaultBase.absoluteString
        // The Chat tab's badge counts the chat's waiting approvals, so a
        // change in the chat redraws the tab bar too.
        chat.app = self
        talk.app = self
        relay = chat.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        // The notices ride in the snapshot, so a new one redraws every orb.
        relayToday = today.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        // Push notifications: the delegate, Approve/Deny on the lock screen.
        PushCenter.shared.start(app: self)
        // Mute and End on the Dynamic Island reach the call through here.
        TalkActivityBridge.handler = { [weak self] action in
            guard let self else { return }
            switch action {
            case .toggleMute: self.talk.toggleMute()
            case .end: self.talk.hangUp()
            }
        }
    }

    /// A client for the current address (falls back to the default if the
    /// typed one isn't a URL).
    var client: JarvisClient {
        let base = URL(string: server.trimmingCharacters(in: .whitespaces)) ?? JarvisClient.defaultBase
        return JarvisClient(base: base)
    }

    /// Notes whether the last call reached the PC, for the status line.
    func noteReach(_ error: Error?) {
        if let error = error as? JarvisError, error == .unreachable {
            reachable = false
        } else {
            reachable = true
        }
    }

    /// Start on an offer card: switch to Chat and send its text there.
    func start(_ offer: Offer) {
        tab = .chat
        Task { await chat.send(offer.startText, offerId: offer.id, app: self) }
    }

    /// "Show" on a hidden money card: Face ID, falling back to the passcode.
    func unlockMoney() async {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return }
        let ok = (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Show your money details")) ?? false
        moneyUnlocked = ok
    }

    /// Hides money again (the app went to the background).
    func lockMoney() {
        moneyUnlocked = false
    }
}
