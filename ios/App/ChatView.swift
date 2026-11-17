// The Chat tab: Dylan's conversation with Jarvis, approval cards inline,
// and the Ask box at the bottom.
import SwiftUI
import JarvisKit

struct ChatView: View {
    @EnvironmentObject private var app: AppModel
    @ObservedObject var chat: ChatModel
    @State private var draft = ""
    @State private var flagging: ChatItem?
    @FocusState private var typing: Bool
    /// Whether the newest line is on screen; when it isn't, "Scroll to
    /// bottom" shows (Dylan, 2026-11-17).
    @State private var atBottom = true

    /// Status line, the scrolling chat, then the composer.
    var body: some View {
        ZStack {
            Theme.sky.ignoresSafeArea()
            VStack(spacing: 0) {
                StatusLine()
                messages
                if let problem = chat.problem {
                    Text(problem)
                        .font(.footnote)
                        .foregroundStyle(Theme.rose)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                composer
            }
        }
        .task {
            if !chat.loaded {
                await app.client.warm()
                await chat.load(app: app)
            }
        }
        .sheet(item: $flagging) { item in
            WrongSheet(item: item)
        }
    }

    /// The conversation, kept scrolled to the newest line.
    private var messages: some View {
        ScrollViewReader { scroller in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if chat.items.isEmpty && chat.loaded {
                        emptyState
                    }
                    ForEach(chat.items) { item in
                        row(item).id(item.id)
                    }
                    if showDots {
                        TypingDots(label: chat.working).id("dots")
                    }
                    // An invisible marker after the last line: on screen
                    // means the chat is scrolled to the bottom.
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                        .onAppear { atBottom = true }
                        .onDisappear { atBottom = false }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            // Opens on the newest message, like Messages.
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await chat.load(app: app) }
            .onChange(of: chat.items) {
                withAnimation(.easeOut(duration: 0.2)) {
                    scroller.scrollTo(chat.items.last?.id, anchor: .bottom)
                }
            }
            .overlay(alignment: .bottom) {
                if !atBottom {
                    Button {
                        withAnimation(.easeOut(duration: 0.3)) {
                            scroller.scrollTo("bottom", anchor: .bottom)
                        }
                    } label: {
                        Label("Scroll to bottom", systemImage: "arrow.down")
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(Theme.glass))
                            .overlay(Capsule().strokeBorder(Theme.glassEdge))
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .foregroundStyle(Theme.frost)
                    .padding(.bottom, 10)
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.2), value: atBottom)
        }
    }

    /// Typing dots while he thinks, looks something up, or hasn't started
    /// writing yet (the web page also shows them after 1.5 s of quiet).
    private var showDots: Bool {
        guard chat.isSending else { return false }
        if chat.working != nil { return true }
        guard let last = chat.items.last, last.kind == .jarvis else { return true }
        return last.text.isEmpty
    }

    /// The orb and a nudge, before there's any chat.
    private var emptyState: some View {
        VStack(spacing: 20) {
            OrbView(state: .listening, size: 120)
            Text("Ask Jarvis anything.")
                .foregroundStyle(Theme.frostDim)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    /// One chat line, drawn by kind.
    @ViewBuilder
    private func row(_ item: ChatItem) -> some View {
        switch item.kind {
        case .user:
            Text(item.text)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 20, bottomTrailingRadius: 6, topTrailingRadius: 20).fill(Theme.userBubble))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.leading, 60)
        case .jarvis:
            if !item.text.isEmpty {
                JarvisBubble(item: item) { flagging = item }
                    .padding(.trailing, 40)
            }
        case .approval(let approval):
            ApprovalCard(approval: approval, outcome: item.outcome) { ok in
                Task { await chat.answer(approval, ok: ok, app: app) }
            }
            .padding(.trailing, 30)
        }
    }

    /// The Ask box and Send.
    private var composer: some View {
        HStack(spacing: 8) {
            TextField("Ask Jarvis", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .focused($typing)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.glass))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.glassEdge))
                .submitLabel(.send)
                .onSubmit(send)
            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(canSend ? Theme.glacier : Theme.glass))
                    .foregroundStyle(canSend ? Theme.basalt : Theme.frostFaint)
            }
            .disabled(!canSend)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// Something typed and no reply still coming.
    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !chat.isSending
    }

    /// Sends the draft and clears the box.
    private func send() {
        guard canSend else { return }
        let text = draft
        draft = ""
        Task { await chat.send(text, app: app) }
    }
}

/// One of Jarvis's replies: the model chip, the words, and the faint "…"
/// ("That was wrong") once it's finished.
struct JarvisBubble: View {
    let item: ChatItem
    let onWrong: () -> Void

    /// Chip over a glass bubble.
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let model = item.model, !ModelWording.label(model).isEmpty {
                let tone = ModelWording.isClaude(model) ? Theme.ember : Theme.glacier
                Text(ModelWording.label(model))
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .foregroundStyle(tone)
                    .background(Capsule().fill(tone.opacity(0.14)))
            }
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(markdown(item.text))
                    .textSelection(.enabled)
                if item.finished {
                    Button(action: onWrong) {
                        Text("…")
                            .foregroundStyle(Theme.frostFaint)
                            .frame(minWidth: 28, minHeight: 28)
                    }
                    .accessibilityLabel("That was wrong")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 6, bottomTrailingRadius: 20, topTrailingRadius: 20).fill(Theme.glass))
            .overlay(UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 6, bottomTrailingRadius: 20, topTrailingRadius: 20).strokeBorder(Theme.glassEdge))
        }
    }

    /// Bold, italics, code and links render; anything else stays plain text.
    private func markdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

/// Three soft dots, plus what he's looking up when he says.
struct TypingDots: View {
    let label: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The dots blink in turn unless Reduce Motion is on.
    var body: some View {
        HStack(spacing: 10) {
            TimelineView(.animation(paused: reduceMotion)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                HStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(Theme.frostDim)
                            .frame(width: 7, height: 7)
                            .opacity(reduceMotion ? 0.7 : 0.3 + 0.7 * abs(sin(t * 2.6 - Double(i) * 0.6)))
                    }
                }
            }
            if let label, !label.isEmpty {
                Text(label)
                    .font(.footnote)
                    .foregroundStyle(Theme.ember)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label ?? "Jarvis is thinking")
    }
}
