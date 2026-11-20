// Jarvis for iPhone and iPad: a front end for the Jarvis running on the
// lab PC, reached over Tailscale. The brain, tools and approvals stay on
// the PC.
import SwiftUI
import UserNotifications
import JarvisKit

@main
struct JarvisApp: App {
    /// Keeps the iPhone's tabs portrait and lets the bedside kiosk turn sideways.
    @UIApplicationDelegateAdaptor(OrientationLock.self) private var orientation
    @StateObject private var app = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    /// Starts the Watch bridge, so the Watch can ask Jarvis through this phone.
    init() {
        WatchBridge.shared.start()
    }

    /// One window: the tabs, over the night sky, always dark like the page.
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .preferredColorScheme(.dark)
                .tint(Theme.glacier)
        }
        // Money hides again the moment the app leaves the screen.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .background else { return }
            app.lockMoney()
            // Paused (dozing) and leaving the app: hang up, so the mic goes
            // off. A live call keeps going in the background, mic on
            // (Dylan, 2026-11-17).
            if app.talk.phase == .on(.dozing) { app.talk.hangUp() }
        }
    }
}

/// Chat, Talk and Today as pages, with the Settings sheet over them.
///
/// The pages are a paging TabView rather than a tab-bar one (Dylan,
/// 2026-11-17: tab changes must glide). A swipe follows the finger and
/// springs to the next page; tapping the bar slides there the same way.
/// The bar is drawn here, on glass, since a paging TabView has none.
struct RootView: View {
    @EnvironmentObject private var app: AppModel
    /// The iPhone's bedside kiosk: up while sideways and charging.
    @StateObject private var bedside = PhoneKioskMonitor()
    /// Whether the keyboard is up.
    @StateObject private var keyboard = KeyboardWatch()
    /// One page, with room for the tab bar.
    private func page<Page: View>(_ content: Page, _ screen: GeometryProxy) -> some View {
        content
            .roomForTabBar()
    }

    /// The last touch on the bar, tab change or scroll up.
    @State private var barTouched: Date?
    /// True while the page is being scrolled down (the bar tucks away).
    @State private var scrollingDown = false
    /// Whether the bar is full size right now (JarvisKit TabBarSize).
    @State private var barExpanded = false
    /// Shrinks the bar two seconds after the last use.
    @State private var barTimer: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The bar was touched or a tab changed: open it, and shrink it again
    /// two seconds later.
    private func touchBar() {
        barTouched = Date()
        scrollingDown = false
        settleBar()
        barTimer?.cancel()
        barTimer = Task {
            try? await Task.sleep(for: .seconds(TabBarSize.holdSeconds + 0.05))
            guard !Task.isCancelled else { return }
            settleBar()
        }
    }

    /// A page scrolled: down tucks the bar away at once, up opens it.
    private func barScrolled(_ delta: Double) {
        guard let down = TabBarSize.isScrollDown(delta) else { return }
        // Called on every frame of a scroll: only touches state when
        // something actually changes.
        if down {
            if !scrollingDown { scrollingDown = true }
            settleBar()
        } else if scrollingDown || !barExpanded {
            touchBar()
        }
    }

