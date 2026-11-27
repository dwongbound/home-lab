// The chat: history from the PC, a streaming reply, approval cards and
// "That was wrong". Mirrors the web page's chat sheet (JarvisPanel).
import SwiftUI
import UIKit
import JarvisKit

/// One line in the chat.
struct ChatItem: Identifiable, Equatable {
    enum Kind: Equatable {
        case user
        case jarvis
        case approval(Approval)
    }

    /// The row's identity. Kept across reloads (ChatMerge), so a refresh
    /// never makes SwiftUI rebuild rows it already drew.
    var id: String
    var kind: Kind
    var text: String
    /// Jarvis's lines: which brain wrote it ("claude", "ornith").
    var model: String?
    /// Jarvis's lines: false while the words are still arriving.
    var finished: Bool
    /// Jarvis's lines: what Dylan asked, for "That was wrong".
    var question: String
    /// Approvals: how it ended, as its one-line history entry ("Approved:
    /// Write a file", "Timed out: …"); nil while it's still waiting.
    var outcome: String?
    /// Dylan's lines: the photos sent with it, while this session has them.
    var photos: [UIImage] = []
    /// Dylan's lines: how many photos it carried (history keeps only this).
    var photoCount = 0
    /// Jarvis's lines: "is this the meal I logged?" (its key and choices),
    /// and the choice once answered (the buttons retire).
    var mealKey: String?
    var mealChoices: [String] = []
    var mealAnswer: String?
    /// Jarvis's id for the turn (from history), so a notice can open it.
    var turnId: Int?
    /// A message he sent unasked: the model that wrote it, when one did.
    var writer: String?
    /// True when Jarvis's record says this message is kept (a yellow dot).
    var kept = false
    /// Dylan's lines: sent while a reply was running and waiting its turn
    /// (Jarvis's "queued"); a small grey "Queued" until its reply starts.
    var queued = false
    /// When it was sent (history's `at`; now, for one just sent here). Nil
    /// for approval cards. Shown on a leftward drag and in the day lines.
    var at: Date?
    /// The earlier message this one replies to, shown as a quote over it.
    var replyTo: ChatQuote?

    /// A line of Dylan's.
    static func user(_ text: String, photos: [UIImage] = [], photoCount: Int? = nil) -> ChatItem {
        ChatItem(id: UUID().uuidString, kind: .user, text: text, model: nil, finished: true, question: "", outcome: nil, photos: photos, photoCount: photoCount ?? photos.count, at: Date())
    }

    /// A reply of Jarvis's, empty until words arrive.
    static func jarvis(_ text: String, model: String?, finished: Bool, question: String) -> ChatItem {
        ChatItem(id: UUID().uuidString, kind: .jarvis, text: text, model: model, finished: finished, question: question, outcome: nil, at: Date())
    }

    /// A line of Dylan's or Jarvis's (not an approval card).
    var isTurn: Bool { if case .approval = kind { return false } else { return true } }

    /// What the history merge compares (JarvisKit ChatMerge).
    var mergeLine: MergeLine { MergeLine(id: id, turnId: turnId, isUser: kind == .user, text: text) }

    /// An approval card.
    static func approval(_ approval: Approval) -> ChatItem {
        ChatItem(id: "approval-\(approval.id)", kind: .approval(approval), text: "", model: nil, finished: true, question: "", outcome: nil)
    }
}

