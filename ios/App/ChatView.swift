// The Chat tab: Dylan's conversation with Jarvis, approval cards inline,
// and the Ask box at the bottom.
import PhotosUI
import SwiftUI
import JarvisKit

struct ChatView: View {
    @EnvironmentObject private var app: AppModel
    @ObservedObject var chat: ChatModel
    @State private var draft = ""
    /// Photos picked for the next message (up to 4).
    @State private var picked: [PickedPhoto] = []
    @State private var choosing: [PhotosPickerItem] = []
    @State private var showLibrary = false
    @State private var showCamera = false
    /// The turn just opened from a notice, glowing for a moment.
    @State private var highlighted: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flagging: ChatItem?
    @FocusState private var typing: Bool
    /// Whether the newest line is on screen; when it isn't, "Scroll to
    /// bottom" shows (Dylan, 2026-11-17).
    @State private var atBottom = true
    /// Scrolled up by hand, well clear of the newest line: the bar tucks
    /// away. Set from the scroll's own geometry (iOS 18), never by content
    /// loading, so the chat can't open tucked.
    @State private var readingUp = false
    /// Tapped the compose button: the bar stays open until he scrolls up again.
    @State private var opened = false
    /// A reply arrived while he was reading further up (the compose button's orange dot).
    @State private var unseenReply = false
    /// Whether the keyboard is up (RootView's KeyboardWatch).
    @EnvironmentObject private var keyboard: KeyboardWatch

