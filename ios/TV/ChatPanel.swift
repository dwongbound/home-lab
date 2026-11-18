// The Apple TV's chat (Dylan, 2026-11-18: "it should just be a continuous
// conversation, where I can use dictation to 'text it' and it would
// respond… maybe during dictation the right side of the screen turns into
// the chat"). Ask Jarvis turns the right side of the always-on screen into
// the conversation; the orb, clock and weather stay on the left. Replies
// stream in as bubbles and are read aloud (the speaker button mutes them).
// After each reply the text field takes focus again, so the next turn is:
// press Select, hold the mic button and speak, then Done. Menu, or a minute
// of quiet, slides the chat away; reopening carries on the conversation.
// The turn-by-turn rules are TVChat in JarvisKit.
import AVFoundation
import SwiftUI
import JarvisKit

@MainActor
final class TVChatModel: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var chat = TVChat()
    @Published var draft = "" { didSet { lastActivity = Date() } }
    /// True while a reply is being read aloud.
    @Published private(set) var speaking = false
    /// A stand-in voice level for the orb: a lift on every word read.
    @Published private(set) var level: Double = 0
    /// Counts finished replies, so the view can put focus back on the field.
    @Published private(set) var replies = 0
    /// Read replies aloud (the speaker button).
    @Published var speakReplies = UserDefaults.standard.object(forKey: "tv.speakReplies") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(speakReplies, forKey: "tv.speakReplies")
            if !speakReplies { voice.stopSpeaking(at: .immediate) }
        }
    }
    private(set) var lastActivity = Date()
    private let client = JarvisClient()
    private let voice = AVSpeechSynthesizer()
    private var seeded = false

    override init() {
        super.init()
        voice.delegate = self
    }

    /// The chat opened: pick up the last few turns of the conversation.
    func opened() async {
        lastActivity = Date()
        guard !seeded else { return }
        seeded = true
        #if DEBUG
        // Screenshot check: `-demoChat` fills in a sample conversation.
        if ProcessInfo.processInfo.arguments.contains("-demoChat") {
            chat.seed([
                ChatTurn(role: "user", text: "What's the weather like tonight?", at: "", model: nil),
                ChatTurn(role: "assistant", text: "Clear and cooling off: **58°F** by 9 PM, down to 52°F overnight. No rain.", at: "", model: nil),
                ChatTurn(role: "user", text: "Remind me to bring a jacket to volleyball", at: "", model: nil),
                ChatTurn(role: "assistant", text: "Done. I'll remind you at 5:30, before you leave for the Y.", at: "", model: nil),
            ])
            return
        }
        #endif
        if let history = try? await client.history() { chat.seed(history) }
    }

    /// Sends what's in the field and streams the reply in.
    func send() async {
        guard let text = chat.send(draft) else { return }
        draft = ""
        hush()
        do {
            for try await event in client.chat(text) {
                chat.apply(event)
                lastActivity = Date()
            }
            chat.finish()
        } catch {
            chat.finish(error: error.localizedDescription)
        }
        lastActivity = Date()
        replies += 1
        if speakReplies, let reply = chat.lastReply { speak(reply) }
    }

    /// Approve or Deny with the remote.
    func answer(_ approval: Approval, ok: Bool) async {
        chat.settle(approval.id, ok ? "Approved" : "Denied")
        lastActivity = Date()
        do {
            try await client.answer(approval: approval.id, ok: ok)
        } catch {
            chat.settle(approval.id, nil)
        }
    }

    /// Stops reading aloud.
    func hush() {
        voice.stopSpeaking(at: .immediate)
    }

    /// Reads a reply in a British voice, markup stripped.
    private func speak(_ text: String) {
        let plain = text.replacingOccurrences(of: #"[*_`#>|]"#, with: "", options: .regularExpression)
        guard !plain.isEmpty else { return }
        let utterance = AVSpeechUtterance(string: plain)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-GB")
        voice.speak(utterance)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in self.speaking = true }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.speaking = false; self.level = 0; self.lastActivity = Date() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.speaking = false; self.level = 0 }
    }

    /// Each word lifts the orb, longer words a little more, then it falls.
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        let lift = min(1, 0.45 + Double(characterRange.length) * 0.06)
        Task { @MainActor in
            self.level = lift
            self.lastActivity = Date()
            try? await Task.sleep(for: .milliseconds(180))
            self.level = lift * 0.35
        }
    }

    /// The orb's mood for the chat: thinking, working, speaking, else nil.
    var orbMood: OrbView.Mood? {
        if speaking { return .speaking }
        switch chat.phase {
        case .thinking: return chat.working == nil ? .thinking : .working
        case .answering: return .speaking
        case .idle: return nil
        }
    }
}