@MainActor
final class ChatModel: ObservableObject {
    @Published private(set) var items: [ChatItem] = []
    /// The message he's replying to (Reply in a message's menu), shown as a
    /// strip over the text box until he sends or taps its x.
    @Published var replyingTo: ChatQuote?
    /// Sends going out or replies still streaming (several at once: he can
    /// send while Jarvis is answering, Dylan 2026-11-21).
    @Published private(set) var sendsInFlight = 0
    /// True from Send until every reply has ended.
    var isSending: Bool { sendsInFlight > 0 }
    /// The slow lookup Jarvis is doing ("Searching the web."), or nil.
    @Published private(set) var working: String?
    /// The last problem, worded for Dylan, or nil.
    @Published var problem: String?
    /// True once history has loaded at least once.
    @Published private(set) var loaded = false
    /// Older turns exist on the server than the ones held (a paging server
    /// says so; today's never does).
    /// Paging older turns from the server (JarvisKit OlderPaging).
    @Published private(set) var older = OlderPaging(hasMore: false)
    var olderOnServer: Bool { older.state != .done }
    var loadingOlder: Bool { older.state == .loading }
    #if DEBUG
    /// `-demoOlderServer`: pages fetched, for the UI test.
    @Published var demoOlderFetches = 0
    /// Pages shown at the top (fetched or already held), for the UI test.
    @Published var demoOlderPages = 0
    #endif
    static var demoOlderServer: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-demoOlderServer")
        #else
        false
        #endif
    }

    /// Leaving Chat for another tab: back to the newest page only, so
    /// earlier pages are fetched again only if he scrolls up for them, and
    /// nothing old is drawn when he comes back (Dylan, 2026-11-20). A
    /// message still going out stays.
    func trimToNewest() {
        let keep = HistoryQuery.pageSize
        let turns = items.filter(\.isTurn).count
        guard turns > keep, !isSending else { return }
        var seen = 0
        var cut = items.endIndex
        for index in items.indices.reversed() where items[index].isTurn {
            seen += 1
            if seen == keep { cut = index; break }
        }
        items.removeFirst(cut)
        var paging = older
        paging.reset(hasMore: true)
        if paging != older { older = paging }
    }

    /// After a failed older page, try again (his tap).
    func retryOlder() { older.retry() }
    /// An older window is showing (opened round a notice's turn); newer
    /// turns exist past it.
    @Published private(set) var newerOnServer = false
    /// Checking for a reply that finished while the app was away.
    @Published private(set) var catchingUp = false
    /// True while photos are uploading (before the reply starts).
    @Published private(set) var uploading = false
    /// A blocking label while a meal answer goes ("Telling Jarvis…").
    @Published private(set) var busy: String?
    /// A meal answer that failed, kept for "Try again".
    @Published private(set) var failedMeal: (itemId: String, choice: String)?
    /// A message whose photos were refused, kept for "Try again".
    @Published private(set) var failed: (text: String, photos: [PickedPhoto])?
    /// Photos sent this session, by message text, so a reload keeps them
    /// on their bubbles; otherwise a past message shows "2 photos".
    private var sentPhotos: [String: [UIImage]] = [:]

    /// Approvals still waiting, for the tab's badge.
    var pendingCount: Int {
        items.filter { item in
            if case .approval = item.kind { return item.outcome == nil }
            return false
        }.count
    }

    /// Loads the chat so far and anything still waiting on an OK.
    func load(app: AppModel, around turnId: Int? = nil) async {
        #if DEBUG
        // `-demoChat` fills Chat with a long mixed history and reaches no
        // Jarvis (the scroll-lag test, UITests/ChatScrollTests.swift).
        if ProcessInfo.processInfo.arguments.contains("-demoChat") {
            // Through the same merge as a real load, so the demo shows what
            // a reload does to the rows (`-mockTalkTurns` adds turns).
            // `-demoOlderServer`: only the newest page, the rest paged in
            // from the "server" as he scrolls up (UITests/ChatOlderTests).
            if Self.demoOlderServer {
                let all = DemoChat.items()
                let newest = Array(all.suffix(ChatWindow.page))
                let next = merged(newest, around: false)
                if items.isEmpty || next.first?.turnId == newest.first?.turnId {
                    if next != items { items = next }
                    var paging = older
                    paging.reset(hasMore: all.count > newest.count)
                    if paging != older { older = paging }
                }
                if !loaded { loaded = true }
                return
            }
            let next = merged(DemoChat.items(), around: false)
            if next != items { items = next }
            if !loaded { loaded = true }
            return
        }
        #endif
        let client = app.client
        do {
            // The newest page, or a window round a turn a notice opened.
            let page = try await client.history(turnId.map { .around($0, limit: HistoryQuery.pageSize) } ?? .newest(limit: HistoryQuery.pageSize))
            let turns = page.turns
            let pending = try await client.pendingApprovals()
            // Settled approvals aren't in the PC's history, so they're kept
            // from before, each after the line it followed.
            let settled = settledApprovals()
            // The page is laid over what Chat shows, never swapped in
            // for it (Dylan, 2026-11-20: after Talk, Chat went blank and
            // then everything flashed in, because every reload gave every
            // row a new identity). Rows already shown keep theirs.
            let window = turnId != nil
            var fresh = merged(Self.items(from: turns), around: window)
            // Older pages stayed above the page (he'd scrolled through them).
            let keptOlder = !window && fresh.first?.turnId != turns.first?.id
            // Each value is written only when it changed: every write
            // redraws Chat, and a refresh that finds nothing new should
            // draw nothing (the Talk → Chat stutter, same day).
            // When older pages stayed, so does what's known about paging
            // past them.
            if !keptOlder {
                var paging = older
                paging.reset(hasMore: page.hasMore)
                if paging != older { older = paging }
            }
            if newerOnServer != page.hasNewer { newerOnServer = page.hasNewer }
            lastPending = page.pending
            for (anchor, afterText, item) in settled {
                let at = ApprovalPlace.index(anchor: anchor, afterText: afterText, turnIds: fresh.map(\.turnId), texts: fresh.map(\.text))
                fresh.insert(item, at: at)
            }
            let known = Set(fresh.map(\.id))
            // An approval that's over never comes back as a card, even while
            // the PC still lists it for a moment.
            let waiting = app.settled.waiting(pending)
            let next = fresh + waiting.map(ChatItem.approval).filter { !known.contains($0.id) }
            if next != items { items = next }
            for item in items {
                if case .approval(let approval) = item.kind, item.outcome == nil, let line = app.settled.line(for: approval.id) {
                    showSettled(approval.id, line: line)
                }
            }
            if problem != nil { problem = nil }
            // Loaded means a load worked: a failed first try used to count,
            // which left Chat empty with nothing retrying (Dylan,
            // 2026-11-20, after a phone restart).
            if !loaded { loaded = true }
            if loadFailed { loadFailed = false }
            app.noteReach(nil)
        } catch {
            // A refresh in the background never puts an error in Chat
            // (Dylan, 2026-11-19: "Jarvis answered 502" coming back to the
            // app); the status line shows whether Jarvis can be reached.
            app.noteReach(error)
        }
    }

    /// True once the first load has failed every retry (Chat says so,
    /// with Retry); cleared by the next load that works.
    @Published private(set) var loadFailed = false
    private var ensuring = false

    /// Loads the chat if it never has: at launch, on visiting Chat, on
    /// coming back to the app, and from Retry. Tries again after 1, 2, 4
    /// and 8 seconds (the network can take a moment after a restart),
    /// then says it couldn't, and the next visit or Retry starts over.
    func ensureLoaded(app: AppModel) async {
        guard !loaded, !ensuring else { return }
        ensuring = true
        defer { ensuring = false }
        if loadFailed { loadFailed = false }
        await app.client.warm()
        for wait in ChatScreen.retryWaits {
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            await load(app: app)
            if loaded {
                // Opened fresh after leaving mid-reply: fetch what finished.
                await catchUp(app: app)
                return
            }
        }
        loadFailed = true
    }

    /// History lines laid over the turn lines Chat holds (ChatMerge): rows
    /// already shown keep their identity and photos, new turns are added,
    /// older pages and lines still going out stay. Approvals are put back
    /// by the caller.
    private func merged(_ page: [ChatItem], around window: Bool) -> [ChatItem] {
        let held = items.filter(\.isTurn)
        let plan = ChatMerge.plan(held: held.map(\.mergeLine), fresh: page.map(\.mergeLine), keepOlder: !window) { UUID().uuidString }
        let heldById = Dictionary(held.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let laid = plan.fresh.map { placed -> ChatItem in
            var item = page[placed.index]
            item.id = placed.id
            if let before = heldById[placed.id], !before.photos.isEmpty {
                // The same images, so the row doesn't count as changed.
                item.photos = before.photos
            } else if item.kind == .user, item.photoCount > 0 {
                item.photos = sentPhotos[item.text] ?? PhotoDiskCache.load(text: item.text, count: item.photoCount)
            }
            return item
        }
        return plan.older.map { held[$0] } + laid + plan.tail.map { held[$0] }
    }

    /// What the server last said about a reply still being written.
    private var lastPending: Bool?

    /// The next older page from the server, put above what's held. Only
    /// asked for when the server says there is one.
    func loadOlder(app: AppModel) async {
        guard let first = items.compactMap(\.turnId).first, older.begin() else { return }
        #if DEBUG
        if Self.demoOlderServer {
            demoOlderFetches += 1
            // `-demoOlderSlow`: four seconds, so a test can watch the screen as it lands.
            try? await Task.sleep(for: .milliseconds(ProcessInfo.processInfo.arguments.contains("-demoOlderSlow") ? 4000 : 600))
            let all = DemoChat.items()
            let end = all.firstIndex { $0.turnId == first } ?? 0
            let page = Array(all[max(0, end - HistoryQuery.pageSize)..<end])
            items.insert(contentsOf: page, at: 0)
            older.finish(added: page.count, hasMore: end - page.count > 0)
            return
        }
        #endif
        do {
            let page = try await app.client.history(.before(first, limit: HistoryQuery.pageSize))
            let known = Set(items.compactMap(\.turnId))
            let fresh = Self.items(from: page.turns.filter { $0.id.map { !known.contains($0) } ?? false })
            items.insert(contentsOf: fresh, at: 0)
            older.finish(added: fresh.count, hasMore: page.hasMore)
        } catch {
            older.fail()
            app.noteReach(error)
        }
    }

    /// Back in the app (or opened fresh): if his last message has no answer
    /// yet, or Jarvis says he's still writing, read the history again every
    /// couple of seconds until the reply is there, so a reply finished while
    /// the app was away shows up without a duplicate.
    func catchUp(app: AppModel) async {
        guard !isSending, !catchingUp, loaded else { return }
        catchingUp = true
        defer { catchingUp = false; if working != nil { working = nil } }
        let started = Date()
        while Date().timeIntervalSince(started) < ChatHistory.catchUpSeconds {
            await load(app: app)
            let turns = items.compactMap { item -> ChatTurn? in
                switch item.kind {
                case .user: return ChatTurn(role: "user", text: item.text, at: "", model: nil, id: item.turnId)
                case .jarvis: return ChatTurn(role: "assistant", text: item.text, at: "", model: item.model, id: item.turnId)
                case .approval: return nil
                }
            }
            guard ChatHistory.replyOwed(turns, pending: lastPending), !isSending else { return }
            working = "Catching up"
            try? await Task.sleep(for: .seconds(ChatHistory.catchUpEvery))
        }
    }

    /// Each settled approval with the id of the nearest turn above it (and
    /// the text of the line just before, for lines with no id yet).
    private func settledApprovals() -> [(Int?, String?, ChatItem)] {
        items.enumerated().compactMap { index, item in
            guard case .approval = item.kind, item.outcome != nil else { return nil }
            let anchor = items[..<index].last(where: { $0.turnId != nil })?.turnId
            let before = index > 0 ? items[index - 1].text : nil
            return (anchor, before, item)
        }
    }

    /// Approvals still waiting, oldest first: the cards pinned above the
    /// Ask box.
    var pendingApprovals: [Approval] {
        items.compactMap { item in
            if case .approval(let approval) = item.kind, item.outcome == nil { return approval }
            return nil
        }
    }

    /// Settles any waiting approval whose time has run out, so its card
    /// collapses into a "Timed out" line (Dylan, 2026-11-17).
    func expireOverdue(now: Date = Date()) {
        for approval in pendingApprovals where ApprovalWording.hasExpired(approval.expires, now: now) {
            settle(approval, ok: false, later: false, by: "timeout")
        }
    }

    /// The app that owns this chat, for the settled approvals (set by AppModel).
    weak var app: AppModel?

    /// Shows an approval as settled (`line`) or waiting again (nil). Called
    /// by AppModel whichever screen settled it.
    func showSettled(_ id: String, line: String?) {
        withAnimation(.smooth(duration: 0.35)) {
            update("approval-\(id)") { $0.outcome = line }
        }
    }

    /// Starts a reply to one of the chat's lines; a line without an id yet
    /// (still arriving) can't be quoted.
    func reply(to item: ChatItem) {
        guard let id = item.turnId, item.isTurn else { return }
        Haptics.play(.tab)
        withAnimation(.snappy) {
            replyingTo = ChatQuote(id: id, role: item.kind == .user ? "user" : "jarvis", text: item.text)
        }
    }

    /// Saved turns as chat lines; each reply remembers the question before it.
    static func items(from turns: [ChatTurn]) -> [ChatItem] {
        var out: [ChatItem] = []
        var lastQuestion = ""
        for turn in turns {
            var item: ChatItem
            if turn.isUser {
                lastQuestion = turn.text
                item = .user(turn.text, photoCount: turn.images ?? 0)
            } else {
                // A message he sent unasked isn't an answer to the line above.
                item = .jarvis(turn.text, model: turn.model, finished: true, question: ModelWording.isNotice(turn.model ?? "") ? "" : lastQuestion)
            }
            item.turnId = turn.id
            item.at = ChatTime.parse(turn.at)
            item.writer = turn.writer
            item.kept = turn.kept ?? false
            item.replyTo = turn.replyTo
            out.append(item)
        }
        return out
    }

    /// Sends a message (and any photos) and fills in the reply as it
    /// streams. A refused photo (400) keeps the message for "Try again".
    func send(_ text: String, photos: [PickedPhoto] = [], offerId: String? = nil, app: AppModel) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !photos.isEmpty else { return }
        let previews = photos.map(\.preview)
        if !photos.isEmpty {
            sentPhotos[trimmed] = previews
            PhotoDiskCache.save(previews, text: trimmed)
        }
        var mine = ChatItem.user(trimmed, photos: previews)
        // The message being replied to goes with this send, then the strip clears.
        let quote = replyingTo
        mine.replyTo = quote
        if quote != nil { replyingTo = nil }
        Haptics.play(.send)
        // Sent while a reply is still running: Jarvis steers it or queues
        // this one (its stream says which). Its own reply, if any, is made
        // only when its words start, so a steered message never shows an
        // empty bubble of its own.
        let alongside = isSending
        items.append(mine)
        var replyId: String?
        if !alongside {
            let reply = ChatItem.jarvis("", model: nil, finished: false, question: trimmed)
            items.append(reply)
            replyId = reply.id
        }
        sendsInFlight += 1
        uploading = !photos.isEmpty
        // Leaving the app right after Send must not stop the message going
        // out: iOS gives a little time to finish the request and read the
        // reply; Jarvis keeps going on the PC either way and the app
        // catches up from history when it's back.
        var background = UIBackgroundTaskIdentifier.invalid
        background = UIApplication.shared.beginBackgroundTask(withName: "Jarvis chat") {
            UIApplication.shared.endBackgroundTask(background)
            background = .invalid
        }
        defer { if background != .invalid { UIApplication.shared.endBackgroundTask(background) } }
        problem = nil
        failed = nil

        do {
            for try await event in replyStream(trimmed, offerId: offerId, photos: photos, replyTo: quote?.id, alongside: alongside, app: app) {
                uploading = false
                switch event {
                case .turn(let id):
                    update(mine.id) { $0.turnId = id }
                case .steered:
                    // Into the running reply: his message goes just above
                    // the words still coming (all three kinds: steered,
                    // stopped, an approval's answer); no reply of its own.
                    placeSteered(mine.id)
                case .queued:
                    update(mine.id) { $0.queued = true }
                case .delta, .model, .working, .mealQuestion, .approval:
                    if replyId == nil {
                        // A queued message's reply starts: it moves into
                        // its own turn at the end, its reply under it.
                        update(mine.id) { $0.queued = false }
                        if let index = items.firstIndex(where: { $0.id == mine.id }) {
                            let moved = items.remove(at: index)
                            items.append(moved)
                        }
                        let reply = ChatItem.jarvis("", model: nil, finished: false, question: trimmed)
                        items.append(reply)
                        replyId = reply.id
                    }
                    apply(event, to: replyId ?? "")
                default:
                    apply(event, to: replyId ?? "")
                }
            }
            app.noteReach(nil)
        } catch let error as JarvisError {
            if case .server(let status, _) = error, status == 400 || status == 413, !photos.isEmpty {
                problem = PhotoLimits.refusedWords
                failed = (trimmed, photos)
                items.removeAll { $0.id == mine.id }
            } else {
                sendDropped(error, text: trimmed, photos: photos, mine: mine.id, reply: replyId ?? "", app: app)
            }
            app.noteReach(error)
        } catch {
            sendDropped(error, text: trimmed, photos: photos, mine: mine.id, reply: replyId ?? "", app: app)
            app.noteReach(error)
        }
        // A send that didn't go keeps its quote for the retry.
        if problem != nil || failed != nil, replyingTo == nil { replyingTo = quote }
        uploading = false
        update(mine.id) { $0.queued = false }
        finish(replyId)
        // The new turns' ids come with history; Keep needs them.
        if problem == nil, !Self.fixtureChat { Task { try? await Task.sleep(for: .seconds(1)); if !self.isSending { await self.load(app: app) } } }
    }

    /// A steered message: just above the reply still coming (SendFlow).
    private func placeSteered(_ mine: String) {
        let lines = items.map { SendFlow.Line(id: $0.id, isUser: $0.kind == .user, open: $0.kind == .jarvis && !$0.finished) }
        guard let at = SendFlow.steeredIndex(lines, mine: mine), let from = items.firstIndex(where: { $0.id == mine }) else { return }
        let moved = items.remove(at: from)
        items.insert(moved, at: min(at, items.count))
    }

    /// Jarvis's reply to a send, as it streams in. `-fixtureChat` (debug
    /// builds) plays a canned reply instead, so the chat's send behaviour
    /// can be tested without writing to live Jarvis.
    private func replyStream(_ text: String, offerId: String?, photos: [PickedPhoto], replyTo: Int?, alongside: Bool, app: AppModel) -> AsyncThrowingStream<ChatEvent, Error> {
        #if DEBUG
        // `-fixtureChat`: a send while one is running is steered, or with
        // `-fixtureQueue` queued then answered (nothing reaches Jarvis).
        if Self.fixtureChat, alongside {
            let queue = ProcessInfo.processInfo.arguments.contains("-fixtureQueue")
            return AsyncThrowingStream { continuation in
                Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    continuation.yield(.turn(9_500 + Int.random(in: 0..<499)))
                    if queue {
                        continuation.yield(.queued(after: nil))
                        try? await Task.sleep(for: .seconds(25))
                        continuation.yield(.model("claude"))
                        continuation.yield(.delta("And for the second thing: yes, done."))
                    } else {
                        continuation.yield(.steered(into: nil, as: "steered"))
                    }
                    continuation.yield(.done)
                    continuation.finish()
                }
            }
        }
        if Self.fixtureChat {
            return AsyncThrowingStream { continuation in
                Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    continuation.yield(.turn(9_000 + Int.random(in: 0..<999)))
                    continuation.yield(.model("claude"))
                    try? await Task.sleep(for: .seconds(20))
                    for chunk in ["Sure. ", "Here's what ", "I found: ", "it's sunny tomorrow, ", "so no jacket needed."] {
                        continuation.yield(.delta(chunk))
                        try? await Task.sleep(for: .milliseconds(250))
                    }
                    continuation.yield(.done)
                    continuation.finish()
                }
            }
        }
        #endif
        return app.client.chat(text, offerId: offerId, photos: photos.map { ChatPhoto(jpeg: $0.jpeg) }, replyTo: replyTo)
    }

    /// Debug builds: `-fixtureChat` answers sends with a canned reply.
    static var fixtureChat: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-fixtureChat")
        #else
        return false
        #endif
    }

    /// A send that broke. Nothing back yet: it didn't go, so say so and
    /// offer Try again (never sent again on its own). Jarvis had it (its
    /// turn id came back, or words had started): he carries on and saves it
    /// once, so fetch the rest instead of offering to send it twice.
    private func sendDropped(_ error: Error, text: String, photos: [PickedPhoto], mine: String, reply: String, app: AppModel) {
        // Jarvis has it once he's said its id ("turn") or begun answering.
        let received = items.first { $0.id == mine }?.turnId != nil
        let started = received || !(items.first { $0.id == reply }?.text.isEmpty ?? true)
        if started {
            problem = nil
            Task { await self.catchUp(app: app) }
        } else {
            problem = ErrorWording.sendFailed
            Haptics.play(.failure)
            failed = (text, photos)
            items.removeAll { $0.id == mine }
        }
    }

    /// Answers "is this the meal I logged?" under a reply; his answer comes
    /// back as his next bubble and the buttons retire.
    func answerMeal(_ item: ChatItem, choice: String, app: AppModel) async {
        guard let key = item.mealKey, busy == nil else { return }
        busy = "Telling Jarvis…"
        problem = nil
        failedMeal = nil
        do {
            let message = try await app.client.answerMeal(key: key, choice: choice)
            update(item.id) { $0.mealAnswer = choice }
            items.append(.jarvis(message, model: nil, finished: true, question: item.question))
            app.noteReach(nil)
        } catch {
            problem = error.localizedDescription
            failedMeal = (item.id, choice)
            app.noteReach(error)
        }
        busy = nil
    }

    /// Tries the failed meal answer again.
    func retryMeal(app: AppModel) async {
        guard let failed = failedMeal, let item = items.first(where: { $0.id == failed.itemId }) else { return }
        await answerMeal(item, choice: failed.choice, app: app)
    }

    /// Sends the refused message again.
    func retry(app: AppModel) async {
        guard let failed else { return }
        await send(failed.text, photos: failed.photos, app: app)
    }

    /// One streamed event onto the reply in progress.
    private func apply(_ event: ChatEvent, to replyId: String) {
        switch event {
        case .delta(let words):
            // His first words: a soft nudge, the way a reply arriving is felt.
            // His first words, while Chat is in front: one soft tick, nothing per word.
            if items.first(where: { $0.id == replyId })?.text.isEmpty == true, app?.tab == .chat { Haptics.play(.replyStarts) }
            update(replyId) { $0.text += words }
        case .model(let model):
            update(replyId) { $0.model = model }
        case .working(let label):
            working = label
        case .workingDone:
            working = nil
        case .approval(let approval):
            // The card goes above the reply's later words, like on the page.
            // One that's already over is never shown.
            if app?.settled.isSettled(approval.id) != true, !items.contains(where: { $0.id == "approval-\(approval.id)" }) {
                let at = items.firstIndex(where: { $0.id == replyId }) ?? items.endIndex
                items.insert(.approval(approval), at: at)
                Haptics.play(.approvalArrives)
            }
        case .approvalDone(let id, let ok, let by, let later):
            let summary = knownApproval(id)?.summary ?? ""
            app?.settleApproval(id, line: ApprovalWording.settledLine(ok: ok, later: later, by: by, summary: summary))
        case .error(let message):
            problem = message
            Haptics.play(.failure)
        case .turn(let id):
            // His message's id in history, so catching up later matches it
            // instead of showing it twice (send() sets it on its own message).
            if let mine = items.lastIndex(where: { $0.kind == .user && $0.turnId == nil }) { items[mine].turnId = id }
        case .steered, .queued:
            break
        case .mealQuestion(let key, let choices):
            update(replyId) { $0.mealKey = key; $0.mealChoices = choices }
        case .done:
            break
        }
    }

    /// Marks the reply finished; an empty one is dropped.
    private func finish(_ replyId: String?) {
        sendsInFlight = max(0, sendsInFlight - 1)
        if sendsInFlight == 0 { working = nil }
        if let replyId, let index = items.firstIndex(where: { $0.id == replyId }) {
            if items[index].text.isEmpty {
                items.remove(at: index)
            } else {
                items[index].finished = true
            }
        }
    }

    /// Changes one item in place.
    private func update(_ id: String, _ change: (inout ChatItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[index])
    }

    /// Settles an approval: the pinned card collapses into its one-line
    /// entry in the history, gently.
    private func settle(_ approval: Approval, ok: Bool, later: Bool, by: String) {
        let line = ApprovalWording.settledLine(ok: ok, later: later, by: by, summary: approval.summary)
        if let app {
            app.settleApproval(approval.id, line: line)
        } else {
            showSettled(approval.id, line: line)
        }
    }

    /// The approval card with this id, settled or not.
    private func knownApproval(_ id: String) -> Approval? {
        for item in items {
            if case .approval(let approval) = item.kind, approval.id == id { return approval }
        }
        return nil
    }

    /// Approve or Deny on a card. Shows the answer at once and takes it
    /// back if the PC didn't get it.
    func answer(_ approval: Approval, ok: Bool, app: AppModel) async {
        if let message = await app.answerApproval(id: approval.id, summary: approval.summary, ok: ok) {
            problem = message
        }
    }

    /// Sends "That was wrong" with Dylan's note. Returns whether it went.
    func flagWrong(_ item: ChatItem, note: String, app: AppModel) async -> Bool {
        do {
            try await app.client.flagWrong(question: item.question, answer: item.text, note: note)
            return true
        } catch {
            problem = error.localizedDescription
            return false
        }
    }
}

