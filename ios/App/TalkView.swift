// The Talk tab: hands-free voice with Jarvis, like the page's /talk. The
// orb in the middle, what he heard and what he's saying under it, and one
// Talk/Pause button plus Mute. Keeps going with the screen locked.
import SwiftUI
import JarvisKit

@MainActor
final class TalkModel: ObservableObject {
    /// Where the line is, from the screen's side.
    enum Phase: Equatable {
        case off
        case connecting
        case on(TalkState)
    }

    @Published private(set) var phase: Phase = .off
    @Published private(set) var muted = false
    /// What Whisper is hearing right now, or the last thing it heard.
    @Published private(set) var heard = ""
    /// His reply so far.
    @Published private(set) var reply = ""
    @Published private(set) var model: String?
    /// The slow lookup he's doing ("Searching the web."), or nil.
    @Published private(set) var working: String?
    @Published private(set) var approvals: [(approval: Approval, outcome: String?)] = []
    @Published private(set) var level: Float = 0
    @Published var problem: String?
    /// True once Talk has been started from this tab, so it only auto-starts once.
    private(set) var started = false
    private var line: TalkLine?

    /// Opens the line (Talk). Throws nothing: problems land in `problem`.
    func start(app: AppModel) async {
        guard phase == .off else { return }
        started = true
        problem = nil
        phase = .connecting
        let handlers = TalkHandlers(
            onEvent: { [weak self] event in self?.apply(event, app: app) },
            onLevel: { [weak self] level in self?.level = level },
            onClosed: { [weak self] message in self?.closed(message) }
        )
        let line = TalkLine(request: app.client.talkRequest, handlers: handlers)
        do {
            try await line.open()
            self.line = line
            if case .connecting = phase { phase = .on(.listening) }
            line.setMuted(muted)
            app.noteReach(nil)
        } catch {
            phase = .off
            problem = error.localizedDescription
        }
    }

    /// Pause: dozes when this Jarvis can (he wakes on "Hey Jarvis"), else hangs up.
    func pause() {
        guard let line else { return }
        if line.canDoze {
            line.doze()
            phase = .on(.dozing)
            level = 0
        } else {
            hangUp()
        }
    }

    /// Talk after a pause.
    func wake() {
        line?.wake()
        phase = .on(.listening)
    }

    /// Ends the call.
    func hangUp() {
        line?.close()
        line = nil
        phase = .off
        level = 0
        working = nil
    }

    /// Mic off or on; the line stays open either way.
    func toggleMute() {
        muted.toggle()
        line?.setMuted(muted)
        if muted { level = 0 }
    }

    /// Approve or Deny on a card shown during Talk.
    func answer(_ approval: Approval, ok: Bool, app: AppModel) async {
        settle(approval.id, ok ? "Approved" : "Denied")
        do {
            try await app.client.answer(approval: approval.id, ok: ok)
        } catch {
            settle(approval.id, nil)
            problem = error.localizedDescription
        }
    }

    /// One event from the line onto the screen.
    private func apply(_ event: TalkEvent, app: AppModel) {
        switch event {
        case .state(let state):
            phase = .on(state)
            if state == .listening { level = 0 }
        case .partial(let words, _), .transcript(let words, _):
            if reply.isEmpty == false && !isJoining(event) {
                // A new question: clear the last answer.
                reply = ""
                model = nil
            }
            heard = words
        case .reply(let words):
            reply += words
        case .model(let name):
            model = name
        case .working(let label):
            working = label
        case .workingDone:
            working = nil
        case .done:
            working = nil
            // Spoken turns land in the web chat too, so the Chat tab catches up.
            Task { await app.chat.load(app: app) }
        case .stop:
            break
        case .approval(let approval):
            if !approvals.contains(where: { $0.approval.id == approval.id }) {
                approvals.append((approval, nil))
            }
        case .approvalDone(let id, let ok, let by, let later):
            settle(id, ApprovalWording.outcomeText(ok: ok, later: later, by: by))
        case .hello:
            break
        }
    }

    /// Whether words carry on the question he's already answering.
    private func isJoining(_ event: TalkEvent) -> Bool {
        switch event {
        case .partial(_, let joined), .transcript(_, let joined): return joined
        default: return false
        }
    }

    /// Writes how an approval ended onto its card (nil puts the buttons back).
    private func settle(_ id: String, _ outcome: String?) {
        guard let index = approvals.firstIndex(where: { $0.approval.id == id }) else { return }
        approvals[index].outcome = outcome
    }

    /// The line dropped by itself.
    private func closed(_ message: String) {
        line = nil
        phase = .off
        level = 0
        working = nil
        problem = message
    }
}

