// The Chat tab: Dylan's conversation with Jarvis, approval cards inline,
// and the Ask box at the bottom.
import PhotosUI
import SwiftUI
import JarvisKit

struct ChatView: View {
    @EnvironmentObject private var app: AppModel
    @ObservedObject var chat: ChatModel
    /// Whether the box holds any words. The words themselves live in
    /// ComposerField, so a keystroke redraws only the box, never the list
    /// (Dylan, 2026-11-19: typing felt laggy; every key used to rebuild
    /// all 240 rows). This flips only when the box goes empty or not.
    @State private var hasText = false
    /// Loading a window round a notice's message.
    @State private var finding = false
    /// How many of the newest messages are drawn (JarvisKit ChatWindow);
    /// older ones are added a page at a time as he reaches the top.
    @State private var shown = ChatWindow.page
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
    @Environment(\.scenePhase) private var scenePhase

    /// Status line, the scrolling chat, then the composer.
    var body: some View {
        #if DEBUG
        let _ = PerfCount.bump("chat")
        #endif
        ZStack(alignment: .top) {
            Theme.sky.ignoresSafeArea()
            VStack(spacing: 0) {
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
                // Always laid out, only faded (Dylan, 2026-11-20: the lag was
                // worst as the box went and came back): removing it resized
                // the list and re-laid out every message. Hidden, it can't be
                // touched.
                composer
                    .opacity(collapsed ? 0 : 1)
                    .offset(y: collapsed && !reduceMotion ? 6 : 0)
                    .allowsHitTesting(!collapsed)
                    .accessibilityHidden(collapsed)
                    .animation(reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.22), value: collapsed)
            }
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
        // No bar: the notices pill and gear float as glass over the chat.
        .overlay(alignment: .top) { TopFade() }
        .floatingStatus(showsStatus: false)
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
        // The first visit loads the chat. The paged tab view runs this again
        // every time Chat slides in, and that used to refetch the history
        // mid-slide and redraw the whole chat while it moved: the "tiny
        // stutter" from Talk to Chat (Dylan, 2026-11-20). Later visits do
        // nothing; replies arrive through the stream, a push, or coming
        // back to the app (scenePhase below).
        .task {
            guard !chat.loaded else { return }
            await app.client.warm()
            await chat.load(app: app)
            // Opened fresh after leaving mid-reply: fetch what finished.
            await chat.catchUp(app: app)
        }
        // Back in the app: a reply that finished while it was away.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await chat.catchUp(app: app) } }
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
                    // The rows redraw only when what they show changes, not
                    // on every change anywhere in the app (Dylan, 2026-11-19:
                    // tab swipes and typing were rebuilding all of them).
                    // Older messages wait until he scrolls up to them.
                    if ChatWindow.hasMore(shown: shown, total: chat.items.count) || chat.olderOnServer {
                        olderRow(scroller)
                            .id("older")
                            // Loads when he has scrolled up to it himself, and
                            // again after each page while it's still in view;
                            // never on its own at the bottom of the chat.
                            .task(id: "\(shown)-\(chat.items.count)-\(readingUp)") {
                                guard readingUp else { return }
                                try? await Task.sleep(for: .milliseconds(150))
                                guard !Task.isCancelled else { return }
                                loadOlder(scroller)
                            }
                    }
                    ChatRowsList(items: Array(chat.items.suffix(shown)), highlighted: highlighted, keptTurns: keptTurns,
                                 mealBusy: chat.busy != nil, actions: rowActions)
                        .equatable()
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
            // For the UI tests: the page scroller is a scroll view too now.
            .accessibilityIdentifier("chatList")
            // Nothing to show yet: message-shaped placeholders in the list's
            // place, so the page still slides in looking like Chat, then
            // the messages fade in over them once (Dylan, 2026-11-20). With
            // messages already here it never shows.
            .overlay {
                if chat.items.isEmpty && !chat.loaded {
                    ChatSkeleton()
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.3), value: chat.loaded)
            // Messages run up under the floating buttons (no bar).
            .contentMargins(.top, FloatingStatus.room, for: .scrollContent)
            .scrollDismissesKeyboard(.interactively)
            .reportsScrollToTabBar()
            .modifier(ReadingUpWatch(readingUp: $readingUp, atBottom: $atBottom))
            .refreshable { await chat.load(app: app) }
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
                focus(on: target, scroller)
            }
            // Chat may be built only now, with a turn already asked for (a
            // push tapped while the app was closed, or a first visit).
            .onAppear { focus(on: app.focusTurn, scroller) }
            // The measuring run (-perfCycle): fling to the top or bottom.
            .onReceive(NotificationCenter.default.publisher(for: .perfScroll)) { note in
                withAnimation(.easeInOut(duration: 1.2)) {
                    if note.object as? String == "top", let first = chat.items.suffix(shown).first?.id {
                        scroller.scrollTo(first, anchor: .top)
                    } else {
                        scroller.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
            .overlay {
                if finding {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Finding that message…").font(.subheadline)
                    }
                    .padding(.horizontal, 18)
                    .frame(minHeight: 44)
                    .background(.ultraThinMaterial, in: Capsule())
                    .foregroundStyle(Theme.frost)
                }
            }
            .overlay(alignment: .top) {
                // Opened at an older part of the chat: the way back.
                if chat.newerOnServer && !finding {
                    Button {
                        Task {
                            await chat.load(app: app)
                            shown = ChatWindow.first(total: chat.items.count)
                            try? await Task.sleep(for: .milliseconds(50))
                            scroller.scrollTo("bottom", anchor: .bottom)
                        }
                    } label: {
                        Label("Latest", systemImage: "arrow.down.to.line")
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(Capsule().strokeBorder(Theme.glassEdge))
                    }
                    .foregroundStyle(Theme.frost)
                    .padding(.top, FloatingStatus.room + 4)
                    .accessibilityLabel("Go to the latest messages")
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
    /// Goes to a notice's message: loads round it if need be, scrolls to it
    /// and lets it glow; if it isn't in the chat any more (or the notice has
    /// no message), the notice's own full text opens instead.
    private func focus(on target: Int?, _ scroller: ScrollViewProxy) {
        guard let target else { return }
        Task {
            // Not held: ask for a window round it (a paging server
            // answers one; today's sends its newest turns), with a
            // labelled wait rather than a list jumping about.
            if !chat.items.contains(where: { $0.turnId == target }) {
                finding = true
                await chat.load(app: app, around: target)
                finding = false
            }
            let fallback = app.focusFallback
            app.focusFallback = nil
            if case .scroll = NoticeFocus.outcome(turnId: target, loaded: chat.items.compactMap(\.turnId)),
               let index = chat.items.firstIndex(where: { $0.turnId == target }) {
                // An old turn beyond the drawn window: widen it first.
                shown = ChatWindow.including(index: index, shown: shown, total: chat.items.count)
                try? await Task.sleep(for: .milliseconds(50))
                let item = chat.items[index]
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
            } else if let fallback {
                // The message isn't in the chat any more: the notice's
                // own full text, not the bottom of Chat.
                app.readingNotice = fallback
            }
            app.focusTurn = nil
        }
    }

    /// The top row: a spinner only while a page is really on its way; after a
    /// failure a plain line and Retry; otherwise a button to load more.
    @ViewBuilder
    private func olderRow(_ scroller: ScrollViewProxy) -> some View {
        Group {
            if chat.loadingOlder {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading earlier messages").font(.footnote).foregroundStyle(Theme.frostDim)
                }
            } else if chat.older.state == .failed {
                HStack(spacing: 10) {
                    Text("Couldn’t load earlier messages.").font(.footnote).foregroundStyle(Theme.frostDim)
                    Button("Retry") { chat.retryOlder(); loadOlder(scroller) }
                        .font(.footnote.weight(.semibold))
                        .frame(minHeight: 44)
                }
            } else {
                Button("Earlier messages") { loadOlder(scroller) }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.glacier)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44)
    }

    /// Adds the next page of older messages above, keeping his place: the
    /// message that was at the top stays where it was.
    private func loadOlder(_ scroller: ScrollViewProxy) {
        let total = chat.items.count
        guard ChatWindow.hasMore(shown: shown, total: total) else {
            // Everything held is drawn: ask the server for an older page.
            let anchor = chat.items.first?.id
            Task {
                await chat.loadOlder(app: app)
                shown = ChatWindow.grow(shown, total: chat.items.count)
                if let anchor {
                    var quiet = Transaction()
                    quiet.disablesAnimations = true
                    withTransaction(quiet) { scroller.scrollTo(anchor, anchor: .top) }
                }
            }
            return
        }
        let anchor = chat.items.suffix(shown).first?.id
        var quiet = Transaction()
        quiet.disablesAnimations = true
        withTransaction(quiet) { shown = ChatWindow.grow(shown, total: total) }
        if let anchor {
            Task { @MainActor in
                withTransaction(quiet) { scroller.scrollTo(anchor, anchor: .top) }
            }
        }
    }

    /// The turns showing as kept (yellow), for the rows.
    private var keptTurns: Set<Int> {
        app.keptTurns(in: chat.items)
    }

    /// What a row can do, without the rows watching the whole app.
    private var rowActions: ChatRowActions {
        let app = app, chat = chat
        let flag = $flagging
        return ChatRowActions(
            flag: { flag.wrappedValue = $0 },
            keep: { turn in Task { await app.keep(turnId: turn) } },
            letGo: { turn in Task { await app.letGo(turnId: turn) } },
            answerMeal: { item, choice in Task { await chat.answerMeal(item, choice: choice, app: app) } }
        )
    }

    private var showDots: Bool {
        if chat.catchingUp { return true }
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
                               hasDraft: hasText || !picked.isEmpty,
                               sending: chat.isSending, opened: opened)
    }

    /// Scrolled up reading: compose (opens the bar, focused, at the newest
    /// line) and jump to newest, with an orange dot for a reply not seen yet.
    private func compactComposer(_ scroller: ScrollViewProxy) -> some View {
        // One round arrow (Dylan, 2026-11-20): back to the newest message,
        // where the Ask box fades back in. Orange dot: a reply he hasn't seen.
        Button {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) { scroller.scrollTo("bottom", anchor: .bottom) }
        } label: {
            Image(systemName: "arrow.down")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
                .background(Circle().fill(Theme.glass))
                .overlay(Circle().strokeBorder(Theme.glassEdge))
                .overlay(alignment: .topTrailing) {
                    if unseenReply {
                        Circle().fill(OrbView.noticeOrange(onLight: false)).frame(width: 10, height: 10).offset(x: -2, y: 2)
                    }
                }
        }
        .foregroundStyle(Theme.frost)
        .accessibilityLabel(unseenReply ? "Newest message, a new reply" : "Newest message")
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
            ComposerField(hasText: $hasText, focus: $typing,
                          hasPhotos: !picked.isEmpty, sending: chat.isSending) { text in send(text) }
        }
        .padding(.horizontal, 2)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.glass))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.glassEdge))
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 2)
    }

    /// Sends the words (the box has already cleared itself) and any photos.
    private func send(_ text: String) {
        guard !chat.isSending, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !picked.isEmpty else { return }
        let photos = picked
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
            // The glow's shadow only while glowing: a shadow on every bubble,
            // even a clear one, was an offscreen render pass per message.
            .modifier(GlowShadow(on: glowing))
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
        MarkdownCache.shared.attributed(text)
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
                    if gap < 60 { if !atBottom { atBottom = true } }
                    else if gap > 100 { if atBottom { atBottom = false } }
                    if gap < 40 { if readingUp { readingUp = false } }
                    else if gap > 120, byHand, !readingUp { readingUp = true }
                }
        }
    }
}

