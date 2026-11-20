// The app's shell state: which server, which tab, whether the PC answered
// last time. Chat and Today keep their own models.
import Combine
import LocalAuthentication
import SwiftUI
import UIKit
import JarvisKit

/// The tabs along the bottom (a sidebar on iPad).
/// The pages, left to right (Dylan, 2026-11-18: "change the default tab to
/// home, make it all the way left and then right of it is talk and then
/// chat"). The order here is the bar's and the swipe's.
enum AppTab: Hashable, CaseIterable {
    case today
    case talk
    case chat

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
    /// Home first: the app opens on Home every launch (Dylan, 2026-11-18).
    @Published var tab: AppTab = .today
    @Published var showSettings = false
    /// nil until the first request; then whether the PC answered.
    @Published var reachable: Bool?
    /// The PC answers but Jarvis is restarting or down (502, 503, 504,
    /// after the quiet retries); the top line says so.
    @Published var jarvisRestarting = false
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
    @Published private(set) var clearedNotices = PendingClears()
    /// Said in the drawer when a dismiss didn't go through.
    @Published var noticeProblem: String?

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
        Notices.unread(allNotices)
    }

    /// Everything from the snapshot: unread and kept, with this device's own
    /// keeps and let-gos laid over until the next snapshot catches up.
    private var allNotices: [Notice] {
        var list = settled.showing(Notices.sorted((today.snapshot?.notices ?? []).filter { !clearedNotices.ids.contains($0.id) }))
        list.removeAll { $0.kept && letGoHere.contains($0.id) }
        for notice in keptNoticesHere where !list.contains(where: { $0.id == notice.id }) { list.append(notice) }
        return list
    }

    /// Kept to remember (yellow dots): never unread, untouched by Clear.
    var keptNotices: [Notice] {
        Notices.kept(allNotices)
    }

    /// What orbits the orb: the unread (orange) and the kept (yellow).
    var orbitNotices: [Notice] {
        notices + keptNotices
    }

    /// Kept here and not yet in a snapshot.
    @Published private var keptNoticesHere: [Notice] = []
    /// Let go here and maybe still in the last snapshot.
    @Published private var letGoHere: Set<String> = []
    /// Chat turns kept here (by turn id), until the next history load says so.
    @Published private(set) var keptTurnsHere: Set<Int> = []

    /// The turns among `items` that are kept, worked out with one pass over
    /// the notices (not one per message, as isKept would be).
    func keptTurns(in items: [ChatItem]) -> Set<Int> {
        var byTurn: [Int: Notice] = [:]
        for notice in Notices.kept(allNotices) { if let turn = notice.turnId { byTurn[turn] = notice } }
        var out = Set<Int>()
        for item in items {
            guard let turn = item.turnId else { continue }
            if let notice = byTurn[turn] {
                if !letGoHere.contains(notice.id) { out.insert(turn) }
            } else if keptTurnsHere.contains(turn) || item.kept {
                out.insert(turn)
            }
        }
        return out
    }

    /// True when a chat turn is kept (by Jarvis's record or just now here).
    func isKept(turnId: Int?, historyKept: Bool) -> Bool {
        guard let turnId else { return false }
        if let notice = Notices.kept(turnId: turnId, in: allNotices) { return !letGoHere.contains(notice.id) }
        return keptTurnsHere.contains(turnId) || historyKept
    }

    /// Keeps a chat message as a yellow dot (Dylan, 2026-11-19: "jarvis
    /// tells me something and i want to keep it so i remember it later").
    func keep(turnId: Int) async {
        keptTurnsHere.insert(turnId)
        do {
            let result = try await client.keep(turnId: turnId)
            if result.ok {
                if let notice = result.notice { keptNoticesHere.append(notice) }
                await today.load(app: self)
            } else {
                keptTurnsHere.remove(turnId)
                chat.problem = result.message.isEmpty ? "Jarvis couldn't keep that." : result.message
            }
        } catch {
            keptTurnsHere.remove(turnId)
            noteReach(error)
        }
    }

    /// Keeps a notice as a yellow dot (from its card on the orb or its full
    /// view); viewing never clears it, only Unkeep does.
    func keep(_ notice: Notice) async {
        if let turnId = notice.turnId { keptTurnsHere.insert(turnId) }
        do {
            let result = try await client.keep(noticeId: notice.id)
            if result.ok {
                if let kept = result.notice { keptNoticesHere.append(kept) }
                await today.load(app: self)
            } else {
                if let turnId = notice.turnId { keptTurnsHere.remove(turnId) }
                noticeProblem = result.message.isEmpty ? "Jarvis couldn't keep that." : result.message
            }
        } catch {
            if let turnId = notice.turnId { keptTurnsHere.remove(turnId) }
            noteReach(error)
        }
    }

    /// Lets a kept item go (from its yellow dot, or the message in chat).
    func letGo(_ notice: Notice) async {
        letGoHere.insert(notice.id)
        keptNoticesHere.removeAll { $0.id == notice.id }
        if let turnId = notice.turnId { keptTurnsHere.remove(turnId) }
        do {
            let result = try await client.unkeep(noticeId: notice.id)
            if result.ok {
                await today.load(app: self)
            } else {
                letGoHere.remove(notice.id)
                chat.problem = result.message.isEmpty ? "Jarvis couldn't let that go." : result.message
            }
        } catch {
            letGoHere.remove(notice.id)
            noteReach(error)
        }
    }

    /// Let go of a chat message by its turn: finds its kept item.
    func letGo(turnId: Int) async {
        if let notice = Notices.kept(turnId: turnId, in: allNotices) {
            await letGo(notice)
        } else {
            keptTurnsHere.remove(turnId)
        }
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
        if !noticeIds.isEmpty { clearedNotices.hide(Array(noticeIds)) }
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
        clearedNotices.hide(ids)
        do {
            try await client.clearNotices(ids: ids)
            await today.load(app: self)
        } catch {
            clearedNotices.restore(ids)
            noticeProblem = "Couldn't reach Jarvis, so that notice is back. Try again in a moment."
        }
    }

    /// The report showing in the app's reader, if any.
    @Published var report: ReportPage?
    /// What a Keep or Delete is waiting on ("Deleting the report…"), shown
    /// as a labelled, blocking wait.
    @Published private(set) var reportBusy: String?
    /// Keep switched here, shown at once until the snapshot catches up.
    @Published private var retentionHere: [String: Retention] = [:]
    /// Something to say about a report change that didn't happen.
    @Published var reportMessage: String?
    /// Reports deleted here, hidden at once.
    @Published private var deletedHere: Set<String> = []

    /// Jarvis's reports from the snapshot, with this device's own changes
    /// laid over it; nil from an older Jarvis.
    var reportShelf: ReportShelf? {
        guard var shelf = today.snapshot?.reports else { return nil }
        shelf.reports = shelf.reports
            .filter { !deletedHere.contains($0.id) }
            .map { report in retentionHere[report.id].map { report.retained($0) } ?? report }
        return shelf
    }

    /// Opens a report in the app's own reader (never Safari). The notice it
    /// came from is read, so it clears everywhere like any other. A bad id
    /// opens nothing.
    func openReport(id: String, title: String? = nil, clearing notice: Notice? = nil) async {
        guard Reports.isId(id) else { return }
        if showNotices {
            // Let the notices sheet finish going before the report comes up.
            showNotices = false
            try? await Task.sleep(for: .milliseconds(450))
        }
        report = ReportPage(id: id, title: title ?? reportShelf?.reports.first { $0.id == id }?.title)
        if let notice { await clearNotices([notice.id]) }
    }

    /// How long a report is kept: 2 weeks, 1 month, 3 months or forever.
    /// Saves at once; an older server that can't take spans says so.
    func setRetention(_ id: String, _ retention: Retention) async {
        reportBusy = "Saving…"
        defer { reportBusy = nil }
        do {
            switch try await client.setRetention(id: id, retention) {
            case .saved:
                retentionHere[id] = retention
                await today.load(app: self)
            case .notYet:
                reportMessage = RetentionReply.notYetWords
            case .failed(let words):
                reportMessage = words
            }
        } catch {
            noteReach(error)
            reportMessage = error.localizedDescription
        }
    }

    /// The report's page as a .html file named from its title, ready for
    /// the share sheet (Files, Messages, Mail, AirDrop); nil when it can't
    /// be fetched.
    func reportFile(id: String, title: String) async -> URL? {
        reportBusy = "Getting the report ready…"
        defer { reportBusy = nil }
        guard case .page(let html) = await client.report(id: id) else {
            reportMessage = "The report couldn't be fetched to share. Try again in a moment."
            return nil
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("share-\(id)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(Reports.shareFileName(title))
        do {
            try Data(html.utf8).write(to: file, options: .atomic)
            return file
        } catch {
            reportMessage = error.localizedDescription
            return nil
        }
    }

    /// Deletes a report now. True when it went.
    @discardableResult
    func deleteReport(_ id: String) async -> Bool {
        reportBusy = "Deleting the report…"
        defer { reportBusy = nil }
        do {
            try await client.deleteReport(id: id)
            deletedHere.insert(id)
            await today.load(app: self)
            return true
        } catch {
            noteReach(error)
            return false
        }
    }

    /// Opens Chat at the message a notice previews (acting on it, so the
    /// notice clears everywhere). `about` is the notice itself: when its
    /// message isn't in the chat any more (or it has none), its own full
    /// text opens instead (JarvisKit NoticeFocus).
    func openTurn(_ turnId: Int?, clearing notice: Notice? = nil, about: Notice? = nil) async {
        showNotices = false
        if turnId == nil, let about {
            readingNotice = about
        } else {
            focusFallback = about ?? notice
            tab = .chat
            focusTurn = turnId
        }
        if let notice { await clearNotices([notice.id]) }
    }

    /// Jobs stopped here, hidden until the next snapshot drops them.
    @Published private(set) var stoppedJobs: Set<String> = []

    /// Stops a running job on Jarvis; it leaves the list only once Jarvis
    /// says it stopped (or had already finished). Words when it didn't.
    func stopJob(_ task: RunningTask) async -> String? {
        do {
            switch try await client.stopJob(id: task.id) {
            case .stopped(let words):
                stoppedJobs.insert(task.id)
                await today.load(app: self)
                return words
            case .gone:
                stoppedJobs.insert(task.id)
                await today.load(app: self)
                return nil
            case .failed(let words):
                return words
            }
        } catch {
            noteReach(error)
            return (error as? JarvisError)?.errorDescription ?? ErrorWording.unreachable
        }
    }

    /// A notice read in full (its whole text, source and time).
    @Published var readingNotice: Notice?
    /// The notice to show if its message can't be found in Chat.
    var focusFallback: Notice?

    /// The notice a push was about, if this device knows it.
    func notice(id: String?, turnId: Int?) -> Notice? {
        allNotices.first { ($0.id == id && id != nil) || ($0.turnId == turnId && turnId != nil) }
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
        clearedNotices.hide(ids)
        do {
            try await client.clearAllNotices()
        } catch {
            clearedNotices.restore(ids)
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
        let restarting = error.map(ConnectionStatus.isJustNotAnswering) ?? false
        if restarting != jarvisRestarting { jarvisRestarting = restarting }
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
