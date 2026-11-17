// Jarvis for iPhone and iPad: a front end for the Jarvis running on the
// lab PC, reached over Tailscale. The brain, tools and approvals stay on
// the PC.
import SwiftUI

@main
struct JarvisApp: App {
    @StateObject private var app = AppModel()

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
    }
}

/// Chat, Talk and Today as tabs, with the Settings sheet over them.
struct RootView: View {
    @EnvironmentObject private var app: AppModel

    /// The tab bar; each tab draws its own status line instead of a big title
    /// (Dylan, 2026-11-16: no "Chat"/"Talk" headings).
    var body: some View {
        TabView(selection: $app.tab) {
            ChatView(chat: app.chat)
                .tabItem { Label("Chat", systemImage: "bubble.left") }
                .badge(app.chat.pendingCount)
                .tag(AppTab.chat)
            TalkView(talk: app.talk)
                .tabItem { Label("Talk", systemImage: "waveform") }
                .tag(AppTab.talk)
            TodayView(today: app.today)
                .tabItem { Label("Today", systemImage: "calendar") }
                .tag(AppTab.today)
        }
        .sheet(isPresented: $app.showSettings) {
            SettingsView()
        }
        // Opening Talk the first time starts the call, like the page's /talk.
        .onChange(of: app.tab) { _, tab in
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