/// Parsed reply text, kept so scrolling past a bubble again doesn't parse
/// its markdown again (Dylan, 2026-11-19: Chat felt laggy as he scrolled).
/// A reply still streaming in has new text each time, so it's parsed fresh.
final class MarkdownCache: @unchecked Sendable {
    static let shared = MarkdownCache()
    private let cache = NSCache<NSString, Box>()
    private final class Box { let value: AttributedString; init(_ v: AttributedString) { value = v } }

    init() { cache.countLimit = 400 }

    func attributed(_ text: String) -> AttributedString {
        if let hit = cache.object(forKey: text as NSString) { return hit.value }
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        #if DEBUG
        PerfCount.bump("markdown")
        #endif
        let value = (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
        cache.setObject(Box(value), forKey: text as NSString)
        return value
    }
}

/// The Ask box's words and its send button. It owns the typed text, so a
/// keystroke redraws this and nothing else; the Chat screen only hears
/// when the box goes from empty to not (or back).
private struct ComposerField: View {
    @Binding var hasText: Bool
    var focus: FocusState<Bool>.Binding
    let hasPhotos: Bool
    let sending: Bool
    let onSend: (String) -> Void
    @State private var text = ""
    /// Saves the unsent words half a second after the last keystroke, so
    /// they survive leaving the app or it being closed.
    @State private var saving: Task<Void, Never>?
    static let draftKey = "chat.draft"

