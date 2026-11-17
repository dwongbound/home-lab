// The chat: history from the PC, a streaming reply, approval cards and
// "That was wrong". Mirrors the web page's chat sheet (JarvisPanel).
import SwiftUI
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
    /// Approvals: how it ended ("Approved", "Denied out loud"), nil while waiting.
    var outcome: String?

    /// A line of Dylan's.
    static func user(_ text: String) -> ChatItem {
        ChatItem(id: UUID().uuidString, kind: .user, text: text, model: nil, finished: true, question: "", outcome: nil)
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
            items = Self.items(from: turns) + pending.map(ChatItem.approval)
            problem = nil
            app.noteReach(nil)
        } catch {
            problem = error.localizedDescription
            app.noteReach(error)
        }
        loaded = true
    }

    /// Saved turns as chat lines; each reply remembers the question before it.
    static func items(from turns: [ChatTurn]) -> [ChatItem] {
        var out: [ChatItem] = []
        var lastQuestion = ""
        for turn in turns {
            if turn.isUser {
                lastQuestion = turn.text
                out.append(.user(turn.text))
            } else {
                out.append(.jarvis(turn.text, model: turn.model, finished: true, question: lastQuestion))
            }
        }
        return out
    }

    /// Sends a message and fills in the reply as it streams.
    func send(_ text: String, offerId: String? = nil, app: AppModel) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSending else { return }
        items.append(.user(trimmed))
        let reply = ChatItem.jarvis("", model: nil, finished: false, question: trimmed)
        items.append(reply)
        isSending = true
        problem = nil

        do {
            for try await event in app.client.chat(trimmed, offerId: offerId) {
                apply(event, to: reply.id)
            }
            app.noteReach(nil)
        } catch {
            problem = error.localizedDescription
            app.noteReach(error)
        }
        finish(reply.id)
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
            settle(id, text: ApprovalWording.outcomeText(ok: ok, later: later, by: by))
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

    /// Writes how an approval ended onto its card.
    private func settle(_ approvalId: String, text: String) {
        update("approval-\(approvalId)") { $0.outcome = text }
    }

    /// Approve or Deny on a card. Shows the answer at once and takes it
    /// back if the PC didn't get it.
    func answer(_ approval: Approval, ok: Bool, app: AppModel) async {
        settle(approval.id, text: ok ? "Approved" : "Denied")
        do {
            try await app.client.answer(approval: approval.id, ok: ok)
            app.noteReach(nil)
        } catch {
            update("approval-\(approval.id)") { $0.outcome = nil }
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
