// Jarvis on Apple TV: the always-on display. A big orb, the time, the
// weather and the sun on the left; on the right one roomy panel at a time
// (what's next, the house, his work, health, his suggestions) cross-fading
// every 20 s, with anything pressing above it (KioskPlan, shared with the
// iPad kiosk). Refreshes every 15 s like the page, and keeps the TV from
// dimming while it's open. Reaches the PC over Tailscale's Apple TV app,
// the same front door as the phone. Read-only: nothing here acts.
import SwiftUI
import UIKit
import JarvisKit

@main
struct JarvisTVApp: App {
    /// One screen, always dark.
    var body: some Scene {
        WindowGroup {
            AlwaysOnView()
                .preferredColorScheme(.dark)
        }
    }
}

@MainActor
final class AlwaysOnModel: ObservableObject {
    @Published private(set) var snapshot: Snapshot?
    /// nil until the first answer; then whether the PC answered last time.
    @Published private(set) var reachable: Bool?
    /// How many approvals are waiting: a count for the chip, never what.
    @Published private(set) var approvals = 0
    private let client = JarvisClient()

    /// The banner showing for new notices, if any (TVBanner in JarvisKit).
    @Published var banner: BannerShow?
    /// The notices this TV has already seen; nil until the first snapshot,
    /// so what was waiting at launch never banners.
    private var seen: Set<String>?
    /// True while the night view is up: only notices that need Dylan banner.
    var night = false

    /// Notices cleared here, hidden at once until the snapshot drops them.
    @Published private(set) var cleared: Set<String> = []

    /// The unread notices, newest first, less any just cleared.
    var notices: [Notice] {
        Notices.sorted((snapshot?.notices ?? []).filter { !cleared.contains($0.id) })
    }

    /// Banners whatever is new since the last snapshot: the newest, with
    /// "+N more" (TVBanner).
    private func noticeArrivals() {
        let notices = self.notices
        let arrivals = TVBanner.arrivals(seen: seen, now: notices, night: night)
        seen = (seen ?? []).union(notices.map(\.id))
        if let next = TVBanner.banner(arrivals) {
            banner = BannerShow(notice: next.notice, more: next.more)
        }
    }

    /// Clears notices everywhere (empty ids = all of them).
    func clearNotices(_ ids: [String]) {
        let gone = ids.isEmpty ? notices.map(\.id) : ids
        cleared.formUnion(gone)
        Task {
            do {
                if ids.isEmpty { try await client.clearAllNotices() } else { try await client.clearNotices(ids: ids) }
            } catch {
                cleared.subtract(gone)
            }
        }
    }

    /// Approve or Deny from a notice, then clear it.
    func answer(_ notice: Notice, ok: Bool) {
        guard let approvalId = notice.approvalId else { return }
        Task {
            do {
                try await client.answer(approval: approvalId, ok: ok)
                clearNotices([notice.id])
            } catch {}
        }
    }

    /// Tells Jarvis Dylan has gone to bed (or is up after a mis-press).
    /// Failures stay quiet: an older server answers 404 or 409.
    func setSleep(_ asleep: Bool) {
        Task { try? await client.setSleep(asleep: asleep, source: "tv") }
    }

    /// Fetches the snapshot; keeps the last one on screen if this fails.
    func load() async {
        #if DEBUG
        // `-demoSnapshot` shows the sample data even when Jarvis answers.
        if let demo = DemoSnapshot.snapshot {
            snapshot = demo
            reachable = true
            // `-demoBanner` pretends the sample notices just arrived.
            if ProcessInfo.processInfo.arguments.contains("-demoBanner"), seen == nil { seen = [] }
            noticeArrivals()
            return
        }
        #endif
        do {
            snapshot = try await client.snapshot()
            reachable = true
            noticeArrivals()
            approvals = (try? await client.pendingApprovals().count) ?? approvals
        } catch {
            reachable = false
            #if DEBUG
            if snapshot == nil, let demo = DemoSnapshot.snapshot { snapshot = demo }
            #endif
        }
    }
}