    private var canSend: Bool {
        (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || hasPhotos) && !sending
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            TextField("Ask Jarvis", text: $text, axis: .vertical)
                .lineLimit(1...5)
                .focused(focus)
                .padding(.vertical, 11)
                .submitLabel(.send)
                .onSubmit(send)
                .accessibilityIdentifier("composer")
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
        .onChange(of: text) { _, new in
            let filled = !new.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if filled != hasText { hasText = filled }
            saving?.cancel()
            saving = Task {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                UserDefaults.standard.set(new, forKey: Self.draftKey)
            }
        }
        .onAppear {
            #if DEBUG
            // `-resetDraft`: start with an empty box (UI tests; an empty
            // `-chat.draft ""` argument doesn't reliably clear it).
            if ProcessInfo.processInfo.arguments.contains("-resetDraft") {
                UserDefaults.standard.removeObject(forKey: Self.draftKey)
                return
            }
            #endif
            if text.isEmpty, let saved = UserDefaults.standard.string(forKey: Self.draftKey), !saved.isEmpty { text = saved }
        }
    }

    private func send() {
        guard canSend else { return }
        let words = text
        text = ""
        saving?.cancel()
        UserDefaults.standard.removeObject(forKey: Self.draftKey)
        onSend(words)
    }
}

/// What a chat row can do (closures, so the rows needn't watch the app).
struct ChatRowActions {
    let flag: (ChatItem) -> Void
    let keep: (Int) -> Void
    let letGo: (Int) -> Void
    let answerMeal: (ChatItem, String) -> Void
}

/// Every chat row. Equatable on what it shows, so a redraw of the Chat
/// screen (a tab swipe, the bar, a keystroke) skips all of them unless a
/// message, the glow or a kept mark actually changed.
private struct ChatRowsList: View, Equatable {
    let items: [ChatItem]
    let highlighted: Int?
    let keptTurns: Set<Int>
    let mealBusy: Bool
    let actions: ChatRowActions