    /// Sets the bar's size from the rule, with a spring (a quick fade
    /// with Reduce Motion).
    private func settleBar() {
        let open = TabBarSize.expanded(lastInteraction: barTouched, scrollingDown: scrollingDown, onTalk: app.tab == .talk)
        guard open != barExpanded else { return }
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.85)) { barExpanded = open }
    }


    /// Each page draws its own status line instead of a big title
    /// (Dylan, 2026-11-16: no "Chat"/"Talk" headings).
    var body: some View {
        #if DEBUG
        let _ = PerfCount.bump("root")
        #endif
        // The page swiper runs to the screen's very top and bottom (Dylan,
        // 2026-11-19: on the iPhone 17 Pro the app "stops early … like a
        // horizontal line"): a paging TabView clips its pages to the safe
        // area, so the pages' own backgrounds and scrolling stopped short of
        // the edges. It now ignores the container safe area; the pages still
        // see the real insets, so content clears the Dynamic Island and the
        // home indicator while backgrounds and scrolling reach the edges.
        // The keyboard rule is untouched.
        GeometryReader { screen in
            TabView(selection: $app.tab) {
                // Home, Talk, Chat, left to right (AppTab's order).
                page(TodayView(today: app.today), screen).tag(AppTab.today)
                page(TalkView(talk: app.talk), screen)
                    .environment(\.orbOffScreen, app.tab != .talk)
                    .tag(AppTab.talk)
                // Chat keeps the same fixed room as every page. Build 19 let
                // it follow the bar's size, and that looped on 2026-11-19:
                // the bar shrinking moved Chat's content, which read as a
                // scroll, which moved the bar, until the app froze.
                page(ChatView(chat: app.chat), screen).tag(AppTab.chat)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea(.container, edges: .vertical)
        }
        // The keyboard goes as soon as a page swipe starts, not only once
        // the next page has landed.
        .simultaneousGesture(DragGesture(minimumDistance: PageSwipe.minDistance).onChanged { drag in
            if keyboard.up, PageSwipe.isSideways(width: drag.translation.width, height: drag.translation.height) {
                KeyboardWatch.dismiss()
            }
        })
        .background(Theme.sky.ignoresSafeArea())
        // The bar floats over the pages; each page keeps room for it, so
        // lists scroll up from under it and buttons sit above it.
        // The keyboard covers the bar rather than lifting it (Dylan,
        // 2026-11-18): it stays at the bottom, out of sight while typing.
        .overlay(alignment: .bottom) {
            TabBar(tab: $app.tab, chatBadge: app.chat.pendingCount, expanded: barExpanded) { touchBar() }
                .opacity(keyboard.up ? 0 : 1)
                .allowsHitTesting(!keyboard.up)
                .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .environmentObject(keyboard)
        // Pages report their scrolling so the bar can shrink or open.
        .environment(\.tabBarScroll, TabBarScroll { delta in barScrolled(delta) })
        .modifier(PadKioskAndNotices(app: app))
        .fullScreenCover(isPresented: Binding(get: { bedside.showing }, set: { if !$0 { bedside.dismiss() } })) {
            PhoneKioskView(today: app.today, talk: app.talk, app: app) { bedside.dismiss() }
        }
        // Rotating upright or unplugging mid-call hands the call to the Talk
        // tab rather than dropping it.
        .onChange(of: bedside.showing) { _, showing in
            if !showing, PhoneKiosk.handOverToTalk(callLive: app.talk.phase != .off) { app.tab = .talk }
        }
        .onAppear { bedside.start() }
        // The Settings switch can turn it on or off at any time.
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in bedside.update() }
        // A notice read in full: one whose message isn't in Chat any more,
        // or one with no message at all.
        .sheet(item: $app.readingNotice) { notice in
            NoticeDetail(notice: notice).environmentObject(app)
        }
        .sheet(isPresented: $app.showSettings) {
            SettingsView()
        }
        // The snapshot (Today, and the orb's dots) refreshes every 15 s,
        // whichever page is showing, and every 5 s while an orange dot is up
        // so a notice read on another device fades here soon after.
        .task {
            while !Task.isCancelled {
                await app.today.load(app: app)
                try? await Task.sleep(for: .seconds(Orbit.refreshSeconds(orangeShowing: !app.notices.isEmpty)))
            }
        }
        // `-perfCycle`: a measuring run for Instruments, launched only by a
        // developer (nothing a user can reach): switches tabs and scrolls
        // Chat for a while, never calling Talk.
        .task {
            guard ProcessInfo.processInfo.arguments.contains("-perfCycle") else { return }
            app.talk.started = true
            try? await Task.sleep(for: .seconds(4))
            let order: [AppTab] = [.talk, .chat, .talk, .today]
            for round in 0..<6 {
                for tab in order {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) { app.tab = tab }
                    try? await Task.sleep(for: .seconds(0.9))
                    if tab == .chat {
                        NotificationCenter.default.post(name: .perfScroll, object: round % 2 == 0 ? "top" : "bottom")
                        try? await Task.sleep(for: .seconds(1.5))
                    }
                }
            }
        }
        // If the app ever opens on Talk the call starts with it; onChange
        // below only sees later switches. (It opens on Home now.)
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-demoIsland") { app.talk.demoIsland(); return }
            // `-openReport <id>` starts on Home with that report open.
            let args = ProcessInfo.processInfo.arguments
            if let at = args.firstIndex(of: "-openReport"), at + 1 < args.count {
                app.tab = .today
                await app.today.load(app: app)
                await app.openReport(id: args[at + 1])
                return
            }
            // `-focusMissingNotice` taps the first notice whose turn isn't
            // in the chat (the "no longer in history" check).
            if args.contains("-focusMissingNotice") {
                try? await Task.sleep(for: .seconds(3))
                if let notice = app.notices.first(where: { $0.turnId != nil }) {
                    await app.openTurn(99_999, about: notice)
                }
                return
            }
            // `-onTalkQuiet` opens on Talk without calling Jarvis (layout checks).
            if args.contains("-onTalkQuiet") {
                app.talk.started = true
                app.tab = .talk
                return
            }
            if args.contains("-onHome") {
                app.tab = .today
                // `-openNoticesSheet` opens the drawer (simulator checks).
                if args.contains("-openNoticesSheet") { try? await Task.sleep(for: .seconds(4)); app.showNotices = true }
                return
            }
            // `-focusTurn long|short` opens Chat on a long or short message
            // the way a tapped notice does, to check its glow.
            if let at = args.firstIndex(of: "-focusTurn"), at + 1 < args.count {
                app.tab = .chat
                await app.chat.load(app: app)
                let jarvis = app.chat.items.filter { $0.kind == .jarvis && $0.turnId != nil && !$0.text.isEmpty }
                let pick = args[at + 1] == "long" ? jarvis.max { $0.text.count < $1.text.count } : jarvis.filter { $0.text.count < 80 }.last
                try? await Task.sleep(for: .seconds(1))
                app.focusTurn = pick?.turnId
                return
            }
            // `-openChat` starts on Chat (simulator checks; no mic there).
            if ProcessInfo.processInfo.arguments.contains("-openChat") {
                app.tab = .chat
                // `-thenHome` changes page a few seconds later, to check the
                // keyboard goes with it.
                if ProcessInfo.processInfo.arguments.contains("-thenHome") {
                    try? await Task.sleep(for: .seconds(6))
                    app.tab = .today
                }
                return
            }
            #endif
        }
        // Talk never calls Jarvis by itself (Dylan, 2026-11-20: "we
        // shouldn't call jarvis by default. A button should be clicked"):
        // arriving on the page only shows the orb and the Talk button
        // (JarvisKit TalkStart). Landing there used to set up the call,
        // audio and microphone right on the page swipe.
        .onChange(of: app.tab) { _, _ in
            touchBar()
            // Swiping or tapping to another page puts the keyboard away.
            KeyboardWatch.dismiss()
        }
    }
}

