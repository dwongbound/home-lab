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
    /// True while photos are uploading (before the reply starts).
    @Published private(set) var uploading = false
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
    func load(app: AppModel) async {
        let client = app.client
        do {
            let turns = try await client.history()
            let pending = try await client.pendingApprovals()
            // Settled approvals aren't in the PC's history, so they're kept
            // from before, each after the line it followed.
            let settled = settledApprovals()
            var fresh = Self.items(from: turns).map { item in
                var item = item
                if item.kind == .user, item.photoCount > 0, let kept = sentPhotos[item.text] { item.photos = kept }
                return item
            }
            for (afterText, item) in settled {
                let at = afterText.flatMap { text in fresh.lastIndex(where: { $0.text == text }) }.map { $0 + 1 } ?? fresh.endIndex
                fresh.insert(item, at: at)
            }
            let known = Set(fresh.map(\.id))
            items = fresh + pending.map(ChatItem.approval).filter { !known.contains($0.id) }
            problem = nil
            app.noteReach(nil)
        } catch {
            problem = error.localizedDescription
            app.noteReach(error)
        }
        loaded = true
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

    /// Saved turns as chat lines; each reply remembers the question before it.
    static func items(from turns: [ChatTurn]) -> [ChatItem] {
        var out: [ChatItem] = []
        var lastQuestion = ""
        for turn in turns {
            if turn.isUser {
                lastQuestion = turn.text
                out.append(.user(turn.text, photoCount: turn.images ?? 0))
            } else {
                out.append(.jarvis(turn.text, model: turn.model, finished: true, question: lastQuestion))
            }
        }
        return out
    }

    /// Sends a message (and any photos) and fills in the reply as it
    /// streams. A refused photo (400) keeps the message for "Try again".
    func send(_ text: String, photos: [PickedPhoto] = [], offerId: String? = nil, app: AppModel) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !photos.isEmpty, !isSending else { return }
        let previews = photos.map(\.preview)
        if !photos.isEmpty { sentPhotos[trimmed] = previews }
        let mine = ChatItem.user(trimmed, photos: previews)
        items.append(mine)
        let reply = ChatItem.jarvis("", model: nil, finished: false, question: trimmed)
        items.append(reply)
        isSending = true
        uploading = !photos.isEmpty
        problem = nil
        failed = nil

        do {
            for try await event in app.client.chat(trimmed, offerId: offerId, photos: photos.map { ChatPhoto(jpeg: $0.jpeg) }) {
                uploading = false
                apply(event, to: reply.id)
            }
            app.noteReach(nil)
        } catch let error as JarvisError {
            if case .server(let status, _) = error, status == 400, !photos.isEmpty {
                problem = PhotoLimits.refusedWords
                failed = (trimmed, photos)
                items.removeAll { $0.id == mine.id }
            } else {
                problem = error.localizedDescription
            }
            app.noteReach(error)
        } catch {
            problem = error.localizedDescription
            app.noteReach(error)
        }
        uploading = false
        finish(reply.id)
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
            if !items.contains(where: { $0.id == "approval-\(approval.id)" }) {
                let at = items.firstIndex(where: { $0.id == replyId }) ?? items.endIndex
                items.insert(.approval(approval), at: at)
            }
        case .approvalDone(let id, let ok, let by, let later):
            if let approval = pendingApprovals.first(where: { $0.id == id }) {
                settle(approval, ok: ok, later: later, by: by)
            }
        case .error(let message):
            problem = message
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
        withAnimation(.smooth(duration: 0.35)) {
            update("approval-\(approval.id)") { $0.outcome = line }
        }
    }

    /// Approve or Deny on a card. Shows the answer at once and takes it
    /// back if the PC didn't get it.
    func answer(_ approval: Approval, ok: Bool, app: AppModel) async {
        settle(approval, ok: ok, later: false, by: "page")
        do {
            try await app.client.answer(approval: approval.id, ok: ok)
            app.noteReach(nil)
        } catch {
            withAnimation(.smooth(duration: 0.35)) {
                update("approval-\(approval.id)") { $0.outcome = nil }
            }
            problem = error.localizedDescription
            app.noteReach(error)
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