    static func == (a: ChatRowsList, b: ChatRowsList) -> Bool {
        a.items == b.items && a.highlighted == b.highlighted && a.keptTurns == b.keptTurns && a.mealBusy == b.mealBusy
    }

    var body: some View {
        ForEach(items) { item in
            row(item).id(item.id)
        }
    }

    /// One chat line, drawn by kind.
    @ViewBuilder
    private func row(_ item: ChatItem) -> some View {
        #if DEBUG
        let _ = PerfCount.bump("row")
        #endif
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
                    // The same light markdown as his replies (bold, italic, code).
                    Text(MarkdownCache.shared.attributed(item.text))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 20, bottomTrailingRadius: 6, topTrailingRadius: 20).fill(Theme.userBubble))
                        // A kept message carries a small yellow dot.
                        .overlay(alignment: .topLeading) {
                            if keptTurns.contains(item.turnId ?? -1) {
                                Circle().fill(OrbView.keptYellow(onLight: false)).frame(width: 9, height: 9).offset(x: -3, y: -3)
                                    .accessibilityLabel("Kept")
                            }
                        }
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, 60)
            // His own messages can be kept as a dot too (Dylan, 2026-11-20).
            .contextMenu {
                if let turnId = item.turnId {
                    if keptTurns.contains(turnId) {
                        Button("Unkeep", systemImage: "bookmark.slash") { actions.letGo(turnId) }
                    } else {
                        Button("Keep", systemImage: "bookmark") { actions.keep(turnId) }
                    }
                }
                Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = item.text }
            }
        case .jarvis:
            if !item.text.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    // A notice opened here: the bubble itself glows softly.
                    JarvisBubble(item: item, glowing: item.turnId != nil && item.turnId == highlighted, kept: keptTurns.contains(item.turnId ?? -1)) { actions.flag(item) }
                        // Keep any finished message as a yellow dot, or let
                        // a kept one go (Dylan, 2026-11-19).
                        .contextMenu {
                            if let turnId = item.turnId, item.finished {
                                if keptTurns.contains(turnId) {
                                    Button("Unkeep", systemImage: "bookmark.slash") { actions.letGo(turnId) }
                                } else {
                                    Button("Keep", systemImage: "bookmark") { actions.keep(turnId) }
                                }
                            }
                            Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = item.text }
                        }
                    // "Is this the meal I already logged?"
                    if item.mealKey != nil && item.mealAnswer == nil && item.finished {
                        HStack(spacing: 8) {
                            ForEach(item.mealChoices, id: \.self) { choice in
                                Button(MealChoice.label(choice)) {
                                    actions.answerMeal(item, choice)
                                }
                                .buttonStyle(.bordered)
                                .tint(Theme.glacier)
                                .frame(minHeight: 44)
                                .disabled(mealBusy)
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
}

extension Notification.Name {
    /// The measuring run's "scroll Chat now" (-perfCycle only).
    static let perfScroll = Notification.Name("jarvis.perfScroll")
}

/// A soft orange shadow, only when on (no shadow layer at all otherwise).
private struct GlowShadow: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if on {
            content.shadow(color: OrbView.noticeOrange(onLight: false).opacity(0.28), radius: 12)
        } else {
            content
        }
    }
}