struct TalkView: View {
    @EnvironmentObject private var app: AppModel
    @ObservedObject var talk: TalkModel

    /// Status line, the orb and words in the middle, the buttons at the bottom.
    var body: some View {
        ZStack {
            Theme.sky.ignoresSafeArea()
            VStack(spacing: 0) {
                StatusLine()
                GeometryReader { area in
                    ScrollView {
                        VStack(spacing: 18) {
                            OrbView(state: mood, size: min(area.size.width - 48, 300), level: Double(talk.level))
                                .opacity(talk.phase == .on(.dozing) || talk.phase == .off ? 0.55 : 1)
                                .padding(.top, 24)
                            Text(statusWords)
                                .font(.headline)
                                .foregroundStyle(statusColor)
                                .accessibilityAddTraits(.updatesFrequently)
                            words
                            ForEach(talk.approvals, id: \.approval.id) { entry in
                                ApprovalCard(approval: entry.approval, outcome: entry.outcome) { ok in
                                    Task { await talk.answer(entry.approval, ok: ok, app: app) }
                                }
                            }
                            if let problem = talk.problem {
                                Text(problem)
                                    .font(.footnote)
                                    .foregroundStyle(Theme.rose)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 16)
                        .frame(maxWidth: 560)
                        .frame(maxWidth: .infinity)
                    }
                }
                controls
            }
        }
    }

    /// What he heard (dim) and what he's saying back, with his chip.
    @ViewBuilder
    private var words: some View {
        if !talk.heard.isEmpty {
            Text(talk.heard)
                .font(.body)
                .foregroundStyle(Theme.frostDim)
                .multilineTextAlignment(.center)
        }
        if !talk.reply.isEmpty {
            VStack(spacing: 6) {
                if let model = talk.model {
                    Text(ModelWording.label(model))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ModelWording.isClaude(model) ? Theme.ember : Theme.glacier)
                }
                Text(talk.reply)
                    .font(.title3)
                    .foregroundStyle(Theme.frost)
                    .multilineTextAlignment(.center)
            }
        }
    }

    /// Talk/Pause, plus Mute while the line is open.
    private var controls: some View {
        HStack(spacing: 12) {
            if isOpen {
                Button { talk.toggleMute() } label: {
                    Label(talk.muted ? "Unmute" : "Mute", systemImage: talk.muted ? "mic.slash.fill" : "mic.fill")
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.bordered)
                .tint(talk.muted ? Theme.rose : Theme.frost)
            }
            Button { mainAction() } label: {
                HStack(spacing: 8) {
                    if talk.phase == .connecting {
                        ProgressView().tint(Theme.basalt)
                    }
                    Text(mainLabel)
                }
                .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.glacier)
            .foregroundStyle(Theme.basalt)
            .disabled(talk.phase == .connecting)
        }
        .font(.body.weight(.semibold))
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .frame(maxWidth: 560)
    }

    /// True while the line is up (listening, thinking, speaking or dozing).
    private var isOpen: Bool {
        if case .on = talk.phase { return true }
        return false
    }

    /// "Talk" when off or dozing, "Pause" while he's on.
    private var mainLabel: String {
        switch talk.phase {
        case .off: return "Talk"
        case .connecting: return "Calling Jarvis…"
        case .on(.dozing): return "Talk"
        case .on: return "Pause"
        }
    }

    /// What the big button does now.
    private func mainAction() {
        switch talk.phase {
        case .off: Task { await talk.start(app: app) }
        case .connecting: break
        case .on(.dozing): talk.wake()
        case .on: talk.pause()
        }
    }

    /// The orb's mood: amber while he's on a slow lookup.
    private var mood: OrbView.Mood {
        if talk.working != nil { return .working }
        switch talk.phase {
        case .on(.thinking): return .thinking
        case .on(.speaking): return .speaking
        default: return .listening
        }
    }

    /// The line under the orb.
    private var statusWords: String {
        if let working = talk.working, !working.isEmpty { return working }
        switch talk.phase {
        case .off: return "Tap Talk to start"
        case .connecting: return "Calling Jarvis…"
        case .on(.listening): return talk.muted ? "Muted" : "Listening"
        case .on(.thinking): return "Thinking…"
        case .on(.speaking): return "Speaking"
        case .on(.dozing): return "Paused. Say “Hey Jarvis” or tap Talk."
        }
    }

    /// Amber while working, rose while muted, quiet otherwise.
    private var statusColor: Color {
        if talk.working != nil { return Theme.ember }
        if talk.muted && isOpen { return Theme.rose }
        return Theme.frostDim
    }
}