struct AlwaysOnView: View {
    @StateObject private var model = AlwaysOnModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Which turn of the panel rotation is showing.
    @State private var turn = 0
    /// The sun lamp right now (Dylan, 2026-11-17): the background follows
    /// the real sunrise and sunset; see SunLamp in JarvisKit.
    @State private var lamp = SunLampState(phase: .night, brightness: SunLamp.nightBrightness, warmth: 0)
    /// A few points of slow drift, so an OLED never holds one picture.
    @State private var drift = CGSize.zero
    /// True while the Ask Jarvis screen is up.
    @State private var asking = false
    /// The conversation (kept while the chat is closed, so reopening
    /// carries on) and whether the text field has focus.
    @StateObject private var chat = TVChatModel()
    /// True while the notices list is in the right side.
    @State private var showingNotices = false
    /// How long the card showing needs to scroll its text through once.
    @State private var cardScroll: Double = 0
    /// The most a card's rows may take before they scroll: less when the
    /// Now/Next card is above.
    @State private var rowsMax: CGFloat = 274
    @FocusState private var typing: Bool
    /// Guest-friendly (on by default): people walking in see this screen,
    /// so it leaves out sleep, steps, Jarvis's suggestions and the private
    /// half of the greeting (TVBoard in JarvisKit).
    @AppStorage("tv.guestFriendly") private var guest = true
    /// The calm bedroom layout from 2:30 AM to just before sunrise (on by
    /// default; the moon button beside Ask Jarvis turns it off).
    @AppStorage("tv.nightCalm") private var nightCalmOn = true
    /// A soft chime with each banner (never in the night view).
    @AppStorage("tv.bannerChime") private var chimeOn = true
    /// True while the calm layout shows.
    @State private var calm = false
    /// A remote press shows the full board until then.
    @State private var wokenUntil: Date?
    /// When the Night button was pressed, while its night view is up.
    @State private var nightPressedAt: Date?