/// Sent photos' thumbnails on disk (Caches), so a past message still shows
/// them after a relaunch: history only says how many there were.
enum PhotoDiskCache {
    private static var folder: URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let url = caches.appendingPathComponent("chat-photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Keeps a message's thumbnails.
    static func save(_ images: [UIImage], text: String) {
        guard let folder else { return }
        let key = PhotoCacheKey.key(text: text, count: images.count)
        for (i, image) in images.enumerated() {
            try? image.jpegData(compressionQuality: 0.7)?.write(to: folder.appendingPathComponent("\(key)-\(i).jpg"))
        }
    }

    /// A message's thumbnails, or none if they aren't on this device.
    static func load(text: String, count: Int) -> [UIImage] {
        guard let folder else { return [] }
        let key = PhotoCacheKey.key(text: text, count: count)
        let images = (0..<count).compactMap { UIImage(contentsOfFile: folder.appendingPathComponent("\(key)-\($0).jpg").path) }
        return images.count == count ? images : []
    }
}


#if DEBUG
/// A long, mixed chat for scroll checks: short and long replies with
/// markdown, lists and code, model chips, kept ones, photo chips.
enum DemoChat {
    static func items() -> [ChatItem] {
        var out: [ChatItem] = []
        let long = """
        Here's the **plan** for tomorrow, with the bits that matter:

        - Leave by `9:40` for the *10:30* at Varda
        - Rain until noon, so take the jacket
        - Dinner with Aditya has **no time set** yet

        | Item | Calories | Protein |
        |---|---|---|
        | Burrito bowl | 675 | 54 g |
        | Smoothie | 140 | 1 g |

        ```
        swift test --filter Chat
        ```
        I'll check again at 8 and tell you if anything moves.
        """
        // `-demoChatBig`: 2,000 turns, for the lazy-loading check.
        let turns = ProcessInfo.processInfo.arguments.contains("-demoChatBig") ? 1000 : 120
        for i in 0..<turns {
            var me = ChatItem.user(i % 5 == 0 ? "Can you look at tomorrow and tell me what I need to bring?" : "ok \(i)", photoCount: i % 9 == 0 ? 2 : 0)
            me.turnId = i
            // Every three hours back from now, so the demo spans days.
            me.at = Date().addingTimeInterval(-Double(turns - i) * 3 * 3600)
            out.append(me)
            var reply = ChatItem.jarvis(i % 3 == 0 ? long : "Done. **Logged** it: \(i * 7) calories, `\(i)P`. Anything else?", model: ["claude", "ornith", "qwen"][i % 3], finished: true, question: "q")
            reply.turnId = 1000 + i
            reply.at = me.at?.addingTimeInterval(60)
            reply.kept = i % 11 == 0
            out.append(reply)
        }
        // `-mockTalkTurns`: exchanges as if spoken on Talk, added by the
        // debug run below and picked up by the next load.
        for i in 0..<talkTurns {
            var me = ChatItem.user("talk \(i)", photoCount: 0)
            me.turnId = 5000 + i * 2
            out.append(me)
            var reply = ChatItem.jarvis("Done, from Talk (\(i)).", model: "claude", finished: true, question: "talk \(i)")
            reply.turnId = 5001 + i * 2
            out.append(reply)
        }
        return out
    }

    /// Spoken exchanges added by `-mockTalkTurns`.
    nonisolated(unsafe) static var talkTurns = 0
}
#endif
