// Ask Jarvis on the Apple TV (Dylan, 2026-11-17): press Select on the
// always-on screen, type or hold the remote's mic to dictate, and Jarvis
// answers on screen in big type and out loud. One question at a time.
// tvOS gives apps no access to the Siri Remote's microphone, so the
// question comes through the system keyboard's dictation. Jarvis's own
// voice is only on the Talk line, not for a typed chat, so the answer is
// spoken with the TV's built-in voice for now. Menu, or 30 s of quiet after
// he's finished, goes back to the always-on screen.
import AVFoundation
import SwiftUI
import JarvisKit

@MainActor
final class AskModel: ObservableObject {
    enum Phase { case asking, thinking, answering, done }

    @Published var question = ""
    @Published private(set) var phase: Phase = .asking
    @Published private(set) var reply = ""
    @Published private(set) var working: String?
    @Published private(set) var problem: String?
    /// Approvals Jarvis asked for during this answer, and how each ended.
    @Published private(set) var approvals: [(approval: Approval, outcome: String?)] = []
    private let client = JarvisClient()
    private let voice = AVSpeechSynthesizer()

    /// Sends the question through the chat stream and fills in the reply.
    func send() async {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        phase = .thinking
        reply = ""
        problem = nil
        do {
            for try await event in client.chat(text) {
                switch event {
                case .delta(let words):
                    reply += words
                    phase = .answering
                case .working(let label): working = label
                case .workingDone: working = nil
                case .approval(let approval):
                    if !approvals.contains(where: { $0.approval.id == approval.id }) { approvals.append((approval, nil)) }
                case .approvalDone(let id, let ok, let by, let later):
                    settle(id, ApprovalWording.outcomeText(ok: ok, later: later, by: by))
                case .error(let message): problem = message
                default: break
                }
            }
        } catch {
            problem = error.localizedDescription
        }
        working = nil
        phase = .done
        speak(reply)
    }

    /// Approve or Deny with the remote.
    func answer(_ approval: Approval, ok: Bool) async {
        settle(approval.id, ok ? "Approved" : "Denied")
        do {
            try await client.answer(approval: approval.id, ok: ok)
        } catch {
            settle(approval.id, nil)
            problem = error.localizedDescription
        }
    }

    /// Stops talking (leaving the screen).
    func hush() {
        voice.stopSpeaking(at: .immediate)
    }

    /// Writes how an approval ended (nil puts the buttons back).
    private func settle(_ id: String, _ outcome: String?) {
        guard let index = approvals.firstIndex(where: { $0.approval.id == id }) else { return }
        approvals[index].outcome = outcome
    }

    /// Reads the answer aloud in a British voice, plain text only.
    private func speak(_ text: String) {
        let plain = text.replacingOccurrences(of: #"[*_`#>|]"#, with: "", options: .regularExpression)
        guard !plain.isEmpty else { return }
        let utterance = AVSpeechUtterance(string: plain)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-GB")
        voice.speak(utterance)
    }
}

struct AskJarvisView: View {
    @StateObject private var ask = AskModel()
    @Environment(\.dismiss) private var dismiss
    @FocusState private var typing: Bool

    /// The orb, the question box, and the answer in big type.
    var body: some View {
        ZStack {
            Theme.sky.ignoresSafeArea()
            HStack(alignment: .center, spacing: 70) {
                OrbView(state: orbMood, size: 360, tappable: false)
                VStack(alignment: .leading, spacing: 28) {
                    TextField("Ask Jarvis (hold the mic button to speak)", text: $ask.question)
                        .focused($typing)
                        .onSubmit { Task { await ask.send() } }
                        .disabled(ask.phase == .thinking || ask.phase == .answering)
                    status
                    if !ask.reply.isEmpty {
                        ScrollView {
                            Text(markdown(ask.reply))
                                .font(.title3)
                                .foregroundStyle(Theme.frost)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 520)
                    }
                    ForEach(ask.approvals, id: \.approval.id) { entry in
                        approvalRow(entry.approval, outcome: entry.outcome)
                    }
                    if let problem = ask.problem {
                        Text(problem).font(.callout).foregroundStyle(Theme.rose)
                    }
                }
                .frame(maxWidth: 1000, alignment: .leading)
            }
            .padding(80)
        }
        .fontDesign(.rounded)
        .onAppear { typing = true }
        .onExitCommand { close() }
        // Back to the always-on screen 30 s after he's finished, unless an
        // approval is still waiting.
        .task(id: ask.phase) {
            guard ask.phase == .done else { return }
            try? await Task.sleep(for: .seconds(30))
            if !ask.approvals.contains(where: { $0.outcome == nil }) { close() }
        }
    }

    /// What he's doing right now, in a line.
    @ViewBuilder
    private var status: some View {
        switch ask.phase {
        case .asking:
            Text("Press Select, then hold the mic button on the remote and speak.")
                .font(.callout).foregroundStyle(Theme.frostDim)
        case .thinking:
            Label(ask.working ?? "Jarvis is thinking…", systemImage: "sparkles")
                .font(.callout).foregroundStyle(ask.working == nil ? Theme.frostDim : Theme.ember)
        case .answering, .done:
            EmptyView()
        }
    }

    /// An approval in plain words with Approve and Deny, or how it ended.
    private func approvalRow(_ approval: Approval, outcome: String?) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(ApprovalWording.toolLabel(approval.tool)).font(.headline).foregroundStyle(Theme.ember)
            Text(ApprovalWording.readableSummary(approval.summary)).font(.callout).foregroundStyle(Theme.frost)
            if let outcome {
                Text(outcome).font(.callout.weight(.semibold)).foregroundStyle(outcome.hasPrefix("Approved") ? Theme.moss : Theme.rose)
            } else {
                HStack(spacing: 24) {
                    Button("Deny") { Task { await ask.answer(approval, ok: false) } }
                    Button("Approve") { Task { await ask.answer(approval, ok: true) } }
                }
            }
        }
        .padding(28)
        .glassPanel(tint: Theme.ember)
    }

    /// The orb follows the answer: thinking, working, then speaking.
    private var orbMood: OrbView.Mood {
        switch ask.phase {
        case .thinking: return ask.working == nil ? .thinking : .working
        case .answering: return .speaking
        default: return .listening
        }
    }

    /// Stops the voice and goes back.
    private func close() {
        ask.hush()
        dismiss()
    }

    /// Bold, italics, code and links render; anything else stays plain.
    private func markdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}