    /// The orb and the time on the left; one roomy panel at a time on the
    /// right, cross-fading every 20 s (Dylan, 2026-11-17: the right was
    /// cluttered and not dynamic enough for a kiosk).
    var body: some View {
        ZStack {
            LampSky(lamp: lamp).ignoresSafeArea()
            SkyLayers(lamp: lamp, arc: arc, condition: model.snapshot?.home?.weather?.condition, palette: palette)
                .ignoresSafeArea()
            if calm {
                calmLayout
                    .offset(drift)
                    .transition(.opacity)
            } else {
                HStack(alignment: .center, spacing: 80) {
                    left.frame(maxWidth: .infinity)
                    Group {
                        if asking {
                            ChatPanel(model: chat, palette: palette, field: $typing)
                                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: 60)), removal: .opacity.combined(with: .offset(x: 60))))
                        } else if showingNotices && !guest {
                            NoticesPanel(notices: model.notices, palette: palette, answer: { model.answer($0, ok: $1) }, clear: { model.clearNotices($0) })
                                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: 60)), removal: .opacity.combined(with: .offset(x: 60))))
                        } else {
                            right.transition(.opacity)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .animation(.smooth(duration: 0.6), value: asking)
                    .animation(.smooth(duration: 0.6), value: showingNotices)
                }
                .padding(80)
                .offset(drift)
                .transition(.opacity)
            }
        }
        .fontDesign(.rounded)
        // New notices slide down from the top for a few seconds.
        .overlay(alignment: .top) {
            if let show = model.banner {
                NoticeBanner(show: show, guest: guest, night: calm, palette: palette)
                    .padding(.top, 50)
                    .id(show.id)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                    .task(id: show.id) {
                        if chimeOn && !calm { Chime.shared.play() }
                        try? await Task.sleep(for: .seconds(TVBanner.seconds(show.notice)))
                        if model.banner?.id == show.id { model.banner = nil }
                    }
            }
        }
        .animation(.smooth(duration: 0.6), value: model.banner?.id)
        .onChange(of: calm) { _, night in model.night = night }
        // The two layouts fade into each other slowly, never a cut.
        .animation(reduceMotion ? nil : .easeInOut(duration: 2.5), value: calm)
        // Any swipe on the remote while it's calm brings the board back.
        .onMoveCommand { _ in if calm { wake() } }
        .onPlayPauseCommand { if calm { wake() } }
        .task {
            while !Task.isCancelled {
                await model.load()
                // Every 5 s, so new notices banner promptly.
                try? await Task.sleep(for: .seconds(5))
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(TVBoard.turnSeconds))
                // A card whose text is still scrolling stays until it has
                // gone through once.
                let extra = cardScroll - TVBoard.turnSeconds
                if extra > 0 { try? await Task.sleep(for: .seconds(extra)) }
                cardScroll = 0
                withAnimation(reduceMotion ? nil : .smooth(duration: 1.0)) { turn += 1 }
            }
        }
        // The lamp follows the clock: checked every 30 s, each change eased
        // over 20 s so it never jumps; the layout drifts a few points.
        .task {
            let preview = SunLampPreview.enabled
            var first = true
            while !Task.isCancelled {
                let now = SunLampPreview.now()
                let next = lampState(at: now)
                // Opens straight at the right light; only later changes ease.
                withAnimation(reduceMotion || first ? nil : .easeInOut(duration: preview ? 0.5 : 20)) {
                    lamp = next
                    let minutes = now.timeIntervalSinceReferenceDate / 60
                    drift = CGSize(width: 10 * sin(minutes / 7), height: 8 * cos(minutes / 11))
                }
                first = false
                updateCalm()
                try? await Task.sleep(for: .seconds(preview ? 0.5 : 30))
            }
        }
        // Menu slides the chat away (and only then: otherwise Menu leaves
        // the app as usual).
        // Menu backs out of the night view, then out of the chat; otherwise
        // it leaves the app as usual.
        .onExitCommand(perform: calm ? { wake() } : asking ? { closeChat() } : showingNotices ? { showingNotices = false } : nil)
        // After each reply the field takes focus again: the next turn is one
        // press and the mic button.
        .onChange(of: chat.replies) { _, _ in if asking { typing = true } }
        // A minute of quiet after the last reply closes the chat.
        .task(id: asking) {
            while asking && !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                if chat.chat.shouldClose(lastActivity: chat.lastActivity, now: Date()) { closeChat() }
            }
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            #if DEBUG
            // Screenshot check: `-openAsk` opens Ask Jarvis at launch.
            if ProcessInfo.processInfo.arguments.contains("-openAsk") { openChat() }
            if ProcessInfo.processInfo.arguments.contains("-openNotices") { showingNotices = true }
            #endif
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    // MARK: Sun lamp

    /// The lamp at `now`, from the snapshot's sun times or an LA estimate.
    private func lampState(at now: Date) -> SunLampState {
        let format = ISO8601DateFormatter()
        let sun = model.snapshot?.home?.sun
        let estimate = SunLamp.estimate(for: now)
        let rise = sun?.rising.flatMap { format.date(from: $0) } ?? estimate.sunrise
        let set = sun?.setting.flatMap { format.date(from: $0) } ?? estimate.sunset
        return SunLamp.state(now: now, sunrise: rise, sunset: set)
    }

    // MARK: Night calm

    /// Clock, date, the dimmed orb and one line if something's on before
    /// 10 AM, under the moon and stars. One big invisible button takes the
    /// first press, so Select wakes the board instead of opening Ask Jarvis.
    private var calmLayout: some View {
        Button(action: wake) {
            VStack(spacing: 22) {
                // At night only the pips that need him.
                OrbView(state: .listening, size: 240, orbit: Orbit.items(running: [], notices: model.notices, night: true), tappable: false, onLight: false)
                    .opacity(0.3)
                TimelineView(.periodic(from: .now, by: 30)) { tick in
                    let now = SunLampPreview.now(at: tick.date)
                    VStack(spacing: 10) {
                        Text(now, format: .dateTime.hour().minute())
                            .font(.system(size: 150, weight: .regular, design: .rounded))
                            .monospacedDigit()
                            .fixedSize()
                            .foregroundStyle(ink)
                            .contentTransition(.numericText())
                            .animation(reduceMotion ? nil : .smooth(duration: 0.8), value: now.formatted(.dateTime.hour().minute()))
                        Text(now, format: .dateTime.weekday(.wide).month(.wide).day())
                            .font(.title3)
                            .foregroundStyle(inkDim)
                        if let snapshot = model.snapshot,
                           let line = NightCalm.morningLine(events: snapshot.events, agenda: snapshot.today, now: now, guest: guest) {
                            Label(line, systemImage: "alarm.fill")
                                .font(.headline)
                                .foregroundStyle(inkDim)
                                .labelStyle(TintedIconLabel(icon: accent))
                                .padding(.top, 8)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(CalmButtonStyle())
        .accessibilityLabel("Show the full screen")
    }

    /// Shows the full board for a minute, then lets it settle again.
    private func wake() {
        // Backing out of the Night button's view: straight after pressing it
        // reads as a mis-press, so Jarvis hears "awake" (NightButton). Later,
        // he works that out himself when Dylan next talks to him.
        if let pressed = nightPressedAt {
            if NightButton.sendAwakeOnExit(pressedAt: pressed, now: Date()) { model.setSleep(false) }
            nightPressedAt = nil
        }
        wokenUntil = SunLampPreview.now().addingTimeInterval(NightCalm.pressSeconds)
        updateCalm()
        Task {
            try? await Task.sleep(for: .seconds(NightCalm.pressSeconds + 1))
            updateCalm()
        }
    }

    /// Slides the chat in and puts focus on the field.
    private func openChat() {
        asking = true
        wake()
        Task {
            await chat.opened()
            typing = true
        }
    }

    /// Slides the chat away; the conversation is kept.
    private func closeChat() {
        chat.hush()
        typing = false
        asking = false
    }

    /// Works out whether the calm layout should show right now.
    private func updateCalm() {
        if nightPressedAt != nil { if !calm { calm = true }; return }
        if asking { if calm { calm = false }; return }
        let next = NightCalm.isCalm(now: SunLampPreview.now(), sunrise: sunTimes.rise, enabled: nightCalmOn, wokenUntil: wokenUntil)
        if next != calm { calm = next }
    }

    /// The sun or moon's place on its arc right now.
    private var arc: SkyArc {
        let format = ISO8601DateFormatter()
        let now = SunLampPreview.now()
        let sun = model.snapshot?.home?.sun
        let estimate = SunLamp.estimate(for: now)
        let rise = sun?.rising.flatMap { format.date(from: $0) } ?? estimate.sunrise
        let set = sun?.setting.flatMap { format.date(from: $0) } ?? estimate.sunset
        return SkyArc.at(now: now, sunrise: rise, sunset: set)
    }

    /// Every colour for the lamp right now, each measured against the sky
    /// and panels behind it (LampPalette in JarvisKit): near-black ink by
    /// day, dimmed frost by night, swapped at the crossover.
    private var palette: LampPalette { LampPalette.at(lamp) }
    private var ink: Color { palette.ink.color }
    private var inkDim: Color { palette.inkDim.color }
    private var accent: Color { palette.accent.color }
    private var warm: Color { palette.warm.color }

    // MARK: Left

    /// The orb, the time and the date, the weather and the sun, and the
    /// connection line.
    private var left: some View {
        VStack(spacing: 26) {
            // The orb follows the chat while it's open: thinking, working,
            // speaking with each word.
            OrbView(state: chat.orbMood ?? (model.snapshot?.jobs?.running.isEmpty == false ? .working : .listening), size: 400, level: chat.level, orbit: Orbit.items(running: model.snapshot?.jobs?.running ?? [], notices: model.notices), tappable: false, onLight: palette.darkInk)
                // Dim at night so the bedroom stays dark (the text is dimmed
                // by the palette instead, only as far as it stays readable).
                .opacity(0.35 + 0.65 * min(1, lamp.brightness * 3))
            TimelineView(.periodic(from: .now, by: SunLampPreview.enabled ? 0.5 : 30)) { tick in
                let context = (date: SunLampPreview.now(at: tick.date), ())
                VStack(spacing: 8) {
                    Text(context.date, format: .dateTime.hour().minute())
                        .font(.system(size: 104, weight: .regular, design: .rounded))
                        .monospacedDigit()
                        // Never clipped: the clock always shows in full.
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(ink)
                        // Each minute rolls over rather than snapping.
                        .contentTransition(.numericText())
                        .animation(reduceMotion ? nil : .smooth(duration: 0.8), value: context.date.formatted(.dateTime.hour().minute()))
                    Text(context.date, format: .dateTime.weekday(.wide).month(.wide).day())
                        .font(.title3)
                        .foregroundStyle(inkDim)
                    if let weather = model.snapshot?.home?.weather {
                        Label(weatherText(weather), systemImage: TodayWording.weatherSymbol(weather.condition))
                            .font(.headline)
                            .foregroundStyle(inkDim)
                            .labelStyle(TintedIconLabel(icon: warm))
                            .symbolEffect(.breathe, options: .repeating, isActive: !reduceMotion)
                            .padding(.top, 6)
                    }
                    if let extra = HomeGlance.weatherExtra(model.snapshot?.home?.weather) {
                        Label(extra, systemImage: "wind")
                            .font(.callout)
                            .foregroundStyle(inkDim)
                            .labelStyle(TintedIconLabel(icon: accent))
                    }
                    if let sun = model.snapshot?.home?.sun,
                       let line = TodayWording.sunLine(rising: sun.rising, setting: sun.setting, now: context.date) {
                        Label(line, systemImage: "sun.horizon.fill")
                            .font(.headline)
                            .foregroundStyle(inkDim)
                            .labelStyle(TintedIconLabel(icon: warm))
                    }
                }
            }
            // The two focusable things: Ask Jarvis (Select opens it straight
            // away) and the guest-friendly switch beside it.
            HStack(spacing: 24) {
                Button {
                    asking ? closeChat() : openChat()
                } label: {
                    Label(asking ? "Done" : "Ask Jarvis", systemImage: asking ? "checkmark" : "mic.fill")
                        .font(.callout)
                        .foregroundStyle(ink)
                }
                .buttonStyle(SoftFocusButtonStyle(palette: palette))
                .accessibilityHint("Type or hold the mic button to ask him something")
                Button {
                    withAnimation(.smooth) { guest.toggle() }
                } label: {
                    Label(guest ? "Guest view" : "Full view", systemImage: guest ? "person.2.fill" : "person.fill")
                        .labelStyle(.iconOnly)
                        .font(.callout)
                        .foregroundStyle(ink)
                }
                .accessibilityLabel(guest ? "Guest-friendly view is on" : "Guest-friendly view is off")
                .buttonStyle(SoftFocusButtonStyle(palette: palette))
                .accessibilityHint("Hides sleep, steps and Jarvis's suggestions when on")
                // Night (Dylan, 2026-11-18): the minimal night view now, at
                // any hour, and Jarvis hears he's gone to bed. Any press backs
                // out. Holding Select on it turns the automatic 2:30 AM night
                // view on or off.
                Button {
                    if asking { closeChat() }
                    nightPressedAt = Date()
                    model.setSleep(true)
                    updateCalm()
                } label: {
                    Label("Night", systemImage: nightCalmOn ? "moon.zzz.fill" : "moon.zzz")
                        .labelStyle(.iconOnly)
                        .font(.callout)
                        .foregroundStyle(ink)
                }
                .contextMenu {
                    Button(nightCalmOn ? "Turn off the automatic night view" : "Turn on the automatic night view") {
                        nightCalmOn.toggle()
                        updateCalm()
                    }
                    Button(chimeOn ? "Turn off the notification chime" : "Turn on the notification chime") {
                        chimeOn.toggle()
                    }
                }
                .buttonStyle(SoftFocusButtonStyle(palette: palette))
                .accessibilityHint("Shows only the clock and tells Jarvis you've gone to bed. Hold to change the automatic night view.")
            }
            Text(connectionWords)
                .font(.caption)
                .foregroundStyle(model.reachable == false ? palette.alert.color : inkDim)
        }
    }

    // MARK: Right

    /// From the top: status chips, the greeting, the Now/Next hero card,
    /// then one card at a time cross-fading on a timer, with page dots that
    /// fill while each card is up. A fixed card height, so nothing below
    /// jumps when the card changes and nothing is ever cut off.
    @ViewBuilder
    private var right: some View {
        if let snapshot = model.snapshot {
            let cards = TVBoard.cards(snapshot, guest: guest)
            let active = cards.isEmpty ? 0 : turn % cards.count
            TimelineView(.periodic(from: .now, by: SunLampPreview.enabled ? 0.5 : 15)) { tick in
                let now = SunLampPreview.now(at: tick.date)
                let hero = TVBoard.hero(snapshot, now: now, guest: guest)
                VStack(alignment: .leading, spacing: 26) {
                    HStack(spacing: 18) {
                        ChipRow(chips: StatusChips.chips(snapshot, approvals: model.approvals), palette: palette)
                        noticesButton
                    }
                    greeting(snapshot, showBody: false)
                    if let hero {
                        NowNextCard(item: hero, now: now, palette: palette)
                            .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    }
                    if !cards.isEmpty {
                        ZStack(alignment: .topLeading) {
                            boardCard(cards[active], snapshot: snapshot, now: now)
                                .id(cards[active])
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .offset(x: 40)),
                                    removal: .opacity.combined(with: .offset(x: -40))
                                ))
                        }
                        // With three or more cards the height holds still so
                        // nothing below jumps; with fewer, the card takes
                        // its own height and the column centres itself.
                        .frame(height: cards.count >= 3 ? (hero == nil ? 470 : 400) : nil, alignment: .top)
                        .onPreferenceChange(ScrollCycleKey.self) { cardScroll = $0 }
                        .onAppear { rowsMax = hero == nil ? 344 : 274 }
                        .onChange(of: hero == nil) { _, none in rowsMax = none ? 344 : 274 }
                        if cards.count > 1 {
                            CardDots(count: cards.count, active: active, seconds: TVBoard.turnSeconds, palette: palette)
                        }
                    }
                }
                .animation(.smooth(duration: 0.8), value: hero?.title)
            }
        } else {
            HStack(spacing: 16) {
                ProgressView()
                Text("Jarvis is thinking…").foregroundStyle(inkDim)
            }
        }
    }

    /// "3 new" with its pips: in full view a button that slides the list
    /// in; in guest view the count only, never the text.
    @ViewBuilder
    private var noticesButton: some View {
        let notices = model.notices
        if let count = Notices.countLabel(notices) {
            let label = HStack(spacing: 8) {
                ForEach(Array(Notices.pips(notices).prefix(4).enumerated()), id: \.offset) { _, kind in
                    Circle().fill(OrbView.noticeOrange(onLight: palette.darkInk).opacity(kind == .need ? 1 : 0.75))
                        .frame(width: 12, height: 12)
                }
                Text(count).font(.caption.weight(.semibold))
            }
            if guest {
                label
                    .foregroundStyle(palette.ink.color)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(palette.panel.color))
                    .overlay(Capsule().strokeBorder(palette.panelEdge.color, lineWidth: 2))
            } else {
                Button {
                    showingNotices.toggle()
                } label: { label }
                .buttonStyle(SoftFocusButtonStyle(palette: palette))
                .accessibilityLabel("\(notices.count) unread notices")
            }
        }
    }

    /// "🌙 Good evening, Dylan" and, when there's no hero card and it isn't
    /// guest-friendly, the rest of his greeting.
    @ViewBuilder
    private func greeting(_ snapshot: Snapshot, showBody: Bool) -> some View {
        if let parts = TVBoard.greeting(snapshot, guest: guest) {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(KioskIcons.greetingEmoji(hour: Calendar.current.component(.hour, from: SunLampPreview.now()))) \(parts.headline)")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(ink)
                if showBody, let body = parts.body {
                    Text(body)
                        .font(.callout)
                        .foregroundStyle(inkDim)
                        .lineLimit(2)
                        .frame(maxWidth: 780, alignment: .leading)
                }
            }
        }
    }

    /// One rotating card. Never money; private cards never reach here in
    /// guest-friendly mode (TVBoard.cards).
    @ViewBuilder
    private func boardCard(_ which: TVCard, snapshot: Snapshot, now: Date) -> some View {
        switch which {
        case .message:
            // Jarvis's full message, wrapped; it shrinks a little before it
            // would ever be cut off.
            card(which) {
                // The headline is already across the top; the card is the rest.
                if let parts = TVBoard.greeting(snapshot, guest: guest) {
                    if let body = parts.body {
                        // Long messages scroll slowly in the card rather than
                        // shrinking or cutting off.
                        Text(body)
                            .font(.title3)
                            .lineSpacing(6)
                            .staggered(1)
                    }
                }
            }
        case .today:
            card(which) {
                ForEach(Array(TodayTimeline.rows(snapshot.today, events: snapshot.events, now: now, guest: guest, limit: 6).enumerated()), id: \.element.id) { index, row in
                    timelineRow(row).staggered(index)
                }
            }
        case .home:
            card(which) {
                ForEach(Array(HomeGlance.lines(snapshot.home, limit: 6).enumerated()), id: \.element.id) { index, line in
                    HStack(alignment: .firstTextBaseline, spacing: 18) {
                        Image(systemName: line.symbol)
                            .foregroundStyle(line.attention ? palette.alert.color : accent)
                            .frame(width: 44)
                        Text(line.title).lineLimit(1)
                        Spacer(minLength: 24)
                        Text(line.value)
                            .foregroundStyle(line.attention ? palette.alert.color : inkDim)
                            .fontWeight(line.attention ? .semibold : .regular)
                            .lineLimit(1)
                    }
                    .staggered(index)
                }
            }
        case .playing:
            card(which) {
                ForEach(Array(TVBoard.playing(snapshot.home).prefix(3).enumerated()), id: \.element.id) { index, device in
                    HStack(spacing: 24) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(accent.opacity(0.14)).frame(width: 84, height: 84)
                            Image(systemName: TodayWording.deviceSymbol(device)).font(.title2).foregroundStyle(accent)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(device.detail ?? (device.state == "playing" ? "Playing" : "Paused"))
                                .font(.headline.weight(.semibold)).lineLimit(1)
                            Text(device.name).font(.callout).foregroundStyle(inkDim)
                        }
                        Spacer()
                        Image(systemName: device.state == "playing" ? "waveform" : "pause.fill")
                            .font(.title2)
                            .foregroundStyle(warm)
                            .symbolEffect(.variableColor.iterative, options: .repeating, isActive: device.state == "playing" && !reduceMotion)
                    }
                    .staggered(index)
                }
            }
        case .forecast:
            card(which) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array((snapshot.home?.forecast ?? []).prefix(7).enumerated()), id: \.offset) { index, hour in
                        VStack(spacing: 14) {
                            Text(hourLabel(hour.at)).font(.callout).foregroundStyle(inkDim)
                            Image(systemName: TVBoard.forecastSymbol(hour, sunrise: sunTimes.rise, sunset: sunTimes.set))
                                .font(.title2)
                                .foregroundStyle(warm)
                                .frame(height: 50)
                            Text(hour.temperature.map { "\(Int($0.rounded()))°" } ?? "–")
                                .font(.headline.weight(.semibold))
                            Text((hour.rain ?? 0) >= 20 ? "\(Int(hour.rain!))%" : " ")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(accent)
                        }
                        .frame(maxWidth: .infinity)
                        .staggered(index)
                    }
                }
            }
        case .tasks:
            // What Jarvis is chasing down, each with a live timer.
            card(which) {
                let running = snapshot.jobs?.running ?? []
                TimelineView(.periodic(from: .now, by: 1)) { tick in
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(Array(running.prefix(4).enumerated()), id: \.element.id) { index, task in
                            HStack(alignment: .firstTextBaseline, spacing: 18) {
                                Circle().fill(OrbView.taskBlue(onLight: palette.darkInk)).frame(width: 16, height: 16)
                                    .frame(width: 44)
                                Text(TaskCard.title(task, index: index, guest: guest)).lineLimit(2)
                                Spacer(minLength: 24)
                                Text(task.state == "queued" ? "Queued" : Orbit.elapsed(since: task.startedAt, now: tick.date) ?? "Running")
                                    .font(.headline.monospacedDigit())
                                    .foregroundStyle(accent)
                                    .contentTransition(.numericText())
                            }
                            .staggered(index)
                        }
                    }
                }
            }
        case .jarvis:
            // How Jarvis's services are doing (tasks have their own card).
            card(which) {
                HStack(spacing: 28) {
                    ForEach(snapshot.services) { service in
                        Label(service.name, systemImage: service.status == "down" ? "xmark.circle.fill" : service.status == "degraded" ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                            .labelStyle(TintedIconLabel(icon: service.status == "down" || service.status == "degraded" ? palette.alert.color : accent))
                            .font(.callout)
                            .foregroundStyle(inkDim)
                    }
                }
                .staggered(0)
            }
        case .lookout:
            card(which) {
                let lookout = snapshot.jobs?.lookout
                ForEach(Array((lookout?.watching ?? []).prefix(3).enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 18) {
                        Image(systemName: "eye.fill").foregroundStyle(accent).frame(width: 44)
                        Text(item).lineLimit(1)
                    }
                    .staggered(index)
                }
                if let line = LookoutCard.messagesLine(snapshot.jobs?.messenger) {
                    HStack(alignment: .firstTextBaseline, spacing: 18) {
                        Image(systemName: "envelope.fill").foregroundStyle(warm).frame(width: 44)
                        Text(line)
                        if let quiet = snapshot.jobs?.messenger?.quiet, !quiet.isEmpty {
                            Text("· quiet \(quiet)").foregroundStyle(inkDim)
                        }
                    }
                    .staggered(3)
                }
                if let held = lookout?.heldBackCount, held > 0 {
                    HStack(alignment: .firstTextBaseline, spacing: 18) {
                        Image(systemName: "hand.raised.fill").foregroundStyle(inkDim).frame(width: 44)
                        Text(held == 1 ? "1 thing held back" : "\(held) things held back").foregroundStyle(inkDim)
                    }
                    .staggered(4)
                }
            }
        case .health:
            card(which) {
                HStack(spacing: 60) {
                    if let asleep = snapshot.health?.sleep?.asleepMin {
                        stat(TodayWording.hours(asleep), "asleep last night", symbol: "bed.double.fill")
                    }
                    if let steps = snapshot.health?.yesterday?.steps {
                        stat(steps.formatted(), "steps yesterday", symbol: "figure.walk")
                    }
                }
                .staggered(0)
            }
        case .suggestions:
            card(which) {
                ForEach(Array((snapshot.offers?.offers ?? []).prefix(4).enumerated()), id: \.element.id) { index, offer in
                    HStack(alignment: .firstTextBaseline, spacing: 18) {
                        Image(systemName: "sparkle").foregroundStyle(warm).frame(width: 36)
                        Text(offer.title).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                    .staggered(index)
                }
            }
        }
    }

    /// One row of the Today timeline: a marker on a rail, the time, what.
    private func timelineRow(_ row: TimelineRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 20) {
            Group {
                switch row.state {
                case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(inkDim)
                case .now: Image(systemName: "record.circle.fill").foregroundStyle(accent).symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
                case .next: Image(systemName: "circle.inset.filled").foregroundStyle(accent)
                case .later: Image(systemName: "circle").foregroundStyle(inkDim)
                }
            }
            .frame(width: 36)
            Text(row.time)
                .foregroundStyle(row.state == .done ? inkDim : accent)
                .monospacedDigit()
                .frame(width: 140, alignment: .leading)
            Text(row.title)
                .foregroundStyle(row.state == .done ? inkDim : ink)
                .fontWeight(row.state == .next || row.state == .now ? .semibold : .regular)
                .lineLimit(1)
            if row.jarvis {
                Image(systemName: "sparkles").font(.caption).foregroundStyle(warm)
            }
        }
    }

    /// Today's sunrise and sunset, from the snapshot or the estimate.
    private var sunTimes: (rise: Date, set: Date) {
        let format = ISO8601DateFormatter()
        let now = SunLampPreview.now()
        let sun = model.snapshot?.home?.sun
        let estimate = SunLamp.estimate(for: now)
        return (sun?.rising.flatMap { format.date(from: $0) } ?? estimate.sunrise, sun?.setting.flatMap { format.date(from: $0) } ?? estimate.sunset)
    }

    /// "3 PM" for the forecast strip.
    private func hourLabel(_ iso: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: iso) else { return "" }
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US")
        format.dateFormat = "h a"
        return format.string(from: date)
    }

    /// "On Tailscale · jarvis", or what's wrong.
    private var connectionWords: String {
        switch model.reachable {
        case .some(true): return "On Tailscale · jarvis"
        case .some(false): return "Can’t reach Jarvis. Is Tailscale on for this Apple TV?"
        case .none: return "Connecting…"
        }
    }

    /// A roomy titled card on a real surface, large type.
    private func card<Rows: View>(_ which: TVCard, @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(which.title, systemImage: which.symbol)
                .font(.callout.weight(.bold))
                .foregroundStyle(inkDim)
                .labelStyle(TintedIconLabel(icon: accent))
            // Rows that don't fit scroll slowly inside the card.
            AutoScrollBox(maxHeight: rowsMax) {
                VStack(alignment: .leading, spacing: 18) {
                    rows()
                }
                .font(.body)
                .foregroundStyle(ink)
            }
        }
        .padding(34)
        .frame(maxWidth: .infinity, alignment: .leading)
        // A real surface, measured like the text: paper by day, a faint lift
        // at night, with an edge that shows against the sky (3:1).
        .background(RoundedRectangle(cornerRadius: 34, style: .continuous).fill(palette.panel.color))
        .overlay(RoundedRectangle(cornerRadius: 34, style: .continuous).strokeBorder(palette.panelEdge.color, lineWidth: 2))
    }

    /// An icon, a big number, and a caption.
    private func stat(_ value: String, _ caption: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol).font(.title3).foregroundStyle(accent)
            Text(value).font(.system(size: 52, weight: .bold, design: .rounded)).monospacedDigit()
            Text(caption).font(.callout).foregroundStyle(inkDim)
        }
    }

    /// "Clear, 61°F", or just the condition when there's no number.
    private func weatherText(_ weather: Weather) -> String {
        guard let temperature = weather.temperature else { return TodayWording.weatherWords(weather.condition) }
        return "\(TodayWording.weatherWords(weather.condition)), \(Int(temperature.rounded()))\(weather.unit)"
    }
}