    /// Status line, the scrolling chat, then the composer.
    var body: some View {
        ZStack {
            Theme.sky.ignoresSafeArea()
            VStack(spacing: 0) {
                StatusLine()
                messages
                if let problem = chat.problem {
                    HStack {
                        Text(problem)
                            .font(.footnote)
                            .foregroundStyle(Theme.rose)
                        Spacer()
                        if chat.failed != nil {
                            Button("Try again") { Task { await chat.retry(app: app) } }
                                .font(.footnote.weight(.semibold))
                                .frame(minHeight: 44)
                        } else if chat.failedMeal != nil {
                            Button("Try again") { Task { await chat.retryMeal(app: app) } }
                                .font(.footnote.weight(.semibold))
                                .frame(minHeight: 44)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                }
                pinnedApprovals
                if !picked.isEmpty {
                    PickedStrip(photos: $picked)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if !collapsed {
                    composer
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
            // The same spring as the tab bar's shrink, so the two move as one.
            .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.85), value: collapsed)
            // A blocking "Sending photos…" (or "Telling Jarvis…") while it goes.
            if chat.uploading || chat.busy != nil {
                Color.black.opacity(0.35).ignoresSafeArea()
                VStack(spacing: 14) {
                    ProgressView().controlSize(.large).tint(Theme.frost)
                    Text(chat.busy ?? "Sending photos…").font(.headline).foregroundStyle(Theme.frost)
                }
                .padding(28)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.ultraThinMaterial))
                .transition(.opacity)
            }
        }
        .animation(.smooth, value: chat.uploading)
        .animation(.smooth, value: chat.busy)
        .animation(.smooth, value: picked.count)
        .photosPicker(isPresented: $showLibrary, selection: $choosing, maxSelectionCount: max(1, PhotoLimits.room(holding: picked.count)), matching: .images)
        .onChange(of: choosing) { _, items in
            guard !items.isEmpty else { return }
            Task {
                for item in items.prefix(PhotoLimits.room(holding: picked.count)) {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        add(image)
                    }
                }
                choosing = []
            }
        }
        #if DEBUG
        // Screenshot check: `-demoPhotos` picks two sample photos.
        .onAppear {
            // `-typing` puts the cursor in the field (simulator keyboard checks).
            if ProcessInfo.processInfo.arguments.contains("-typing") {
                Task { try? await Task.sleep(for: .seconds(1.5)); typing = true }
            }
            if ProcessInfo.processInfo.arguments.contains("-demoPhotos"), picked.isEmpty {
                for color in [UIColor.systemOrange, UIColor.systemGreen] {
                    let image = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 900)).image { ctx in
                        color.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 1200, height: 900))
                    }
                    add(image)
                }
            }
        }
        #endif
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in add(image) }.ignoresSafeArea()
        }
        // Waiting approvals collapse into "Timed out" once their time is up.
        .task {
            while !Task.isCancelled {
                chat.expireOverdue()
                try? await Task.sleep(for: .seconds(5))
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
                        // iOS 17 only; on 18 the scroll's own geometry decides (ReadingUpWatch).
                        .onAppear { if #unavailable(iOS 18.0) { atBottom = true } }
                        .onDisappear { if #unavailable(iOS 18.0) { atBottom = false } }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            // Opens on the newest message, like Messages.
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .reportsScrollToTabBar()
            .modifier(ReadingUpWatch(readingUp: $readingUp, atBottom: $atBottom))
            .refreshable { await chat.load(app: app) }
            // "Build it with Jarvis" and the like: words ready in the box.
            .onChange(of: app.chatPrefill) { _, words in
                guard let words else { return }
                draft = words
                typing = true
                app.chatPrefill = nil
            }
            // The keyboard coming up keeps the newest message in view above
            // the field, like Messages.
            .onChange(of: keyboard.up) { _, up in
                guard up, app.focusTurn == nil, highlighted == nil else { return }
                withAnimation(.easeOut(duration: 0.25)) { scroller.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: chat.items) {
                guard app.focusTurn == nil && highlighted == nil else { return }
                // Reading further up: stay put, and dot the compose button instead.
                guard ComposerSize.follows(atBottom: atBottom, lastIsMine: chat.items.last?.kind == .user, sending: chat.isSending) else {
                    if chat.items.last?.kind == .jarvis { unseenReply = true }
                    return
                }
                withAnimation(.easeOut(duration: 0.2)) {
                    scroller.scrollTo(chat.items.last?.id, anchor: .bottom)
                }
            }
            #if DEBUG
            // `-scrollChatUp` scrolls to the oldest line (simulator check of the tucked bar).
            .task {
                guard ProcessInfo.processInfo.arguments.contains("-scrollChatUp") else { return }
                try? await Task.sleep(for: .seconds(4))
                scroller.scrollTo(chat.items.first?.id, anchor: .top)
                readingUp = true
                if ProcessInfo.processInfo.arguments.contains("-pretendNew") { unseenReply = true }
            }
            #endif
            .onChange(of: atBottom) { _, bottom in
                if bottom { unseenReply = false }
            }
            .onChange(of: readingUp) { _, up in
                if up { opened = false } else { unseenReply = false }
            }
            // A notice or notification opened a turn: find it (loading the
            // history if it isn't here yet), scroll to it and let it glow.
            .onChange(of: app.focusTurn) { _, target in
                guard let target else { return }
                Task {
                    if !chat.items.contains(where: { $0.turnId == target }) { await chat.load(app: app) }
                    if let item = chat.items.first(where: { $0.turnId == target }) {
                        withAnimation(.easeOut(duration: 0.4)) { scroller.scrollTo(item.id, anchor: .center) }
                        // A soft tint on the bubble that fades in, rests and
                        // fades out over about two seconds (Dylan, 2026-11-18:
                        // the old outline "is quite ugly"). Reduce Motion: a
                        // plain brief tint, no fading.
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.45)) { highlighted = target }
                        var rest = reduceMotion ? 1.5 : 1.2
                        #if DEBUG
                        // `-holdGlow` keeps it up long enough for a screenshot.
                        if ProcessInfo.processInfo.arguments.contains("-holdGlow") { rest = 60 }
                        #endif
                        try? await Task.sleep(for: .seconds(rest))
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.9)) { highlighted = nil }
                    } else {
                        withAnimation(.easeOut(duration: 0.3)) { scroller.scrollTo("bottom", anchor: .bottom) }
                    }
                    app.focusTurn = nil
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if collapsed {
                    compactComposer(scroller)
                        .padding(.trailing, 12)
                        .padding(.bottom, 8)
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.6, anchor: .bottomTrailing).combined(with: .opacity))
                }
            }
            .overlay(alignment: .bottom) {
                // Typing while scrolled up: a plain way back down.
                // Only after he scrolled up by hand, so it never flashes while the chat loads.
                if readingUp && !collapsed {
                    Button {
                        withAnimation(.easeOut(duration: 0.3)) {
                            scroller.scrollTo("bottom", anchor: .bottom)
                        }
                    } label: {
                        Label("Scroll to bottom", systemImage: "arrow.down")
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)
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
            VStack(alignment: .trailing, spacing: 6) {
                if !item.photos.isEmpty {
                    BubblePhotos(photos: item.photos)
                } else if item.photoCount > 0 {
                    // Past photos aren't kept on the device: a chip says so.
                    Label(PhotoLimits.chip(item.photoCount), systemImage: "photo.on.rectangle")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Theme.userBubble.opacity(0.6)))
                }
                if !item.text.isEmpty {
                    Text(item.text)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 20, bottomTrailingRadius: 6, topTrailingRadius: 20).fill(Theme.userBubble))
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, 60)
        case .jarvis:
            if !item.text.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    // A notice opened here: the bubble itself glows softly.
                    JarvisBubble(item: item, glowing: item.turnId != nil && item.turnId == highlighted, kept: app.isKept(turnId: item.turnId, historyKept: item.kept)) { flagging = item }
                        // Keep any finished message as a yellow dot, or let
                        // a kept one go (Dylan, 2026-11-19).
                        .contextMenu {
                            if let turnId = item.turnId, item.finished {
                                if app.isKept(turnId: turnId, historyKept: item.kept) {
                                    Button("Let go", systemImage: "bookmark.slash") { Task { await app.letGo(turnId: turnId) } }
                                } else {
                                    Button("Keep", systemImage: "bookmark") { Task { await app.keep(turnId: turnId) } }
                                }
                            }
                            Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = item.text }
                        }
                    // "Is this the meal I already logged?"
                    if item.mealKey != nil && item.mealAnswer == nil && item.finished {
                        HStack(spacing: 8) {
                            ForEach(item.mealChoices, id: \.self) { choice in
                                Button(MealChoice.label(choice)) {
                                    Task { await chat.answerMeal(item, choice: choice, app: app) }
                                }
                                .buttonStyle(.bordered)
                                .tint(Theme.glacier)
                                .frame(minHeight: 44)
                                .disabled(chat.busy != nil)
                            }
                        }
                    } else if let answer = item.mealAnswer {
                        Text(MealChoice.label(answer))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.frostDim)
                    }
                }
                .padding(.trailing, 40)
            }
        case .approval:
            // Waiting ones are pinned above the Ask box; settled ones are a
            // single line here, where they happened.
            if let line = item.outcome {
                ApprovalLine(text: line)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottom)))
            }
        }
    }

    /// Approvals still waiting, pinned just above the Ask box until
    /// they're answered or time out.
    @ViewBuilder
    private var pinnedApprovals: some View {
        let pending = chat.pendingApprovals
        if !pending.isEmpty {
            VStack(spacing: 8) {
                ForEach(pending) { approval in
                    ApprovalCard(approval: approval, outcome: nil) { ok in
                        Task { await chat.answer(approval, ok: ok, app: app) }
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .animation(.smooth(duration: 0.35), value: pending.map(\.id))
        }
    }

    /// Whether the input bar is tucked into the compose button (JarvisKit ComposerSize).
    private var collapsed: Bool {
        ComposerSize.collapsed(atBottom: !readingUp, focused: typing,
                               hasDraft: !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !picked.isEmpty,
                               sending: chat.isSending, opened: opened)
    }

    /// Scrolled up reading: compose (opens the bar, focused, at the newest
    /// line) and jump to newest, with an orange dot for a reply not seen yet.
    private func compactComposer(_ scroller: ScrollViewProxy) -> some View {
        HStack(spacing: 0) {
            Button {
                opened = true
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) { scroller.scrollTo("bottom", anchor: .bottom) }
                Task { try? await Task.sleep(for: .milliseconds(120)); typing = true }
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Write a message")
            Button {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) { scroller.scrollTo("bottom", anchor: .bottom) }
            } label: {
                Image(systemName: "arrow.down")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .overlay(alignment: .topTrailing) {
                        if unseenReply {
                            Circle().fill(OrbView.noticeOrange(onLight: false)).frame(width: 9, height: 9).offset(x: -8, y: 9)
                        }
                    }
            }
            .accessibilityLabel(unseenReply ? "Newest message, a new reply" : "Newest message")
        }
        .foregroundStyle(Theme.frost)
        .padding(.horizontal, 2)
        .background(.ultraThinMaterial, in: Capsule())
        .background(Capsule().fill(Theme.glass))
        .overlay(Capsule().strokeBorder(Theme.glassEdge))
    }

    /// The Ask box: one slim pill with the photo and send buttons inside,
    /// growing only as he types more lines (Dylan, 2026-11-19).
    private var composer: some View {
        HStack(alignment: .bottom, spacing: 0) {
            // Photos: take one, or choose up to four.
            Menu {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button { showCamera = true } label: { Label("Take Photo", systemImage: "camera") }
                }
                Button { showLibrary = true } label: { Label("Choose Photos", systemImage: "photo.on.rectangle") }
            } label: {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 44, height: 44)
                    .foregroundStyle(PhotoLimits.room(holding: picked.count) > 0 ? Theme.frost : Theme.frostFaint)
            }
            .disabled(PhotoLimits.room(holding: picked.count) == 0 || chat.isSending)
            .accessibilityLabel("Add photos")
            TextField("Ask Jarvis", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .focused($typing)
                .padding(.vertical, 11)
                .submitLabel(.send)
                .onSubmit(send)
            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(canSend ? Theme.glacier : Color.white.opacity(0.08)))
                    .foregroundStyle(canSend ? Theme.basalt : Theme.frostFaint)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(!canSend)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, 2)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.glass))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.glassEdge))
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 2)
    }

    /// Something typed (or a photo picked) and no reply still coming.
    private var canSend: Bool {
        (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !picked.isEmpty) && !chat.isSending
    }

    /// Sends the draft and any photos, and clears both.
    private func send() {
        guard canSend else { return }
        let text = draft
        let photos = picked
        draft = ""
        picked = []
        Task { await chat.send(text, photos: photos, app: app) }
    }

    /// Shrinks a taken or chosen photo and adds it to the next message.
    private func add(_ image: UIImage) {
        guard PhotoLimits.room(holding: picked.count) > 0, let jpeg = PhotoEncoder.encode(image) else { return }
        picked.append(PickedPhoto(preview: PhotoEncoder.thumbnail(image), jpeg: jpeg))
    }
}

