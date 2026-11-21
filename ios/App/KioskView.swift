// The iPad kiosk (Dylan, 2026-11-17): Home turned into a full-screen,
// always-on display for the room. Status bar hidden, the screen kept awake,
// a big clock and greeting, the live orb, and whatever matters most in the
// hero spot (an approval, an alert, something starting soon). Beside it the
// other panels take turns, cross-fading every 20 s; a touch holds them for
// a minute. No money here at all: anyone in the room can see it.
import SwiftUI
import JarvisKit

struct KioskView: View {
    @EnvironmentObject private var app: AppModel
    @ObservedObject var today: TodayModel
    @ObservedObject var chat: ChatModel
    @ObservedObject var talk: TalkModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Which turn of the panel rotation is showing.
    @State private var turn = 0
    /// When Dylan last touched the screen; the rotation waits a minute after.
    @State private var lastTouch = Date.distantPast

    /// Landscape: clock, orb and hero on the left, rotating panels on the
    /// right. Portrait: the same stacked.
    var body: some View {
        GeometryReader { area in
            let wide = area.size.width > area.size.height
            ZStack(alignment: .topTrailing) {
                Theme.sky.ignoresSafeArea()
                Group {
                    if wide {
                        HStack(alignment: .center, spacing: 48) {
                            lead(orb: min(area.size.height * 0.34, 300))
                                .frame(maxWidth: .infinity)
                            rotating(count: 2)
                                .frame(maxWidth: .infinity)
                        }
                    } else {
                        VStack(spacing: 32) {
                            lead(orb: min(area.size.width * 0.42, 300))
                            rotating(count: 2)
                        }
                    }
                }
                .padding(wide ? 48 : 36)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                closeButton
            }
        }
        .fontDesign(.rounded)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        // Any touch holds the rotation for a minute.
        .simultaneousGesture(TapGesture().onEnded { lastTouch = Date() })
        .simultaneousGesture(DragGesture(minimumDistance: 10).onChanged { _ in lastTouch = Date() })
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            // A call started here carries on in the Talk tab.
            if PhoneKiosk.handOverToTalk(callLive: talk.phase != .off) { app.tab = .talk }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(KioskPlan.turnSeconds))
                if Date().timeIntervalSince(lastTouch) >= KioskPlan.touchHoldSeconds {
                    withAnimation(reduceMotion ? nil : .smooth(duration: 1.2)) { turn += 1 }
                }
            }
        }
    }

    // MARK: Lead column

    /// The clock and greeting, the live orb, and the hero card.
    private func lead(orb size: CGFloat) -> some View {
        VStack(spacing: 22) {
            TimelineView(.everyMinute) { context in
                VStack(spacing: 4) {
                    Text(context.date, format: .dateTime.hour().minute())
                        .font(.system(size: 88, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(context.date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                        .font(.title3.weight(.medium))
                        .foregroundStyle(Theme.frostDim)
                    if let weather = today.snapshot?.home?.weather {
                        HStack(spacing: 16) {
                            Label(weatherText(weather), systemImage: TodayWording.weatherSymbol(weather.condition))
                            if let sunset = TodayWording.time(today.snapshot?.home?.sun?.setting) {
                                Label(sunset, systemImage: "sunset.fill")
                            }
                        }
                        .font(.headline)
                        .foregroundStyle(Theme.frostDim)
                        .symbolRenderingMode(.multicolor)
                        .padding(.top, 4)
                    }
                }
            }
            // Tap to talk, tap again to stop (KioskTalkOrb).
            KioskTalkOrb(talk: talk, app: app, size: size, work: today.snapshot?.jobs?.running ?? [])
                .zIndex(1)
            heroCard
                .animation(.smooth(duration: 0.6), value: hero)
        }
    }

    /// The hero right now: an approval, an alert, something soon, or calm.
    private var hero: KioskHero {
        KioskPlan.hero(snapshot: today.snapshot, pending: chat.pendingApprovals)
    }

    /// The hero, as one glass card that changes gently.
    @ViewBuilder
    private var heroCard: some View {
        switch hero {
        case .approval(let count, let summary):
            if let approval = chat.pendingApprovals.first {
                VStack(alignment: .leading, spacing: 8) {
                    if count > 1 {
                        Text("\(count) things need your OK").font(.caption.weight(.semibold)).foregroundStyle(Theme.ember)
                    }
                    ApprovalCard(approval: approval, outcome: nil) { ok in
                        Task { await chat.answer(approval, ok: ok, app: app) }
                    }
                }
                .frame(maxWidth: 520)
                .transition(.opacity)
                .accessibilityLabel("Needs your OK: \(summary)")
            }
        case .alert(let name, let status):
            heroLine("\(name) is \(status)", symbol: "exclamationmark.triangle.fill", tint: Theme.ember)
        case .soon(let title, let minutes):
            heroLine(minutes <= 0 ? "\(title) is starting" : "\(title) in \(minutes) min", symbol: "calendar.badge.clock", tint: Theme.glacier)
        case .calm:
            // A short headline, then the rest smaller (TodayWording.greetingParts).
            let parts = TodayWording.greetingParts(today.snapshot?.offers?.greeting ?? TodayWording.greeting(for: .now))
            VStack(spacing: 6) {
                Text("\(KioskIcons.greetingEmoji(hour: Calendar.current.component(.hour, from: .now))) \(parts.headline)")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Theme.frost.opacity(0.95))
                if let body = parts.body {
                    Text(body)
                        .font(.body)
                        .foregroundStyle(Theme.frostDim)
                        .lineLimit(3)
                        .frame(maxWidth: 520)
                }
            }
            .multilineTextAlignment(.center)
            .transition(.opacity)
        }
    }

    /// One big line on glass for the hero.
    private func heroLine(_ text: String, symbol: String, tint: Color) -> some View {
        Label(text, systemImage: symbol)
            .font(.title3.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
            .glassPanel(tint: tint)
            .transition(.opacity)
    }

    // MARK: Rotating panels

    /// The panels taking turns: `count` at a time, cross-fading.
    private func rotating(count: Int) -> some View {
        var panels = KioskPlan.panels(snapshot: today.snapshot)
        #if DEBUG
        // `-kioskSleepFirst`: the Sleep panel in the first turn (screenshots).
        if ProcessInfo.processInfo.arguments.contains("-kioskSleepFirst"), let i = panels.firstIndex(of: .sleep) { panels.insert(panels.remove(at: i), at: 0) }
        #endif
        let showing = KioskPlan.showing(panels, turn: turn, count: count)
        return VStack(spacing: 20) {
            ForEach(showing, id: \.self) { panel in
                kioskPanel(panel)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 16)),
                        removal: .opacity.combined(with: .offset(y: -16))
                    ))
            }
            if showing.isEmpty {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Jarvis is thinking…").foregroundStyle(Theme.frostDim)
                }
            }
        }
        .frame(maxWidth: 620)
    }

    /// One panel, drawn large for across the room.
    @ViewBuilder
    private func kioskPanel(_ panel: KioskPanel) -> some View {
        switch panel {
        case .schedule: schedulePanel
        case .home: homePanel
        case .work: workPanel
        case .health: healthPanel
        case .sleep: sleepPanel
        case .offers: offersPanel
        }
    }

    /// Today's schedule: what's next first.
    private var schedulePanel: some View {
        let items = today.snapshot?.today ?? []
        return frame("Today", icon: "calendar") {
            if items.isEmpty {
                Text("Nothing booked").font(.title3).foregroundStyle(Theme.frostDim)
            }
            ForEach(items.prefix(5)) { item in
                HStack(alignment: .firstTextBaseline, spacing: 18) {
                    Image(systemName: KioskIcons.agendaSymbol(item.title))
                        .foregroundStyle(Theme.glacier)
                        .frame(width: 28)
                    Text(AgendaTime.label(at: item.at, allDay: item.allDay ?? false))
                        .font(.title3.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(Theme.glacier)
                        .frame(width: 110, alignment: .leading)
                    Text(item.title).font(.title3).lineLimit(1)
                }
            }
        }
    }

    /// The home at a glance: anything wanting a look first, then the
    /// thermostat, what's playing, lights and rooms (HomeGlance).
    private var homePanel: some View {
        frame("Home", icon: "house.fill") {
            ForEach(HomeGlance.lines(today.snapshot?.home, limit: 7)) { line in
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Image(systemName: line.symbol)
                        .foregroundStyle(line.attention ? Theme.rose : Theme.glacier)
                        .frame(width: 30)
                    Text(line.title).font(.title3).lineLimit(1)
                    Spacer(minLength: 16)
                    Text(line.value)
                        .font(.title3.weight(line.attention ? .semibold : .regular))
                        .foregroundStyle(line.attention ? Theme.rose : Theme.frostDim)
                        .lineLimit(1)
                }
            }
        }
    }

    /// What Jarvis is doing in the background.
    private var workPanel: some View {
        frame("Jarvis is working on", icon: "sparkles") {
            ForEach(today.snapshot?.jobs?.running ?? []) { task in
                HStack(spacing: 12) {
                    Circle().fill(OrbView.workAmber).frame(width: 12, height: 12)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.label).font(.title3).lineLimit(2)
                        Text(task.runningWords()).font(.subheadline).foregroundStyle(Theme.frostDim)
                    }
                }
            }
        }
    }

    /// Jarvis's suggestions, titles only (Start them from Home).
    private var offersPanel: some View {
        frame("From Jarvis", icon: "sparkles") {
            ForEach((today.snapshot?.offers?.offers ?? []).prefix(3)) { offer in
                Text(offer.title).font(.title3).lineLimit(2)
            }
        }
    }

    /// Last night's sleep and yesterday's steps.
    private var healthPanel: some View {
        let health = today.snapshot?.health
        return frame("You", icon: "heart.fill") {
            HStack(spacing: 32) {
                // Minutes asleep only from an older Jarvis; otherwise sleep has its own slide.
                if today.snapshot?.sleep == nil, let asleep = health?.sleep?.asleepMin {
                    stat(TodayWording.hours(asleep), "asleep last night")
                }
                if let steps = health?.yesterday?.steps {
                    stat(steps.formatted(), "steps yesterday")
                }
            }
        }
    }

    /// Last night: the score ring and time asleep, the stage bar, the
    /// score's parts and the week, sized for across the room.
    @ViewBuilder
    private var sleepPanel: some View {
        if let snapshot = today.snapshot {
            let sleep = SleepSlide.card(snapshot)
            frame("Sleep", icon: "bed.double.fill", note: sleep.trendAverage) {
                VStack(alignment: .leading, spacing: 20) {
                    if sleep.kind == .noNight {
                        Text(sleep.emptyWords ?? "").font(.title3).foregroundStyle(Theme.frostDim)
                    } else {
                        SleepHeadline(card: sleep, scale: 1.5)
                        if !sleep.stages.isEmpty { SleepStageBar(shares: sleep.stages, scale: 1.5) }
                        if !sleep.parts.isEmpty { SleepPartBars(parts: sleep.parts, scale: 1.3) }
                    }
                    if !sleep.trend.isEmpty { SleepTrendBars(trend: sleep.trend, scale: 1.4) }
                }
            }
        }
    }

    /// A big number over a caption.
    private func stat(_ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit()
            Text(caption).font(.subheadline).foregroundStyle(Theme.frostDim)
        }
    }

    /// A titled glass panel, sized for the kiosk.
    private func frame<Body: View>(_ title: String, icon: String, note: String? = nil, @ViewBuilder body: () -> Body) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: icon).foregroundStyle(Theme.glacier)
                Text(title).font(.headline)
                Spacer()
                if let note { Text(note).font(.subheadline).foregroundStyle(Theme.frostDim) }
            }
            body()
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(radius: 26)
    }

    // MARK: Pieces

    /// "Close", quiet in the corner.
    private var closeButton: some View {
        Button("Close") { dismiss() }
            .font(.headline)
            .foregroundStyle(Theme.frostDim)
            .frame(minWidth: 88, minHeight: 44)
            .background(Capsule().fill(Color.white.opacity(0.06)))
            .padding(20)
            .accessibilityLabel("Close kiosk")
    }

    /// "Cloudy, 58°F".
    private func weatherText(_ weather: Weather) -> String {
        guard let temperature = weather.temperature else { return TodayWording.weatherWords(weather.condition) }
        return "\(TodayWording.weatherWords(weather.condition)), \(Int(temperature.rounded()))\(weather.unit)"
    }
}
