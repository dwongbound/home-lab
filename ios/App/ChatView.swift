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
    /// Chat is off to the side (set by the pager); flips only when Chat is
    /// the page leaving or arriving, so other tab changes don't touch it.
    @Environment(\.orbOffScreen) private var pageOffScreen

    /// Status line, the scrolling chat, then the composer.
    var body: some View {
        #if DEBUG
        let _ = PerfCount.bump("chat")
        #endif
        ZStack(alignment: .top) {
            Theme.sky.ignoresSafeArea()
            // The list fills the whole page; the box, the arrow and what
            // rides with them float over it (messages())
            messages
            #if DEBUG
            // `-demoOlderServer`: how many older pages were fetched, for the UI test.
            if ChatModel.demoOlderServer {
                Text("\(chat.demoOlderFetches)")
                    .font(.system(size: 2))
                    .opacity(0.02)
                    .accessibilityIdentifier("olderFetches")
                    .allowsHitTesting(false)
                Text("\(chat.demoOlderPages)")
                    .font(.system(size: 2))
                    .opacity(0.02)
                    .accessibilityIdentifier("olderPages")
                    .allowsHitTesting(false)
            }
            #endif
            // A blocking "Sending photos…" (or "Telling Jarvis…") while it goes.
            if chat.uploading || chat.busy != nil {
                Color.black.opacity(0.35).ignoresSafeArea()
                VStack(spacing: 14) {
                    ProgressView().controlSize(.large).tint(Theme.frost)
                    Text(chat.busy ?? "Sending photos…").font(.headline).foregroundStyle(Theme.frost)
                }
                .padding(28)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Backing.style))
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
        // Chat is built at launch beside the other pages; it loads now only
        // if it's the page showing, else when he swipes to it, or from the
        // warm-up once Home has settled, so its first layout of every
        // message never lands mid-animation (the iPad's one 300 ms launch
        // freeze, 2026-11-20).
        .task { if app.tab == .chat { await chat.ensureLoaded(app: app) } }
        .onChange(of: pageOffScreen) { _, away in
            if !away { Task { await chat.ensureLoaded(app: app) } }
        }
        // Back in the app: a reply that finished while it was away.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { chat.loaded ? await chat.catchUp(app: app) : await chat.ensureLoaded(app: app) }
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
                RowsStack {
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
                            // In view: only a lazy list builds this row when
                            // it's reached; a full one knows by watching it.
                            .modifier(OlderRowWatch(inView: $olderInView))
                            .onChange(of: olderInView) { _, inView in if !inView { olderArmed = true } }
                            .task(id: "\(shown)-\(chat.items.count)-\(readingUp)-\(olderInView)-\(olderArmed)") {
                                guard readingUp, olderInView, olderArmed else { return }
                                try? await Task.sleep(for: .milliseconds(150))
                                guard !Task.isCancelled else { return }
                                loadOlder(scroller)
                            }
                    }
                    // A leftward drag slides the rows to show their times.
                    // The messages are the scroll targets (the "earlier" row
                    // above them is not): the list keeps the line he's reading
                    // in place by its identity when older rows are added
                    // above, in the same frame (PlaceKeeping's ScrollPosition).
                    VStack(alignment: .leading, spacing: 14) {
                        RevealTimes {
                            ChatRowsList(items: Array(chat.items.suffix(shown)), highlighted: highlighted, keptTurns: keptTurns,
                                         mealBusy: chat.busy != nil, actions: rowActions)
                                .equatable()
                        }
                    }

                    // An invisible marker after the last line: on screen
                    // means the chat is scrolled to the bottom.
                    Color.clear
                        .frame(height: 1)
                        .background(ScrollViewTap(keeper: placeKeeper))
                        .id("bottom")
                        // While Jarvis thinks, the dots sit in the gap
                        // between the last bubble and the box, taking no
                        // room of their own: his message lands just above
                        // the box and nothing moves again until the reply
                        // starts (Dylan, 2026-11-20: "it scrolls down way
                        // too much after i hit enter").
                        .overlay(alignment: .topLeading) {
                            if showDots {
                                TypingDots(label: chat.working)
                                    .fixedSize()
                                    .offset(y: -12)
                                    .transition(.opacity)
                            }
                        }
                        .animation(.easeOut(duration: 0.2), value: showDots)
                        // iOS 17 only; on 18 the scroll's own geometry decides (ReadingUpWatch).
                        .onAppear { if #unavailable(iOS 18.0) { atBottom = true } }
                        .onDisappear { if #unavailable(iOS 18.0) { atBottom = false } }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                // A readable column on an iPad, centred, the background
                // still running full width (Dylan, 2026-11-20).
                .frame(maxWidth: ChatColumn.maxWidth)
                .frame(maxWidth: .infinity)
            }
            // Opens on the newest message, like Messages, and holds its
            // distance from the bottom as rows are measured, replies grow
            // or older pages arrive on top: pinned at the newest stays
            // pinned, reading further up stays put.
            .defaultScrollAnchor(.bottom)
            .modifier(BottomAnchorOnResize())
            .modifier(PlaceKeeping(keeper: placeKeeper, rearm: { olderArmed = true }))
            // For the UI tests: the page scroller is a scroll view too now.
            .accessibilityIdentifier("chatList")
            // Nothing to show yet: message-shaped placeholders in the list's
            // place, so the page still slides in looking like Chat, then
            // the messages fade in over them once (Dylan, 2026-11-20). With
            // messages already here it never shows.
            .overlay {
                // Never an empty screen (Dylan, 2026-11-20): placeholders
                // until messages arrive, or a plain line with Retry if
                // Jarvis can't be reached (ChatScreen in JarvisKit).
                switch ChatScreen.state(hasItems: !chat.items.isEmpty, loaded: chat.loaded, failed: chat.loadFailed) {
                case .loading:
                    ChatSkeleton().transition(.opacity)
                case .failed:
                    VStack(spacing: 14) {
                        Text("Couldn't reach Jarvis.")
                            .foregroundStyle(Theme.frostDim)
                        Button("Retry") { Task { await chat.ensureLoaded(app: app) } }
                            .buttonStyle(.bordered)
                            .tint(Theme.glacier)
                            .frame(minHeight: 44)
                    }
                    .transition(.opacity)
                case .empty, .messages:
                    EmptyView()
                }
            }
            .animation(.easeOut(duration: 0.3), value: chat.loadFailed)
            .animation(.easeOut(duration: 0.3), value: chat.loaded)
            // Messages run up under the floating buttons (no bar), and
            // down under the box: the newest line clears it at the bottom.
            .contentMargins(.top, FloatingStatus.room, for: .scrollContent)
            .contentMargins(.bottom, bottomRoom, for: .scrollContent)
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
            .onChange(of: chat.items) { old, new in
                guard app.focusTurn == nil && highlighted == nil else { return }
                // Only the END of the chat matters here: older pages arriving
                // at the top, or a merge that changed nothing, leave both the
                // place and the dot alone (Dylan, 2026-11-20).
                guard NewReplyDot.endChanged(oldLastId: old.last?.id, oldLastLength: old.last?.text.count ?? 0,
                                             newLastId: new.last?.id, newLastLength: new.last?.text.count ?? 0) else { return }
                // Reading further up: stay put, and dot the arrow instead.
                guard ComposerSize.follows(atBottom: atBottom, lastIsMine: new.last?.kind == .user, sending: chat.isSending) else {
                    if NewReplyDot.lights(endChanged: true, lastIsJarvis: new.last?.kind == .jarvis, atBottom: atBottom, sending: chat.isSending) {
                        unseenReply = true
                    }
                    return
                }
                // To the marker after the last line: a reply that hasn't
                // started yet draws nothing, so its own id is no place to
                // scroll to.
                withAnimation(.easeOut(duration: 0.2)) {
                    scroller.scrollTo("bottom", anchor: .bottom)
                }
            }
            #if DEBUG
            // `-scrollChatUp` scrolls to the oldest line (simulator check of the tucked bar).
            .task {
                guard ProcessInfo.processInfo.arguments.contains("-scrollChatUp") else { return }
                try? await Task.sleep(for: .seconds(4))
                scroller.scrollTo(chat.items.suffix(shown).first?.id, anchor: .top)
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
            // The pages sit side by side in one scroller, and a lazy list
            // only draws its rows when its own scroll moves: rows that
            // arrived while Chat was off to the side were never drawn, an
            // empty Chat (Dylan, 2026-11-20). Coming on screen, it settles
            // on its newest line, unanimated, unless he's reading further up.
            .onChange(of: pageOffScreen) { _, away in
                if away {
                    // Off to another tab: back to the newest page, at the
                    // bottom, with earlier pages let go (Dylan, 2026-11-20:
                    // "when i leave the chat and come back, it should reset
                    // the view (and dont show earlier messages)"). Done
                    // while Chat is off screen, so nothing flashes.
                    guard app.focusTurn == nil, highlighted == nil else { return }
                    chat.trimToNewest()
                    var quiet = Transaction()
                    quiet.disablesAnimations = true
                    withTransaction(quiet) { shown = ChatWindow.first(total: chat.items.count) }
                    readingUp = false
                    unseenReply = false
                    olderArmed = true
                    return
                }
                guard !readingUp, app.focusTurn == nil, highlighted == nil else { return }
                settleAtNewest(scroller)
            }
            .onChange(of: chat.items.count) { old, _ in
                // The first messages, landing while Chat is off to the side.
                guard old == 0, !readingUp, app.focusTurn == nil else { return }
                settleAtNewest(scroller)
            }
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
                    .background(Backing.style, in: Capsule())
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
                            .background(Backing.style, in: Capsule())
                            .overlay(Capsule().strokeBorder(Theme.glassEdge))
                    }
                    .foregroundStyle(Theme.frost)
                    .padding(.top, FloatingStatus.room + 4)
                    .accessibilityLabel("Go to the latest messages")
                }
            }
            // The bottom of Chat floats over the list (Dylan, 2026-11-20:
            // no band, no wasted height): messages scroll on under the box
            // and the tab bar. Scrolled up with nothing typed, the box goes
            // and the round arrow sits centred in its place; with something
            // typed, the box stays and the arrow sits centred above it.
            .overlay(alignment: .bottom) {
                VStack(spacing: 10) {
                    if readingUp && !collapsed {
                        compactComposer(scroller)
                            .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    }
                    bottomChrome(scroller)
                }
                .animation(.easeOut(duration: 0.2), value: readingUp)
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
                await app.turnFound(true)
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
                await app.turnFound(false)
                if let fallback {
                    // The message isn't in the chat any more: the notice's
                    // own full text, not the bottom of Chat.
                    app.readingNotice = fallback
                }
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
        // One page per arrival at the top: the next waits until the older
        // row has left the screen, or he starts a new drag (Dylan,
        // 2026-11-20: it kept loading page after page by itself).
        olderArmed = false
        let total = chat.items.count
        #if DEBUG
        if ChatModel.demoOlderServer { chat.demoOlderPages += 1 }
        #endif
        guard ChatWindow.hasMore(shown: shown, total: total) else {
            // Everything held is drawn: ask the server for an older page.
            let anchor = chat.items.first?.id
            Task {
                await chat.loadOlder(app: app)
                var quiet = Transaction()
                quiet.disablesAnimations = true
                placeKeeper.hold()
                withTransaction(quiet) { shown = ChatWindow.grow(shown, total: chat.items.count) }
                keepPlace(at: anchor, scroller)
            }
            return
        }
        let anchor = chat.items.suffix(shown).first?.id
        var quiet = Transaction()
        quiet.disablesAnimations = true
        placeKeeper.hold()
        withTransaction(quiet) { shown = ChatWindow.grow(shown, total: total) }
        keepPlace(at: anchor, scroller)
    }

    /// Older messages arrived above: the screen stays where he left off
    /// (Dylan, 2026-11-20), and he scrolls on up to read them. On iOS 18
    /// the list already holds its distance from the bottom as content is
    /// added above (BottomAnchorOnResize), so nothing is moved, even mid-
    /// flick; scrolling the old top line back to the top, as this used to,
    /// is what made it jump. iOS 17 has no such anchor and still needs it.
    private func keepPlace(at anchor: String?, _ scroller: ScrollViewProxy) {
        if #available(iOS 18.0, *) { return }
        guard let anchor else { return }
        var quiet = Transaction()
        quiet.disablesAnimations = true
        Task { @MainActor in
            withTransaction(quiet) { scroller.scrollTo(anchor, anchor: .top) }
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
            jumpToNewest(scroller)
        } label: {
            Image(systemName: "arrow.down")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(Backing.style, in: Circle())
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
    }

    /// The Ask box and the round arrow as one piece (Dylan, 2026-11-20):
    /// scrolled up with nothing typed, the box's glass shrinks into the
    /// round arrow in place, the words fading out as the arrow fades in;
    /// back at the bottom, or on a tap, the arrow grows back into the box.
    /// The field stays laid out underneath, only faded, so its text and
    /// focus survive and the list never moves.
    private func morphingBox(_ scroller: ScrollViewProxy) -> some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        return composer
            .opacity(collapsed ? 0 : 1)
            .allowsHitTesting(!collapsed)
            .accessibilityHidden(collapsed)
            .background {
                // Frosted, so messages scrolling under it don't show through.
                shape.fill(Backing.style)
                    .background(shape.fill(Theme.glass))
                    .overlay(shape.strokeBorder(Theme.glassEdge))
                    .frame(width: collapsed ? 44 : nil, height: collapsed ? 44 : nil)
            }
            .overlay {
                Button {
                    jumpToNewest(scroller)
                } label: {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                        .overlay(alignment: .topTrailing) {
                            if unseenReply {
                                Circle().fill(OrbView.noticeOrange(onLight: false)).frame(width: 10, height: 10).offset(x: -2, y: 2)
                            }
                        }
                }
                .foregroundStyle(Theme.frost)
                .opacity(collapsed ? 1 : 0)
                .scaleEffect(collapsed || reduceMotion ? 1 : 0.6)
                .allowsHitTesting(collapsed)
                .accessibilityHidden(!collapsed)
                .accessibilityLabel(unseenReply ? "Newest message, a new reply" : "Newest message")
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 2)
            .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.86), value: collapsed)
    }

    /// The arrow (Dylan, 2026-11-20: "hit the down button whenever … even
    /// while the screen is scrolling … scroll rlly fast to the bottom"):
    /// an unanimated jump to a few messages from the end stops any flick
    /// and covers any distance at once, then the last stretch slides in
    /// over 0.3 s, so it reads as one fast move. The box comes back and
    /// the new-reply dot clears straight away.
    private func jumpToNewest(_ scroller: ScrollViewProxy) {
        Haptics.play(.jump)
        // The tap always wins: no place-keeping, no next page by itself,
        // and a flick in progress stops (Dylan, 2026-11-20, build 53).
        placeKeeper.jumpToBottom()
        olderArmed = false
        var quiet = Transaction()
        quiet.disablesAnimations = true
        let rows = Array(chat.items.suffix(shown))
        if rows.count > 8 {
            withTransaction(quiet) { scroller.scrollTo(rows[rows.count - 6].id, anchor: .bottom) }
        }
        readingUp = false
        unseenReply = false
        if reduceMotion {
            withTransaction(quiet) { scroller.scrollTo("bottom", anchor: .bottom) }
        } else {
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.3)) { scroller.scrollTo("bottom", anchor: .bottom) }
            }
        }
        // And settle exactly once the last rows are measured.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            settleAtNewest(scroller)
        }
    }

    /// Puts the list on its newest line without animation, then a few more
    /// times over the next half second: the first scroll draws the rows near
    /// the end, whose real heights only then replace the list's estimates,
    /// so the first one alone can land a few messages short.
    private func settleAtNewest(_ scroller: ScrollViewProxy) {
        var quiet = Transaction()
        quiet.disablesAnimations = true
        withTransaction(quiet) { scroller.scrollTo("bottom", anchor: .bottom) }
        // Again as the rows near the end get measured (more of them on an
        // iPad), stopping as soon as he scrolls up himself.
        Task { @MainActor in
            for wait in [60, 150, 300, 500] {
                try? await Task.sleep(for: .milliseconds(wait))
                guard !readingUp else { return }
                withTransaction(quiet) { scroller.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }

    /// The "earlier messages" row is on screen (always true for the lazy
    /// list of iOS 17, which only builds it once it's reached).
    @State private var olderInView = !RowsStackKind.full
    /// Whether reaching the top may load a page (one page per arrival).
    @State private var olderArmed = true
    /// Holds his place while older messages are added above (iOS 18).
    @State private var placeKeeper = PlaceKeeper()
    /// How far the rows are slid left to show their times (0 at rest).
    @State private var timesReveal: CGFloat = 0

    /// How much of the list's end the floating box covers, measured while
    /// it shows; never changed while he's scrolled up, so nothing jumps.
    @State private var bottomRoom: CGFloat = 64

    /// What floats at the bottom: a problem line, waiting approvals, picked
    /// photos and the Ask box. The box is always laid out and only faded
    /// (re-creating the field was where the old lag was); hidden, it can't
    /// be touched, and the list shows through where it was.
    private func bottomChrome(_ scroller: ScrollViewProxy) -> some View {
        VStack(spacing: 0) {
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
                .background(Backing.style, in: Capsule())
                .padding(.horizontal, 12)
            }
            pinnedApprovals
            if !picked.isEmpty {
                PickedStrip(photos: $picked)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            morphingBox(scroller)
        }
        .padding(.bottom, 6)
        .frame(maxWidth: ChatColumn.maxWidth)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
            // Only while the box shows (at the bottom, or typing).
            if !collapsed, abs(height - bottomRoom) > 1 { bottomRoom = height }
        }
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
                // Rich text, like the page (App/RichTextView.swift).
                RichTextView(text: item.text)
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
    /// Chat is off to the side: the dots rest.
    @Environment(\.orbOffScreen) private var offScreen

    /// The dots blink in turn unless Reduce Motion is on.
    var body: some View {
        HStack(spacing: 10) {
            TimelineView(.animation(paused: reduceMotion || offScreen)) { context in
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
                    ChatScroll.gap(contentHeight: g.contentSize.height, offsetY: g.contentOffset.y,
                                   visibleHeight: g.containerSize.height, insetTop: g.contentInsets.top)
                } action: { _, gap in
                    // Only crossings write anything, so scrolling stays cheap.
                    let next = ChatScroll.next(gap: gap, byHand: byHand, atBottom: atBottom, readingUp: readingUp)
                    if next.atBottom != atBottom { atBottom = next.atBottom }
                    if next.readingUp != readingUp { readingUp = next.readingUp }
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
            .accessibilityIdentifier("sendButton")
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

/// A day's line between messages: a hairline either side of its date.
private struct DayLine: View {
    let label: String
    var body: some View {
        HStack(spacing: 10) {
            Rectangle().fill(Color.white.opacity(0.10)).frame(height: 0.5)
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(Theme.frostFaint)
                .fixedSize()
            Rectangle().fill(Color.white.opacity(0.10)).frame(height: 0.5)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("dayLine")
    }
}

/// Messages' leftward drag (Dylan, 2026-11-20: "when i drag from right to
/// left, i should see the minute time of when the message was sent"): the
/// rows follow the finger left, up to about 68 pt with a rubber band, to
/// show each message's time; letting go springs them back. The drag is
/// read where the page swipe is (RootView), since the pager's own pan takes
/// sideways touches before anything inside Chat sees them; a mostly
/// vertical drag is the list's scroll, and a rightward one still goes back
/// to Talk. Only RevealTimes watches it, so a drag never redraws the rows.
@MainActor
final class TimesReveal: ObservableObject {
    static let shared = TimesReveal()
    /// The gap between a bubble and its time once slid in.
    static let gap: CGFloat = 8

    /// How far the rows slide: the widest time ("12:59 PM") at his text size
    /// plus the gap, so every time comes fully into view right beside its
    /// bubble (Dylan, 2026-11-21: "it doesnt drag enough").
    static var width: CGFloat {
        let font = UIFont.preferredFont(forTextStyle: .caption2)
        let digits = UIFont.monospacedDigitSystemFont(ofSize: font.pointSize, weight: .regular)
        let widest = ["12:59 PM", "10:59 AM", "11:58 PM"].map { ($0 as NSString).size(withAttributes: [.font: digits]).width }.max() ?? 52
        return ceil(widest) + gap
    }
    /// The finger's sideways travel (negative: leftward), 0 at rest.
    @Published var drag: CGFloat = 0
    /// Decided on a drag's first move: sideways-left reveals.
    var reveals: Bool?

    /// The rows' offset: the travel with a rubber band, never past the width.
    var offset: CGFloat {
        #if DEBUG
        // `-pinTimes`: held fully open (the UI test can't read the screen mid-drag).
        if ProcessInfo.processInfo.arguments.contains("-pinTimes") { return -Self.width }
        #endif
        guard drag < 0 else { return 0 }
        // With the finger all the way to the full width, then a light
        // rubber band past it.
        let d = -drag, w = Self.width
        return -(d <= w ? d : w + min(24, (d - w) * 0.2))
    }

    /// One move of a drag on Chat; true while it's revealing times.
    func moved(width w: CGFloat, height h: CGFloat) -> Bool {
        if reveals == nil, abs(w) > 8 || abs(h) > 8 {
            reveals = w < 0 && abs(w) > abs(h) * 1.4
        }
        guard reveals == true else { return false }
        var quiet = Transaction()
        quiet.disablesAnimations = true
        withTransaction(quiet) { drag = min(0, w) }
        return true
    }

    /// Let go: back they spring.
    func ended() {
        reveals = nil
        if drag != 0 { withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { drag = 0 } }
    }
}

private struct RevealTimes<Rows: View>: View {
    @ObservedObject private var reveal = TimesReveal.shared
    @ViewBuilder let rows: () -> Rows

    var body: some View {
        rows().offset(x: reveal.offset)
    }
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
        let breaks = ChatTime.dayBreaks(items.map(\.at))
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            // A light line with the day, above each day's first message.
            if breaks[index], let at = item.at {
                DayLine(label: ChatTime.dayLabel(at)).id("day-\(item.id)")
            }
            row(item)
                .frame(maxWidth: .infinity, alignment: item.kind == .user ? .trailing : .leading)
                // The time, just past the right edge: a leftward drag
                // slides it into view (RevealTimes).
                .overlay(alignment: .trailing) {
                    if let at = item.at, item.isTurn {
                        Text(ChatTime.clock(at))
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(Theme.frostFaint)
                            .fixedSize()
                            .offset(x: TimesReveal.width)
                            .accessibilityIdentifier("messageTime")
                    }
                }
                .id(item.id)
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
                        .accessibilityIdentifier("userBubble")
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
                        .accessibilityIdentifier("jarvisBubble")
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
                // Every reply flush on the same left edge, however short
                // (Dylan, 2026-11-20: short replies near the bottom sat
                // indented): the row fills the width, pinned left, as his
                // own are pinned right, instead of leaning on the list's
                // alignment, which rows added later didn't get.
                .padding(.trailing, 40)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .approval:
            // Waiting ones are pinned above the Ask box; settled ones are a
            // single line here, where they happened.
            if let line = item.outcome {
                ApprovalLine(text: line)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
    /// Chat is off to the side: the shimmer rests.
    @Environment(\.orbOffScreen) private var offScreen
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
            .opacity(reduceMotion || offScreen ? 0.8 : (lit ? 1 : 0.55))
        }
        .allowsHitTesting(false)
        .onAppear { shimmer(!offScreen) }
        .onChange(of: offScreen) { _, away in shimmer(!away) }
        .accessibilityElement()
        .accessibilityLabel("Loading chat")
    }

    /// Starts the soft pulse, or stops it dead (no animation left running).
    private func shimmer(_ on: Bool) {
        guard on, !reduceMotion else {
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) { lit = false }
            return
        }
        withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { lit = true }
    }
}

/// How wide Chat's messages and box get: a readable line on an iPad; an
/// iPhone is narrower than this anyway.
enum ChatColumn {
    static let maxWidth: CGFloat = 760
}

/// Keeps the chat's distance from its bottom when its content changes size
/// (iOS 18 and up; 17 keeps the plain bottom anchor).
/// Keeps his place while older messages are added above (Dylan,
/// 2026-11-20: after "Loading earlier messages" he landed at the top of the
/// new batch, which loaded the next, and the next). Just before the rows
/// grow, `hold()` notes how far down he is and how tall the content was;
/// when the content grows, the list is moved down by exactly what was
/// added, so the message he was reading stays put and the new ones sit
/// above the screen. Whether or not iOS's own bottom anchor already did it,
/// this lands in the same place. iOS 18 and up.
final class PlaceKeeper {
    fileprivate var y: CGFloat = 0
    fileprivate var height: CGFloat = 0
    fileprivate var held: (y: CGFloat, height: CGFloat)?
    /// The list's own scroll view, found once (ScrollViewTap): its content
    /// size is watched as UIKit lays it out, so the correction lands in the
    /// same layout pass as the new rows, before anything is drawn. Without
    /// it (not found), the correction above runs a frame later.
    fileprivate weak var scrollView: UIScrollView?
    private var watch: NSKeyValueObservation?
    private var lastHeight: CGFloat = 0

    fileprivate func attach(_ view: UIScrollView) {
        guard scrollView !== view else { return }
        scrollView = view
        lastHeight = view.contentSize.height
        watch = view.observe(\.contentSize, options: [.new]) { [weak self] view, _ in
            MainActor.assumeIsolated { self?.sizeChanged(view) }
        }
    }

    /// Older rows went in above: move down by exactly what was added, so
    /// what he's reading doesn't move. Only right after hold().
    @MainActor private func sizeChanged(_ view: UIScrollView) {
        let height = view.contentSize.height
        defer { lastHeight = height }
        guard let held, height > lastHeight + 1 else { return }
        self.held = nil
        let added = height - held.height
        let target = held.y + added
        if abs(view.contentOffset.y - target) > 0.5 {
            view.setContentOffset(CGPoint(x: view.contentOffset.x, y: target), animated: false)
        }
    }
    /// Set while the arrow's jump to the newest runs: a page landing then
    /// doesn't move the view (the jump ends at the bottom regardless).
    fileprivate var jumpingUntil = Date.distantPast
    /// Moves the list to its very bottom at once (set by PlaceKeeping).
    fileprivate var toBottom: (() -> Void)?

    /// The arrow: drop any place-keeping and go to the bottom now,
    /// stopping a flick in progress.
    func jumpToBottom() {
        held = nil
        jumpingUntil = Date().addingTimeInterval(1.2)
        toBottom?()
    }

    func hold() {
        guard Date() > jumpingUntil else { return }
        if let view = scrollView {
            // Stop any glide first, so the place he's at is the place kept.
            view.setContentOffset(view.contentOffset, animated: false)
            held = (view.contentOffset.y, view.contentSize.height)
            lastHeight = view.contentSize.height
        } else {
            held = (y, height)
        }
        // Nothing grew after all (a page with nothing new): let it go.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.held = nil }
    }
}

private struct PlaceKeeping: ViewModifier {
    let keeper: PlaceKeeper
    /// A new drag by him may load the next page.
    let rearm: () -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.modifier(Keep(keeper: keeper, rearm: rearm))
        } else {
            content
        }
    }

    @available(iOS 18.0, *)
    private struct Keep: ViewModifier {
        let keeper: PlaceKeeper
        let rearm: () -> Void
        @State private var position = ScrollPosition()

        func body(content: Content) -> some View {
            let binding = $position
            keeper.toBottom = {
                var quiet = Transaction()
                quiet.disablesAnimations = true
                withTransaction(quiet) { binding.wrappedValue.scrollTo(edge: .bottom) }
            }
            return content
                .scrollPosition($position)
                .onScrollPhaseChange { old, new in
                    if new == .interacting && old != .interacting { rearm() }
                }
                // Noted on every change, written nowhere: scrolling stays cheap.
                .onScrollGeometryChange(for: CGSize.self) { g in
                    CGSize(width: g.contentOffset.y, height: g.contentSize.height)
                } action: { _, now in
                    keeper.y = now.width
                    if Date() < keeper.jumpingUntil { keeper.held = nil }
                    if keeper.scrollView == nil, let held = keeper.held, now.height > held.height + 1 {
                        keeper.held = nil
                        let target = held.y + (now.height - held.height)
                        if abs(target - now.width) > 1 {
                            var quiet = Transaction()
                            quiet.disablesAnimations = true
                            withTransaction(quiet) { position.scrollTo(y: target) }
                        }
                    }
                    keeper.height = now.height
                }
        }
    }
}

/// Finds the chat list's UIScrollView from inside its content and hands it
/// to the PlaceKeeper (a zero-size view; draws nothing).
private struct ScrollViewTap: UIViewRepresentable {
    let keeper: PlaceKeeper
    func makeUIView(context: Context) -> UIView { Finder(keeper: keeper) }
    func updateUIView(_ view: UIView, context: Context) {}

    final class Finder: UIView {
        let keeper: PlaceKeeper
        init(keeper: PlaceKeeper) { self.keeper = keeper; super.init(frame: .zero); isUserInteractionEnabled = false }
        required init?(coder: NSCoder) { fatalError() }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            var view = superview
            while let v = view, !(v is UIScrollView) { view = v.superview }
            if let scroll = view as? UIScrollView { keeper.attach(scroll) }
        }
    }
}

private struct BottomAnchorOnResize: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.defaultScrollAnchor(.bottom, for: .sizeChanges)
        } else {
            content
        }
    }
}

/// Chat's rows. On iOS 18 and later, a plain stack: every loaded row is laid
/// out when it changes, never while scrolling (Dylan, 2026-11-20). The lazy
/// list it replaces only built rows when its own scroll moved, so messages
/// that arrived while Chat sat off to the side could stay undrawn, an empty
/// Chat, and it built rows mid-scroll, the iPad's scroll hitches. Chat only
/// holds its loaded window (ChatWindow), so this stays affordable. iOS 17
/// keeps the lazy list.
enum RowsStackKind {
    /// A full stack (iOS 18 and up) rather than a lazy one.
    static var full: Bool {
        if #available(iOS 18.0, *) { return true }
        return false
    }
}

struct RowsStack<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        if #available(iOS 18.0, *) {
            VStack(alignment: .leading, spacing: 14, content: content)
        } else {
            LazyVStack(alignment: .leading, spacing: 14, content: content)
        }
    }
}

/// Whether the "earlier messages" row is scrolled into view (iOS 18 and up).
private struct OlderRowWatch: ViewModifier {
    @Binding var inView: Bool

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollVisibilityChange(threshold: 0.05) { visible in
                if inView != visible { inView = visible }
            }
        } else {
            content
        }
    }
}