/// One of Jarvis's replies: the model chip, the words, and the faint "…"
/// ("That was wrong") once it's finished.
struct JarvisBubble: View {
    let item: ChatItem
    /// True while a notice that opened this message is pointing at it: the
    /// bubble takes a soft orange tint in its own shape.
    var glowing = false
    /// Kept to remember: a small yellow marker by the chip.
    var kept = false
    let onWrong: () -> Void

    /// The bubble's own shape, shared by its fill, edge and glow.
    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 6, bottomTrailingRadius: 20, topTrailingRadius: 20)
    }

    /// Chip over a glass bubble.
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let model = item.model {
                    chip(ModelWording.chip(model: model, writer: item.writer))
                }
                if kept {
                    Label("Kept", systemImage: "bookmark.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(OrbView.keptYellow(onLight: false))
                        .accessibilityLabel("Kept")
                }
            }
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(markdown(item.text))
                    .textSelection(.enabled)
                if item.finished && !ModelWording.isNotice(item.model ?? "") {
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
            .background(shape.fill(Theme.glass))
            .background(shape.fill(OrbView.noticeOrange(onLight: false).opacity(glowing ? 0.18 : 0)))
            .overlay(shape.strokeBorder(glowing ? OrbView.noticeOrange(onLight: false).opacity(0.45) : Theme.glassEdge, lineWidth: 1))
            .shadow(color: OrbView.noticeOrange(onLight: false).opacity(glowing ? 0.28 : 0), radius: 12)
        }
    }

    /// Who wrote it: "Jarvis (CO)" in its colour, and for a message he sent
    /// unasked the source word in quiet grey after it ("Lookout").
    @ViewBuilder
    private func chip(_ chip: ModelWording.Chip) -> some View {
        if !chip.label.isEmpty {
            HStack(spacing: 6) {
                let tone: Color = chip.tone == .claude ? Theme.ember : chip.tone == .local ? Theme.glacier : Theme.frostDim
                Text(chip.label)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .foregroundStyle(tone)
                    .background(Capsule().fill(chip.tone == .notice ? Color.white.opacity(0.08) : tone.opacity(0.14)))
                if !chip.source.isEmpty {
                    Text(chip.source)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Theme.frostDim)
                }
            }
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

/// Whether he has scrolled up by hand, away from the newest line (more than
/// 120 pt above it); back within 40 pt counts as the bottom again. Only a
/// drag (or its fling) can tuck the bar, never content loading in.
private struct ReadingUpWatch: ViewModifier {
    @Binding var readingUp: Bool
    /// Within 60 pt of the newest line (out past 100 pt is no longer).
    @Binding var atBottom: Bool

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.modifier(Watch(readingUp: $readingUp, atBottom: $atBottom))
        } else {
            content
        }
    }

    @available(iOS 18.0, *)
    private struct Watch: ViewModifier {
        @Binding var readingUp: Bool
        @Binding var atBottom: Bool
        @State private var byHand = false

        func body(content: Content) -> some View {
            content
                .onScrollPhaseChange { _, phase in
                    if phase == .interacting { byHand = true }
                    if phase == .idle { byHand = false }
                }
                .onScrollGeometryChange(for: Double.self) { g in
                    // How far the newest line is below the visible area.
                    g.contentSize.height + g.contentInsets.bottom - (g.contentOffset.y + g.containerSize.height)
                } action: { _, gap in
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("-logGap") { print("GAP", gap) }
                    #endif
                    if gap < 60 { if !atBottom { atBottom = true } }
                    else if gap > 100 { if atBottom { atBottom = false } }
                    if gap < 40 { if readingUp { readingUp = false } }
                    else if gap > 120, byHand, !readingUp { readingUp = true }
                }
        }
    }
}