/// The sky behind everything, lit by the lamp: near-black at night, deep
/// red to amber to gold through dawn, a warm white daylight sky by day, and
/// amber back to dark at dusk.
struct LampSky: View {
    let lamp: SunLampState

    /// A top-to-bottom gradient, from the palette (so the contrast checks
    /// measure exactly this sky).
    var body: some View {
        let palette = LampPalette.at(lamp)
        LinearGradient(colors: [palette.skyTop.color, palette.skyBottom.color], startPoint: .top, endPoint: .bottom)
    }
}

extension RGB {
    /// As a SwiftUI colour (sRGB).
    var color: Color { Color(.sRGB, red: r, green: g, blue: b) }
}

/// A label whose icon is one solid measured colour (multicolour symbols
/// put a pale yellow sun on a pale sky).
struct TintedIconLabel: LabelStyle {
    let icon: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.icon.foregroundStyle(icon)
            configuration.title
        }
    }
}

/// A fast-forward clock for checking the lamp: debug builds launched with
/// `-sunLampPreview` run a whole day in two minutes from 5:30 AM.
enum SunLampPreview {
    static let started = Date()

    static var enabled: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-sunLampPreview")
        #else
        return false
        #endif
    }

    /// `-lampAt 13:00` (debug builds) holds the clock at that time today,
    /// for screenshots of one light.
    static var pinned: Date? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-lampAt"), i + 1 < args.count else { return nil }
        let parts = args[i + 1].split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: started)
        #else
        return nil
        #endif
    }

    /// Now, or the fast-forward clock's now.
    static func now(at real: Date = Date()) -> Date {
        if let pinned { return pinned }
        guard enabled else { return real }
        let dawn = Calendar.current.date(bySettingHour: 5, minute: 30, second: 0, of: started) ?? started
        return dawn.addingTimeInterval(real.timeIntervalSince(started) * 720)
    }
}

/// The calm layout's whole-screen button: no focus halo or lift, so the
/// screen stays dark and still until a press.
struct CalmButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}