/// Placeholder bubbles while Chat has nothing at all yet: Jarvis's on the
/// left, his on the right, varied widths, in the bubbles' own glass, with a
/// soft shimmer (still with Reduce Motion). Read out as "Loading chat".
private struct ChatSkeleton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lit = false

    /// (his, width as a share of the row, height)
    private static let rows: [(Bool, CGFloat, CGFloat)] = [
        (false, 0.72, 74), (true, 0.38, 40), (false, 0.56, 52),
        (true, 0.5, 40), (false, 0.8, 96), (true, 0.3, 40), (false, 0.62, 58),
    ]

    var body: some View {
        GeometryReader { box in
            VStack(spacing: 14) {
                Spacer(minLength: 0)
                ForEach(Self.rows.indices, id: \.self) { i in
                    let (his, share, height) = Self.rows[i]
                    HStack {
                        if his { Spacer(minLength: 0) }
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(his ? 0.10 : 0.07))
                            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.06)))
                            .frame(width: (box.size.width - 32) * share, height: height)
                        if !his { Spacer(minLength: 0) }
                    }
                }
            }
            .padding(.horizontal, 16)
            // Clear of the composer and the tab bar below.
            .padding(.bottom, 150)
            .opacity(reduceMotion ? 0.8 : (lit ? 1 : 0.55))
        }
        .allowsHitTesting(false)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { lit = true }
        }
        .accessibilityElement()
        .accessibilityLabel("Loading chat")
    }
}
