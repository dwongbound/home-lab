// Jarvis on Apple Watch: ask him something by voice, see his answer, and
// tap Approve or Deny when he needs an OK. Tailscale doesn't run on the
// Watch, so every request goes through the iPhone app (WatchBridge), which
// must be nearby; the phone app doesn't need to be open.
import SwiftUI
import WatchConnectivity
import WatchKit
import JarvisKit

@main
struct JarvisWatchApp: App {
    @StateObject private var model = WatchModel()

    /// One screen: the orb, Ask, the last answer, and anything waiting on an OK.
    var body: some Scene {
        WindowGroup {
            WatchHome(model: model)
                .tint(Theme.glacier)
        }
    }
}

@MainActor
final class WatchModel: NSObject, ObservableObject, WCSessionDelegate {
    enum Phase: Equatable {
        case idle
        case asking
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var question = ""
    @Published private(set) var answer = ""
    @Published private(set) var model: String?
    @Published private(set) var approvals: [Approval] = []
    @Published var problem: String?

    /// Starts the session with the phone.
    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    /// Sends what Dylan dictated to Jarvis (through the phone) and shows the answer.
    func ask(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, phase == .idle else { return }
        question = trimmed
        answer = ""
        model = nil
        problem = nil
        phase = .asking
        let reply = await send(.ask(trimmed))
        phase = .idle
        switch reply {
        case .answer(let text, let who):
            answer = text
            model = who
            WKInterfaceDevice.current().play(.success)
        case .problem(let words):
            problem = words
            WKInterfaceDevice.current().play(.failure)
        default:
            break
        }
        await refreshApprovals()
    }

    /// Fetches what's waiting on an OK.
    func refreshApprovals() async {
        if case .approvals(let list) = await send(.approvals) {
            approvals = list
        }
    }

    /// Approve or Deny on a card; the card goes once the phone confirms.
    func answer(_ approval: Approval, ok: Bool) async {
        switch await send(.answer(id: approval.id, ok: ok)) {
        case .done:
            approvals.removeAll { $0.id == approval.id }
            WKInterfaceDevice.current().play(ok ? .success : .click)
        case .problem(let words):
            problem = words
        default:
            break
        }
    }

    /// One request to the phone. Words the usual failures for a small screen.
    private func send(_ request: WatchRequest) async -> WatchReply {
        let session = WCSession.default
        guard session.activationState == .activated else {
            return .problem("Still connecting to your iPhone. Try again in a moment.")
        }
        guard session.isReachable else {
            return .problem("Can’t reach your iPhone. Jarvis needs it nearby.")
        }
        return await withCheckedContinuation { continuation in
            session.sendMessage(request.message, replyHandler: { message in
                continuation.resume(returning: WatchReply(message: message))
            }, errorHandler: { error in
                continuation.resume(returning: .problem(error.localizedDescription))
            })
        }
    }

    /// Once connected, look for approvals.
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in await self.refreshApprovals() }
    }
}

struct WatchHome: View {
    @ObservedObject var model: WatchModel

    /// Scrolls: orb and Ask on top, then the answer, then approvals.
    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                OrbView(state: model.phase == .asking ? .thinking : .listening, size: 70)
                    .opacity(model.phase == .asking ? 1 : 0.8)
                if model.phase == .asking {
                    Text("Jarvis is thinking…").font(.footnote).foregroundStyle(Theme.frostDim)
                } else {
                    // Tapping offers dictation first, so it's one tap and talk.
                    TextFieldLink(prompt: Text("Ask Jarvis")) {
                        Label("Ask", systemImage: "mic.fill")
                            .frame(maxWidth: .infinity)
                    } onSubmit: { text in
                        Task { await model.ask(text) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.glacier)
                    .foregroundStyle(Theme.basalt)
                }
                if let problem = model.problem {
                    Text(problem).font(.footnote).foregroundStyle(Theme.rose).multilineTextAlignment(.center)
                }
                if !model.question.isEmpty {
                    Text(model.question).font(.footnote).foregroundStyle(Theme.frostDim).frame(maxWidth: .infinity, alignment: .leading)
                }
                if !model.answer.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        if let who = model.model {
                            Text(ModelWording.label(who))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(ModelWording.isClaude(who) ? Theme.ember : Theme.glacier)
                        }
                        Text(model.answer)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(model.approvals) { approval in
                    approvalCard(approval)
                }
            }
        }
        .task { await model.refreshApprovals() }
    }

    /// "Needs your OK", what he wants, Deny and Approve.
    private func approvalCard(_ approval: Approval) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Needs your OK").font(.caption2.weight(.semibold)).foregroundStyle(Theme.ember)
            Text(ApprovalWording.toolLabel(approval.tool)).font(.headline)
            Text(ApprovalWording.readableSummary(approval.summary)).font(.footnote).foregroundStyle(Theme.frostDim)
            HStack {
                Button("Deny") { Task { await model.answer(approval, ok: false) } }
                Button("Approve") { Task { await model.answer(approval, ok: true) } }
                    .tint(Theme.ember)
            }
        }
        .padding(10)
        .glassPanel(tint: Theme.ember)
    }
}