/// The thin line at the top of every screen: whether the PC is reachable,
/// and the gear for Settings.
struct StatusLine: View {
    @EnvironmentObject private var app: AppModel

    /// "On Tailscale · jarvis" in green, "Can't reach Jarvis" in rose, or
    /// "Connecting…" before the first answer.
    var body: some View {
        HStack(spacing: 12) {
            // Tailscale and Jarvis, a dot and a word or two each (JarvisKit
            // ConnectionStatus); the words change when something's wrong.
            // Narrow screens drop words, never wrap: Tailscale's word goes
            // first (its dot stays), then both words but the one that's wrong.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    light(status.tailnet, status.tailnetWords)
                    light(status.jarvis, status.jarvisWords)
                }
                HStack(spacing: 8) {
                    light(status.tailnet, status.tailnet == .good ? nil : status.tailnetWords)
                    light(status.jarvis, status.tailnet == .good ? status.jarvisWords : nil)
                }
                HStack(spacing: 8) {
                    light(status.tailnet, status.tailnet == .good ? nil : status.tailnetWords)
                    light(status.jarvis, status.jarvis == .waiting ? "Restarting" : nil)
                }
            }
            .lineLimit(1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(status.spoken)
            Spacer()
            // The notices: one dot and a count, when any.
            if let status = Notices.statusButton(unread: app.notices, running: running.count) {
                Button {
                    app.showNotices = true
                } label: {
                    HStack(spacing: 6) {
                        // One orange dot for anything new (its shade the
                        // most urgent one's), and a blue one beside it while
                        // Jarvis is working on something (Dylan, 2026-11-19).
                        if let kind = status.orange {
                            Circle().fill(pipColor(kind)).frame(width: 7, height: 7)
                        }
                        if status.blue {
                            Circle().fill(OrbView.taskBlue(onLight: false)).frame(width: 7, height: 7)
                        }
                        Text(status.words)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.frost)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(Capsule().fill(Theme.glass))
                    .overlay(Capsule().strokeBorder(Theme.glassEdge))
                }
                .accessibilityLabel("\(app.notices.count) unread notices, \(running.count) running")
                .transition(.scale.combined(with: .opacity))
            }
            Button {
                app.showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Theme.glass))
                    .overlay(Circle().strokeBorder(Theme.glassEdge))
            }
            .foregroundStyle(Theme.frost)
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .animation(.smooth, value: app.notices.count)
        // Pulling down on the status row opens the notices.
        .contentShape(Rectangle())
        .simultaneousGesture(DragGesture(minimumDistance: 24).onEnded { drag in
            if drag.translation.height > 40 && abs(drag.translation.width) < drag.translation.height { app.showNotices = true }
        })
    }

    /// What Jarvis is working on right now.
    private var running: [RunningTask] {
        app.today.snapshot?.jobs?.running ?? []
    }

    /// Notices are orange (Dylan, 2026-11-18); one that needs him brightest.
    private func pipColor(_ kind: NoticeKind) -> Color {
        OrbView.noticeOrange(onLight: false).opacity(kind == .need ? 1 : kind == .heads ? 0.85 : 0.7)
    }

    /// The dot's colour for the connection state.
    private var status: ConnectionStatus {
        #if DEBUG
        // `-statusState ok|restarting|offline`: those top lines in the simulator.
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-statusState"), i + 1 < args.count {
            switch args[i + 1] {
            case "offline": return .of(reachable: false, jarvisRestarting: false)
            case "restarting": return .of(reachable: true, jarvisRestarting: true)
            default: return .of(reachable: true, jarvisRestarting: false)
            }
        }
        #endif
        return .of(reachable: app.reachable, jarvisRestarting: app.jarvisRestarting)
    }

    /// One state: its dot and its words.
    private func light(_ light: ConnectionStatus.Light, _ words: String?) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color(light)).frame(width: 7, height: 7)
            if let words {
                Text(words)
                    .font(.footnote)
                    .foregroundStyle(light == .bad ? Theme.rose : light == .waiting ? Theme.ember : Theme.frostDim)
                    .fixedSize()
            }
        }
    }

    private func color(_ light: ConnectionStatus.Light) -> Color {
        switch light {
        case .good: return Theme.moss
        case .waiting: return Theme.ember
        case .bad: return Theme.rose
        case .unknown: return Theme.frostFaint
        }
    }
}

