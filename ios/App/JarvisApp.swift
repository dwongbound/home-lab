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

    /// Each page draws its own status line instead of a big title
    /// (Dylan, 2026-11-16: no "Chat"/"Talk" headings).
    var body: some View {
        TabView(selection: $app.tab) {
            // Home, Talk, Chat, left to right (AppTab's order).
            TodayView(today: app.today)
                .roomForTabBar()
                .tag(AppTab.today)
            TalkView(talk: app.talk)
                .roomForTabBar()
                .tag(AppTab.talk)
            ChatView(chat: app.chat)
                .roomForTabBar()
                .tag(AppTab.chat)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
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
            TabBar(tab: $app.tab, chatBadge: app.chat.pendingCount)
                .opacity(keyboard.up ? 0 : 1)
                .allowsHitTesting(!keyboard.up)
                .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .environmentObject(keyboard)
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
            if args.contains("-onHome") { app.tab = .today; return }
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
            if app.tab == .talk && !app.talk.started {
                await app.talk.start(app: app)
            }
        }
        // Opening Talk the first time starts the call, like the page's /talk.
        .onChange(of: app.tab) { _, tab in
            // Swiping or tapping to another page puts the keyboard away.
            KeyboardWatch.dismiss()
            if tab == .talk && !app.talk.started {
                Task { await app.talk.start(app: app) }
            }
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
            HStack(spacing: 6) {
                Circle().fill(dotColor).frame(width: 8, height: 8)
                Text(words)
                    .font(.footnote)
                    .foregroundStyle(Theme.frostDim)
            }
            Spacer()
            // The notices: one dot and a count, when any.
            if !app.notices.isEmpty {
                Button {
                    app.showNotices = true
                } label: {
                    HStack(spacing: 6) {
                        // One orange dot however many there are (Dylan,
                        // 2026-11-19); its shade is the most urgent one's.
                        if let kind = Notices.headerDot(app.notices) {
                            Circle().fill(pipColor(kind)).frame(width: 7, height: 7)
                        }
                        Text(Notices.countLabel(app.notices) ?? "")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.frost)
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(Capsule().fill(Theme.glass))
                    .overlay(Capsule().strokeBorder(Theme.glassEdge))
                }
                .accessibilityLabel("\(app.notices.count) unread notices")
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

    /// Notices are orange (Dylan, 2026-11-18); one that needs him brightest.
    private func pipColor(_ kind: NoticeKind) -> Color {
        OrbView.noticeOrange(onLight: false).opacity(kind == .need ? 1 : kind == .heads ? 0.85 : 0.7)
    }

    /// The dot's colour for the connection state.
    private var dotColor: Color {
        switch app.reachable {
        case .some(true): return Theme.moss
        case .some(false): return Theme.rose
        case .none: return Theme.frostFaint
        }
    }

    /// The status words for the connection state.
    private var words: String {
        switch app.reachable {
        case .some(true): return "On Tailscale · jarvis"
        case .some(false): return "Can’t reach Jarvis. Is Tailscale on?"
        case .none: return "Connecting…"
        }
    }
}

/// The bar along the bottom: Chat, Talk and Today on a glass capsule, the
/// current one lit. Tapping slides to that page with the same spring a
/// swipe uses.
struct TabBar: View {
    @Binding var tab: AppTab
    var chatBadge: Int

    var body: some View {
        HStack(spacing: 4) {
            // Home, Talk, Chat (Dylan, 2026-11-18); "Home" on iPhone and
            // iPad alike (2026-11-17).
            item(.today, "Home", "square.grid.2x2.fill", badge: 0)
            item(.talk, "Talk", "waveform", badge: 0)
            item(.chat, "Chat", "bubble.left.fill", badge: chatBadge)
        }
        .padding(5)
        .glassPanel(radius: 32)
        // A compact pill on iPad too, not a bar across the whole screen.
        .frame(maxWidth: 420)
        .padding(.horizontal, 40)
        .padding(.bottom, 6)
    }

    /// One tab: symbol over label, a soft pill behind the current one.
    private func item(_ target: AppTab, _ title: String, _ symbol: String, badge: Int) -> some View {
        let on = tab == target
        return Button {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) { tab = target }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .semibold))
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
                Text(title).font(.caption2.weight(.semibold))
            }
            .foregroundStyle(on ? Theme.glacier : Theme.frostDim)
            .frame(maxWidth: .infinity, minHeight: 50)
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

extension View {
    /// Keeps a page's content clear of the floating tab bar. While the
    /// keyboard is up the bar is hidden under it, so no gap is kept.
    func roomForTabBar() -> some View {
        modifier(RoomForTabBar())
    }
}

/// The space under a page for the tab bar, none while typing.
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

