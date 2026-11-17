// The Talk tab: hands-free voice with Jarvis, like the page's /talk. The
// orb in the middle, what he heard and what he's saying under it, and one
// Talk/Pause button plus Mute. Keeps going with the screen locked.
import ActivityKit
import SwiftUI
import JarvisKit

/// One finished exchange on the call: what Dylan said and what Jarvis said back.
struct TalkTurn: Identifiable {
    let id = UUID()
    /// Which exchange of the call this was (counts up from 0).
    let number: Int
    let heard: String
    let reply: String
    let model: String?
}

@MainActor
final class TalkModel: ObservableObject {
    /// Where the line is, from the screen's side.
    enum Phase: Equatable {
        case off
        case connecting
        case on(TalkState)
    }

    @Published private(set) var phase: Phase = .off {
        didSet { syncActivity() }
    }
    @Published private(set) var muted = false {
        didSet { syncActivity() }
    }
    /// The call in the Dynamic Island, while it's live.
    private var activity: Activity<TalkActivityAttributes>?
    /// What Whisper is hearing right now, or the last thing it heard.
    @Published private(set) var heard = ""
    /// His reply so far.
    @Published private(set) var reply = ""
    @Published private(set) var model: String?
    /// The slow lookup he's doing ("Searching the web."), or nil.
    @Published private(set) var working: String?
    /// Approvals on this call: the exchange each was asked in, and how it
    /// ended as a one-line history entry (nil while it's still waiting).
    @Published private(set) var approvals: [(approval: Approval, outcome: String?, exchange: Int)] = []
    /// The exchange in progress (the one not yet moved into `turns`).
    @Published private(set) var exchange = 0
    @Published private(set) var level: Float = 0
    /// How bright the voice sounds (0..1), for the orb's ripples.
    @Published private(set) var tone: Float = 0
    /// Earlier exchanges on this call, oldest first, drawn as chat bubbles
    /// above the current one (Dylan, 2026-11-17: the left/right chat look).
    @Published private(set) var turns: [TalkTurn] = []
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
            onLevel: { [weak self] level, tone in self?.hear(level: level, tone: tone) },
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
        settle(approval.id, ok: ok, later: false, by: "page")
        do {
            try await app.client.answer(approval: approval.id, ok: ok)
        } catch {
            withAnimation(.smooth(duration: 0.35)) {
                if let index = approvals.firstIndex(where: { $0.approval.id == approval.id }) {
                    approvals[index].outcome = nil
                }
            }
            problem = error.localizedDescription
        }
    }

    /// Keeps the Dynamic Island in step with the call (Dylan, 2026-11-17):
    /// there while the line is live, gone once it's off or paused.
    private func syncActivity() {
        let state: String
        switch phase {
        case .on(.listening): state = "listening"
        case .on(.thinking): state = "thinking"
        case .on(.speaking): state = "speaking"
        default:
            endActivity()
            return
        }
        let content = ActivityContent(state: TalkActivityAttributes.ContentState(state: state, muted: muted), staleDate: nil)
        if let activity {
            Task { await activity.update(content) }
        } else if ActivityAuthorizationInfo().areActivitiesEnabled {
            do {
                activity = try Activity.request(attributes: TalkActivityAttributes(), content: content)
                talkLog("live activity started")
            } catch {
                talkLog("live activity refused: \(error)")
            }
        } else {
            talkLog("live activities are off in Settings › Jarvis")
        }
    }

    /// Takes the call out of the Dynamic Island.
    private func endActivity() {
        guard let activity else { return }
        self.activity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    /// One event from the line onto the screen.
    private func apply(_ event: TalkEvent, app: AppModel) {
        switch event {
        case .state(let state):
            phase = .on(state)
            // Listening starts quiet; dozing (paused by him or by Jarvis on
            // "that's all") drops the voice so the orb settles.
            if state == .listening || state == .dozing { level = 0; tone = 0 }
        case .partial(let words, _), .transcript(let words, _):
            if reply.isEmpty == false && !isJoining(event) {
                // A new question: the last exchange moves up into the transcript.
                archiveTurn()
                heard = ""
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
                approvals.append((approval, nil, exchange))
            }
        case .approvalDone(let id, let ok, let by, let later):
            settle(id, ok: ok, later: later, by: by)
        case .hello:
            break
        }
    }

    /// The latest reading, raw: the orb smooths it per display frame
    /// (OrbView.Glide), which is what keeps it from quivering.
    private func hear(level new: Float, tone newTone: Float) {
        level = new
        if newTone > 0 { tone = newTone }
    }

    /// Moves the finished exchange into the transcript, keeping the last few.
    private func archiveTurn() {
        guard !heard.isEmpty || !reply.isEmpty else { return }
        turns.append(TalkTurn(number: exchange, heard: heard, reply: reply, model: model))
        exchange += 1
        if turns.count > 6 { turns.removeFirst(turns.count - 6) }
    }

    /// Whether words carry on the question he's already answering.
    private func isJoining(_ event: TalkEvent) -> Bool {
        switch event {
        case .partial(_, let joined), .transcript(_, let joined): return joined
        default: return false
        }
    }

    /// Settles an approval: its card collapses into a one-line entry in the
    /// transcript, after the exchange it was asked in.
    private func settle(_ id: String, ok: Bool, later: Bool, by: String) {
        guard let index = approvals.firstIndex(where: { $0.approval.id == id }) else { return }
        let line = ApprovalWording.settledLine(ok: ok, later: later, by: by, summary: approvals[index].approval.summary)
        withAnimation(.smooth(duration: 0.35)) {
            approvals[index].outcome = line
        }
    }

    /// Approvals still waiting: pinned above the buttons.
    var pendingApprovals: [Approval] {
        approvals.filter { $0.outcome == nil }.map(\.approval)
    }

    /// Settled approvals asked during exchange `number`, as their lines.
    func settledLines(in number: Int) -> [(id: String, line: String)] {
        approvals.compactMap { entry in
            guard entry.exchange == number, let line = entry.outcome else { return nil }
            return (entry.approval.id, line)
        }
    }

    /// Collapses any waiting approval whose time has run out into "Timed out".
    func expireOverdue(now: Date = Date()) {
        for approval in pendingApprovals where ApprovalWording.hasExpired(approval.expires, now: now) {
            settle(approval.id, ok: false, later: false, by: "timeout")
        }
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
    /// Whether the newest line is on screen; false once he scrolls up.
    @State private var following = true

    /// Status line, the orb and words in the middle, the buttons at the bottom.
    var body: some View {
        ZStack {
            Theme.sky.ignoresSafeArea()
            VStack(spacing: 0) {
                StatusLine()
                GeometryReader { area in
                    VStack(spacing: 14) {
                        // The orb stays put; it shrinks a little once
                        // there's a conversation to make room for it.
                        OrbView(state: mood, size: orbSize(in: area.size), level: Double(talk.level), tone: Double(talk.tone), work: app.today.snapshot?.jobs?.running ?? DemoWork.jobs, dim: talk.phase == .on(.dozing) || talk.phase == .off ? 0.55 : 1)
                            // Above the words below it, so a work callout isn't covered.
                            .zIndex(1)
                            .padding(.top, hasWords ? 8 : 24)
                            .animation(.smooth(duration: 0.5), value: hasWords)
                        Text(statusWords)
                            .font(.headline)
                            .foregroundStyle(statusColor)
                            .accessibilityAddTraits(.updatesFrequently)
                        transcript
                    }
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                }
                pinnedApprovals
                controls
            }
        }
        // Waiting approvals collapse into "Timed out" once their time is up.
        .task {
            while !Task.isCancelled {
                talk.expireOverdue()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    /// The orb's size: up to 300 pt on a phone (200 once you're talking),
    /// and larger on an iPad, where it can take up to about a third of the
    /// shorter side (420 pt, 280 while talking).
    private func orbSize(in area: CGSize) -> CGFloat {
        let roomy = min(area.width, area.height) > 600
        let cap: CGFloat = roomy ? (hasWords ? 280 : 420) : (hasWords ? 200 : 300)
        return min(area.width - 48, cap)
    }

    /// Anything said yet on this call.
    private var hasWords: Bool {
        !talk.turns.isEmpty || !talk.heard.isEmpty || !talk.reply.isEmpty
    }

    /// The conversation under the orb, following the newest line as it
    /// arrives (Dylan, 2026-11-17) unless he has scrolled up to read; it
    /// picks up again when he scrolls back down or a new turn starts.
    private var transcript: some View {
        ScrollViewReader { scroller in
            ScrollView {
                VStack(spacing: 12) {
                    words
                    if let problem = talk.problem {
                        Text(problem)
                            .font(.footnote)
                            .foregroundStyle(Theme.rose)
                            .multilineTextAlignment(.center)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id("talk-bottom")
                        .onAppear { following = true }
                        .onDisappear { following = false }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: talk.heard) { follow(scroller) }
            .onChange(of: talk.reply) { follow(scroller) }
            .onChange(of: talk.working) { follow(scroller) }
            .onChange(of: talk.approvals.map(\.outcome)) { follow(scroller) }
            .onChange(of: talk.turns.count) {
                // A new turn always brings the view back to the bottom.
                following = true
                follow(scroller)
            }
        }
    }

    /// Glides to the newest line if he's following along.
    private func follow(_ scroller: ScrollViewProxy) {
        guard following else { return }
        withAnimation(.smooth(duration: 0.35)) {
            scroller.scrollTo("talk-bottom", anchor: .bottom)
        }
    }

    /// The call as a chat: Dylan's words on the right, Jarvis's on the
    /// left, earlier exchanges above the current one.
    @ViewBuilder
    private var words: some View {
        VStack(spacing: 12) {
            ForEach(talk.turns) { turn in
                bubbles(heard: turn.heard, reply: turn.reply, model: turn.model)
                    .opacity(0.7)
                settled(in: turn.number)
            }
            bubbles(heard: talk.heard, reply: talk.reply, model: talk.model)
            settled(in: talk.exchange)
        }
    }

    /// The approvals settled during one exchange, as quiet lines.
    private func settled(in number: Int) -> some View {
        ForEach(talk.settledLines(in: number), id: \.id) { entry in
            ApprovalLine(text: entry.line)
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottom)))
        }
    }

    /// Approval cards still waiting, pinned just above the buttons.
    @ViewBuilder
    private var pinnedApprovals: some View {
        let pending = talk.pendingApprovals
        if !pending.isEmpty {
            VStack(spacing: 8) {
                ForEach(pending) { approval in
                    ApprovalCard(approval: approval, outcome: nil) { ok in
                        Task { await talk.answer(approval, ok: ok, app: app) }
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .frame(maxWidth: 560)
            .animation(.smooth(duration: 0.35), value: pending.map(\.id))
        }
    }

    /// One exchange as two bubbles (either may be missing yet).
    @ViewBuilder
    private func bubbles(heard: String, reply: String, model: String?) -> some View {
        if !heard.isEmpty {
            Text(heard)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 20, bottomTrailingRadius: 6, topTrailingRadius: 20).fill(Theme.userBubble))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.leading, 48)
        }
        if !reply.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                if let model, !ModelWording.label(model).isEmpty {
                    let chip = ModelWording.isClaude(model) ? Theme.ember : Theme.glacier
                    Text(ModelWording.label(model))
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .foregroundStyle(chip)
                        .background(Capsule().fill(chip.opacity(0.14)))
                }
                Text(reply)
                    .foregroundStyle(Theme.frost)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 6, bottomTrailingRadius: 20, topTrailingRadius: 20).fill(Theme.glass))
                    .overlay(UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 6, bottomTrailingRadius: 20, topTrailingRadius: 20).strokeBorder(Theme.glassEdge))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 32)
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
        case .on(.thinking): return "Jarvis is thinking…"
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

/// Sample background work for checking the orb's lit dots without a PC:
/// debug builds launched with `-demoWork` only; empty otherwise.
enum DemoWork {
    static var jobs: [RunningTask] {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-demoWork") {
            let started = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-7 * 60))
            return [
                RunningTask(id: "demo-1", label: "Changing my code so reminders repeat", state: "running", startedAt: started),
                RunningTask(id: "demo-2", label: "Looking up tonight's volleyball time", state: "running", startedAt: started),
            ]
        }
        #endif
        return []
    }
}