/// The bar along the bottom: Chat, Talk and Today on a glass capsule, the
/// current one lit. Tapping slides to that page with the same spring a
/// swipe uses.
struct TabBar: View {
    @Binding var tab: AppTab
    var chatBadge: Int
    /// Full size (icons and labels) while in use; compact icons at rest.
    var expanded = true
    /// A touch on the bar (it opens while used).
    var onTouch: () -> Void = {}

    var body: some View {
        HStack(spacing: expanded ? 4 : 2) {
            // Home, Talk, Chat (Dylan, 2026-11-18); "Home" on iPhone and
            // iPad alike (2026-11-17).
            item(.today, "Home", "square.grid.2x2.fill", badge: 0)
            item(.talk, "Talk", "waveform", badge: 0)
            item(.chat, "Chat", "bubble.left.fill", badge: chatBadge)
        }
        .padding(expanded ? 5 : 3)
        .glassPanel(radius: 32)
        // A compact pill on iPad too; narrower and lower while resting.
        .frame(maxWidth: expanded ? 420 : 200)
        .padding(.horizontal, 40)
        .padding(.bottom, expanded ? 6 : 0)
        .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in onTouch() })
    }

    /// One tab: symbol over label (the label only while open), a soft pill
    /// behind the current one. One tap switches, open or not.
    private func item(_ target: AppTab, _ title: String, _ symbol: String, badge: Int) -> some View {
        let on = tab == target
        return Button {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) { tab = target }
        } label: {
            VStack(spacing: 3) {
                // Drawn at one size and scaled. Animating the symbol's point
                // size made SwiftUI re-interpolate the glyph's paths on every
                // frame of the bar's spring, and on 2026-11-19 a swipe from
                // Home to Talk hung the main thread there for 10 s until the
                // watchdog killed the app. A scale is just a transform.
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .semibold))
                    .scaleEffect(expanded ? 1 : 17.0 / 19.0)
                    .overlay(alignment: .topTrailing) {
                        if badge > 0 {
                            Text("\(badge)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .background(Capsule().fill(Theme.rose))
                                .offset(x: 10, y: -6)
                        }
                    }
                // Always laid out and faded in place, so on a shrink the word
                // fades inside the bar instead of sliding off to a corner
                // (Dylan, 2026-11-19).
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .fixedSize()
                    .opacity(expanded ? 1 : 0)
                    .frame(height: expanded ? 14 : 0, alignment: .top)
                    .clipped()
            }
            .foregroundStyle(on ? Theme.glacier : Theme.frostDim)
            .frame(maxWidth: .infinity, minHeight: expanded ? 50 : 44)
            .clipShape(Capsule())
            .background {
                if on {
                    Capsule().fill(Color.white.opacity(0.10))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// How a page tells the tab bar it scrolled (points; positive = reading
/// further down).
struct TabBarScroll {
    var report: (Double) -> Void = { _ in }
}

private struct TabBarScrollKey: EnvironmentKey {
    static let defaultValue = TabBarScroll()
}

extension EnvironmentValues {
    var tabBarScroll: TabBarScroll {
        get { self[TabBarScrollKey.self] }
        set { self[TabBarScrollKey.self] = newValue }
    }
}

extension View {
    /// Reports this scroll view's movement to the tab bar (iOS 18 and up;
    /// on 17 the bar just follows touches and tab changes).
    @ViewBuilder
    func reportsScrollToTabBar() -> some View {
        if #available(iOS 18.0, *) {
            modifier(ScrollReporter())
        } else {
            self
        }
    }
}

@available(iOS 18.0, *)
private struct ScrollReporter: ViewModifier {
    @Environment(\.tabBarScroll) private var scroll

    /// Only his own scrolling counts. Content moving because a page's
    /// room or its text changed must never move the bar, or the two can
    /// chase each other forever (the 2026-11-19 freeze).
    @State private var byHand = false

    func body(content: Content) -> some View {
        content
            .onScrollPhaseChange { _, phase in
                byHand = phase == .interacting || phase == .decelerating
            }
            .onScrollGeometryChange(for: Double.self) { geometry in
                geometry.contentOffset.y
            } action: { old, new in
                if byHand { scroll.report(new - old) }
            }
    }
}

extension View {
    /// Keeps a page's content clear of the floating tab bar. While the
    /// keyboard is up the bar is hidden under it, so no gap is kept.
    func roomForTabBar() -> some View {
        modifier(RoomForTabBar())
    }
}

/// The space under a page for the tab bar, none while typing.
/// The space under a page for the tab bar, none while typing. Fixed:
/// it must never follow the bar's size (see the Chat page above).
private struct RoomForTabBar: ViewModifier {
    @EnvironmentObject private var keyboard: KeyboardWatch

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: keyboard.up ? 0 : 66) }
    }
}

