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

    let id: String
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

    /// A line of Dylan's.
    static func user(_ text: String, photos: [UIImage] = [], photoCount: Int? = nil) -> ChatItem {
        ChatItem(id: UUID().uuidString, kind: .user, text: text, model: nil, finished: true, question: "", outcome: nil, photos: photos, photoCount: photoCount ?? photos.count)
    }

    /// A reply of Jarvis's, empty until words arrive.
    static func jarvis(_ text: String, model: String?, finished: Bool, question: String) -> ChatItem {
        ChatItem(id: UUID().uuidString, kind: .jarvis, text: text, model: model, finished: finished, question: question, outcome: nil)
    }

    /// An approval card.
    static func approval(_ approval: Approval) -> ChatItem {
        ChatItem(id: "approval-\(approval.id)", kind: .approval(approval), text: "", model: nil, finished: true, question: "", outcome: nil)
    }
}

@MainActor
final class ChatModel: ObservableObject {
    @Published private(set) var items: [ChatItem] = []
    /// True from Send until the reply ends.
    @Published private(set) var isSending = false
    /// The slow lookup Jarvis is doing ("Searching the web."), or nil.
    @Published private(set) var working: String?
    /// The last problem, worded for Dylan, or nil.
    @Published var problem: String?
    /// True once history has loaded at least once.
    @Published private(set) var loaded = false
    /// Older turns exist on the server than the ones held (a paging server
    /// says so; today's never does).
    @Published private(set) var olderOnServer = false
    /// An older page is on its way.
    @Published private(set) var loadingOlder = false
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
            items = DemoChat.items()
            loaded = true
            return
        }
        #endif
        let client = app.client
        do {
            // The newest page, or a window round a turn a notice opened.
            let page = try await client.history(turnId.map { .around($0, limit: HistoryQuery.pageSize) } ?? .newest(limit: HistoryQuery.pageSize))
            let turns = page.turns
            olderOnServer = page.hasMore
            lastPending = page.pending
            let pending = try await client.pendingApprovals()
            // Settled approvals aren't in the PC's history, so they're kept
            // from before, each after the line it followed.
            let settled = settledApprovals()
            var fresh = Self.items(from: turns).map { item in
                var item = item
                if item.kind == .user, item.photoCount > 0 {
                    item.photos = sentPhotos[item.text] ?? PhotoDiskCache.load(text: item.text, count: item.photoCount)
                }
                return item
            }
            for (afterText, item) in settled {
                let at = afterText.flatMap { text in fresh.lastIndex(where: { $0.text == text }) }.map { $0 + 1 } ?? fresh.endIndex
                fresh.insert(item, at: at)
            }
            let known = Set(fresh.map(\.id))
            // An approval that's over never comes back as a card, even while
            // the PC still lists it for a moment.
            let waiting = app.settled.waiting(pending)
            items = fresh + waiting.map(ChatItem.approval).filter { !known.contains($0.id) }
            for item in items {
                if case .approval(let approval) = item.kind, item.outcome == nil, let line = app.settled.line(for: approval.id) {
                    showSettled(approval.id, line: line)
                }
            }
            problem = nil
            app.noteReach(nil)
        } catch {
            // A refresh in the background never puts an error in Chat
            // (Dylan, 2026-11-19: "Jarvis answered 502" coming back to the
            // app); the status line shows whether Jarvis can be reached.
            app.noteReach(error)
        }
        loaded = true
    }

    /// What the server last said about a reply still being written.
    private var lastPending: Bool?

    /// The next older page from the server, put above what's held. Only
    /// asked for when the server says there is one.
    func loadOlder(app: AppModel) async {
        guard olderOnServer, !loadingOlder, let first = items.compactMap(\.turnId).first else { return }
        loadingOlder = true
        defer { loadingOlder = false }
        do {
            let page = try await app.client.history(.before(first, limit: HistoryQuery.pageSize))
            let known = Set(items.compactMap(\.turnId))
            let older = Self.items(from: page.turns.filter { $0.id.map { !known.contains($0) } ?? true })
            items.insert(contentsOf: older, at: 0)
            olderOnServer = page.hasMore && !older.isEmpty
        } catch {
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
        defer { catchingUp = false; working = nil }
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

    /// Each settled approval with the text of the line before it.
    private func settledApprovals() -> [(String?, ChatItem)] {
        items.enumerated().compactMap { index, item in
            guard case .approval = item.kind, item.outcome != nil else { return nil }
            let before = index > 0 ? items[index - 1].text : nil
            return (before, item)
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
            item.writer = turn.writer
            item.kept = turn.kept ?? false
            out.append(item)
        }
        return out
    }

    /// Sends a message (and any photos) and fills in the reply as it
    /// streams. A refused photo (400) keeps the message for "Try again".
    func send(_ text: String, photos: [PickedPhoto] = [], offerId: String? = nil, app: AppModel) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !photos.isEmpty, !isSending else { return }
        let previews = photos.map(\.preview)
        if !photos.isEmpty {
            sentPhotos[trimmed] = previews
            PhotoDiskCache.save(previews, text: trimmed)
        }
        let mine = ChatItem.user(trimmed, photos: previews)
        items.append(mine)
        let reply = ChatItem.jarvis("", model: nil, finished: false, question: trimmed)
        items.append(reply)
        isSending = true
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
            for try await event in app.client.chat(trimmed, offerId: offerId, photos: photos.map { ChatPhoto(jpeg: $0.jpeg) }) {
                uploading = false
                apply(event, to: reply.id)
            }
            app.noteReach(nil)
        } catch let error as JarvisError {
            if case .server(let status, _) = error, status == 400 || status == 413, !photos.isEmpty {
                problem = PhotoLimits.refusedWords
                failed = (trimmed, photos)
                items.removeAll { $0.id == mine.id }
            } else {
                sendDropped(error, text: trimmed, photos: photos, mine: mine.id, reply: reply.id, app: app)
            }
            app.noteReach(error)
        } catch {
            sendDropped(error, text: trimmed, photos: photos, mine: mine.id, reply: reply.id, app: app)
            app.noteReach(error)
        }
        uploading = false
        finish(reply.id)
    }

    /// A send that broke. Nothing back yet: it didn't go, so say so and
    /// offer Try again (never sent again on its own). Words had started
    /// coming: Jarvis has it and carries on, so fetch the rest instead.
    private func sendDropped(_ error: Error, text: String, photos: [PickedPhoto], mine: String, reply: String, app: AppModel) {
        let started = !(items.first { $0.id == reply }?.text.isEmpty ?? true)
        if started {
            problem = nil
            Task { await self.catchUp(app: app) }
        } else {
            problem = ErrorWording.sendFailed
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
            }
        case .approvalDone(let id, let ok, let by, let later):
            let summary = knownApproval(id)?.summary ?? ""
            app?.settleApproval(id, line: ApprovalWording.settledLine(ok: ok, later: later, by: by, summary: summary))
        case .error(let message):
            problem = message
        case .mealQuestion(let key, let choices):
            update(replyId) { $0.mealKey = key; $0.mealChoices = choices }
        case .done:
            break
        }
    }

    /// Marks the reply finished; an empty one is dropped.
    private func finish(_ replyId: String) {
        isSending = false
        working = nil
        if let index = items.firstIndex(where: { $0.id == replyId }) {
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
            out.append(me)
            var reply = ChatItem.jarvis(i % 3 == 0 ? long : "Done. **Logged** it: \(i * 7) calories, `\(i)P`. Anything else?", model: ["claude", "ornith", "qwen"][i % 3], finished: true, question: "q")
            reply.turnId = 1000 + i
            reply.kept = i % 11 == 0
            out.append(reply)
        }
        return out
    }
}
#endif