/// The chat on the right side: the conversation as bubbles, what Jarvis is
/// doing, and the field at the bottom.
struct ChatPanel: View {
    @ObservedObject var model: TVChatModel
    let palette: LampPalette
    var field: FocusState<Bool>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Label("Talking with Jarvis", systemImage: "bubble.left.and.bubble.right.fill")
                    .font(.callout.weight(.bold))
                    .foregroundStyle(palette.inkDim.color)
                    .labelStyle(TintedIconLabel(icon: palette.accent.color))
                Spacer()
                Button {
                    model.speakReplies.toggle()
                } label: {
                    Image(systemName: model.speakReplies ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .font(.callout)
                        .foregroundStyle(palette.ink.color)
                }
                .buttonStyle(SoftFocusButtonStyle(palette: palette))
                .accessibilityLabel(model.speakReplies ? "Replies read aloud" : "Replies muted")
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(model.chat.lines) { line in
                            bubble(line).id(line.id)
                                .transition(.opacity.combined(with: .offset(y: 16)))
                        }
                        status.id("status")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .animation(.smooth(duration: 0.4), value: model.chat.lines.count)
                }
                .scrollIndicators(.hidden)
                .onChange(of: model.chat.lines) { _, _ in
                    withAnimation(.smooth(duration: 0.4)) { proxy.scrollTo("status", anchor: .bottom) }
                }
                .onAppear { proxy.scrollTo("status", anchor: .bottom) }
            }
            .frame(height: 540)
            TextField("Ask Jarvis: press, then hold the mic button to speak", text: $model.draft)
                .focused(field)
                .onSubmit { Task { await model.send() } }
                .disabled(model.chat.phase != .idle)
        }
        .padding(34)
        .background(RoundedRectangle(cornerRadius: 34, style: .continuous).fill(palette.panel.color))
        .overlay(RoundedRectangle(cornerRadius: 34, style: .continuous).strokeBorder(palette.accent.color, lineWidth: 3))
    }

    /// Dylan's lines on the right, Jarvis's on the left; approvals with
    /// focusable Approve and Deny.
    @ViewBuilder
    private func bubble(_ line: TVChatLine) -> some View {
        if let approval = line.approval {
            VStack(alignment: .leading, spacing: 12) {
                Label(ApprovalWording.toolLabel(approval.tool), systemImage: "hand.raised.fill")
                    .font(.headline)
                    .foregroundStyle(palette.warm.color)
                Text(ApprovalWording.readableSummary(approval.summary))
                    .font(.callout)
                    .foregroundStyle(palette.ink.color)
                if let outcome = line.outcome {
                    Text(outcome).font(.callout.weight(.semibold)).foregroundStyle(outcome.hasPrefix("Approved") ? palette.accent.color : palette.alert.color)
                } else {
                    HStack(spacing: 24) {
                        Button("Deny") { Task { await model.answer(approval, ok: false) } }
                            .buttonStyle(SoftFocusButtonStyle(palette: palette))
                        Button("Approve") { Task { await model.answer(approval, ok: true) } }
                            .buttonStyle(SoftFocusButtonStyle(palette: palette))
                    }
                }
            }
            .padding(22)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(palette.warm.color, lineWidth: 2))
        } else {
            let mine = line.who == .me
            HStack {
                if mine { Spacer(minLength: 120) }
                Text(markdown(line.text))
                    .font(.callout)
                    .foregroundStyle(palette.ink.color)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(mine ? palette.accent.color.opacity(palette.darkInk ? 0.12 : 0.05) : palette.skyBottom.color.opacity(palette.darkInk ? 0.6 : 0.9))
                    )
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(mine ? palette.accent.color.opacity(0.5) : palette.panelEdge.color.opacity(0.5), lineWidth: 1))
                if !mine { Spacer(minLength: 120) }
            }
        }
    }

    /// What Jarvis is doing right now, or a problem.
    @ViewBuilder
    private var status: some View {
        if let problem = model.chat.problem {
            Text(problem).font(.callout).foregroundStyle(palette.alert.color)
        } else if model.chat.phase == .thinking {
            Label(model.chat.working ?? "Jarvis is thinking…", systemImage: model.chat.working == nil ? "sparkles" : "gearshape.2.fill")
                .font(.callout)
                .foregroundStyle(palette.inkDim.color)
                .labelStyle(TintedIconLabel(icon: model.chat.working == nil ? palette.accent.color : palette.warm.color))
                .symbolEffect(.pulse, options: .repeating)
        } else if model.chat.lines.isEmpty {
            Text("Ask him anything. He'll keep the conversation going.")
                .font(.callout)
                .foregroundStyle(palette.inkDim.color)
        } else {
            Color.clear.frame(height: 1)
        }
    }

    /// Bold, italics, code and links render; anything else stays plain.
    private func markdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

/// The TV's buttons (Dylan, 2026-11-18: "when i select a button without
/// clicking the highlight is too white. Make it less white"). Instead of
/// tvOS's bright white plate: a soft translucent tint with a clear outline
/// and a small lift when focused, a quiet surface when not. The label keeps
/// the palette's measured ink in every state.
struct SoftFocusButtonStyle: ButtonStyle {
    let palette: LampPalette

    func makeBody(configuration: Configuration) -> some View {
        Plate(configuration: configuration, palette: palette)
    }

    private struct Plate: View {
        let configuration: ButtonStyleConfiguration
        let palette: LampPalette
        @Environment(\.isFocused) private var focused

        var body: some View {
            configuration.label
                .font(.callout.weight(.semibold))
                .foregroundStyle(palette.ink.color)
                .padding(.horizontal, 30)
                .padding(.vertical, 16)
                .background(Capsule().fill(fill))
                .overlay(Capsule().strokeBorder(edge, lineWidth: focused ? 3 : 1.5))
                .scaleEffect(configuration.isPressed ? 0.97 : focused ? 1.08 : 1)
                .shadow(color: .black.opacity(focused ? 0.25 : 0), radius: 16, y: 8)
                .animation(.smooth(duration: 0.25), value: focused)
                .animation(.smooth(duration: 0.12), value: configuration.isPressed)
        }

        /// White at about a fifth over the dark sky; a light accent wash on
        /// the bright day sky, where white wouldn't show.
        private var fill: Color {
            if focused { return palette.darkInk ? palette.accent.color.opacity(0.16) : Color.white.opacity(0.22) }
            return palette.panel.color.opacity(0.7)
        }

        /// The outline that makes focus visible from across the room.
        private var edge: Color {
            if focused { return palette.darkInk ? palette.accent.color : Color.white.opacity(0.75) }
            return palette.panelEdge.color.opacity(0.7)
        }
    }
}