/// Follows the keyboard coming up and going away.
@MainActor
final class KeyboardWatch: ObservableObject {
    @Published private(set) var up = false
    private var observers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.up = true }
        })
        observers.append(center.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.up = false }
        })
    }

    /// Puts the keyboard away, whichever field has it.
    static func dismiss() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

/// The iPad's kiosk and the notices sheet, each presented from its own
/// background view (two sheets on one view clash), plus the iPad's idle
/// clock: any touch, keystroke or tab change restarts its five minutes.
struct PadKioskAndNotices: ViewModifier {
    @ObservedObject var app: AppModel

    func body(content: Content) -> some View {
        content
            .background {
                Color.clear.fullScreenCover(isPresented: $app.padKiosk) {
                    KioskView(today: app.today, chat: app.chat, talk: app.talk)
                        .environmentObject(app)
                }
            }
            .background {
                Color.clear.sheet(isPresented: $app.showNotices) {
                    NoticesSheet().environmentObject(app)
                }
            }
            // A report from Jarvis, in the app's own reader.
            .background {
                Color.clear.sheet(item: $app.report) { page in
                    ReportReader(page: page).environmentObject(app)
                }
            }
            // A link to one of Jarvis's reports (chat's "Open the report")
            // opens in the reader; every other link opens as it always has.
            .environment(\.openURL, OpenURLAction { url in
                guard let id = Reports.id(in: url, base: app.client.base) else { return .systemAction }
                Task { await app.openReport(id: id) }
                return .handled
            })
            .simultaneousGesture(TapGesture().onEnded { app.noteActivity() })
            .simultaneousGesture(DragGesture(minimumDistance: 4).onChanged { _ in app.noteActivity() })
            .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidChangeNotification)) { _ in app.noteActivity() }
            .onReceive(NotificationCenter.default.publisher(for: UITextView.textDidChangeNotification)) { _ in app.noteActivity() }
            .onChange(of: app.tab) { _, _ in app.noteActivity() }
            // The sensible moment to ask about notifications: the first time
            // a notice actually turns up.
            .onChange(of: app.notices.isEmpty) { _, empty in
                if !empty { Task { await PushCenter.shared.askIfNeeded() } }
            }
            // The app badge is the unread count, set here after every
            // snapshot and clear (clearing sends no badge push).
            .onChange(of: app.notices.count) { _, count in
                UNUserNotificationCenter.current().setBadgeCount(count)
            }
            .task {
                guard UIDevice.current.userInterfaceIdiom == .pad else { return }
                UIDevice.current.isBatteryMonitoringEnabled = true
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(15))
                    app.checkIdleKiosk()
                }
            }
    }
}

