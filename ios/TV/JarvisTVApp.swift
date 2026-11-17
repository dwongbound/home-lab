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

    /// Fetches the snapshot; keeps the last one on screen if this fails.
    func load() async {
        #if DEBUG
        // `-demoSnapshot` shows the sample data even when Jarvis answers.
        if let demo = DemoSnapshot.snapshot { snapshot = demo; reachable = true; return }
        #endif
        do {
            snapshot = try await client.snapshot()
            reachable = true
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
    /// Guest-friendly (on by default): people walking in see this screen,
    /// so it leaves out sleep, steps, Jarvis's suggestions and the private
    /// half of the greeting (TVBoard in JarvisKit).
    @AppStorage("tv.guestFriendly") private var guest = true

    /// The orb and the time on the left; one roomy panel at a time on the
    /// right, cross-fading every 20 s (Dylan, 2026-11-17: the right was
    /// cluttered and not dynamic enough for a kiosk).
    var body: some View {
        ZStack {
            LampSky(lamp: lamp).ignoresSafeArea()
            SkyLayers(lamp: lamp, arc: arc, condition: model.snapshot?.home?.weather?.condition, palette: palette)
                .ignoresSafeArea()
            HStack(alignment: .center, spacing: 80) {
                left.frame(maxWidth: .infinity)
                right.frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(80)
            .offset(drift)
        }
        .fontDesign(.rounded)
        .task {
            while !Task.isCancelled {
                await model.load()
                try? await Task.sleep(for: .seconds(15))
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(TVBoard.turnSeconds))
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
                try? await Task.sleep(for: .seconds(preview ? 0.5 : 30))
            }
        }
        .fullScreenCover(isPresented: $asking) {
            AskJarvisView()
                .preferredColorScheme(.dark)
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            #if DEBUG
            // Screenshot check: `-openAsk` opens Ask Jarvis at launch.
            if ProcessInfo.processInfo.arguments.contains("-openAsk") { asking = true }
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
            OrbView(state: model.snapshot?.jobs?.running.isEmpty == false ? .working : .listening, size: 400, work: model.snapshot?.jobs?.running ?? [], tappable: false, onLight: palette.darkInk)
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
                    asking = true
                } label: {
                    Label("Ask Jarvis", systemImage: "mic.fill")
                        .font(.callout)
                }
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
                .accessibilityHint("Hides sleep, steps and Jarvis's suggestions when on")
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
                    ChipRow(chips: StatusChips.chips(snapshot, approvals: model.approvals), palette: palette)
                    greeting(snapshot, showBody: hero == nil)
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
                        .frame(height: hero == nil ? 470 : 400, alignment: .top)
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
        case .jarvis:
            card(which) {
                let running = snapshot.jobs?.running ?? []
                ForEach(Array(running.prefix(2).enumerated()), id: \.element.id) { index, task in
                    HStack(alignment: .firstTextBaseline, spacing: 18) {
                        Image(systemName: "gearshape.2.fill")
                            .foregroundStyle(warm)
                            .symbolEffect(.rotate, options: .repeating, isActive: !reduceMotion)
                            .frame(width: 44)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(task.label).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                            Text(task.runningWords()).font(.caption).foregroundStyle(inkDim)
                        }
                    }
                    .staggered(index)
                }
                HStack(spacing: 28) {
                    ForEach(snapshot.services) { service in
                        Label(service.name, systemImage: service.status == "down" ? "xmark.circle.fill" : service.status == "degraded" ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                            .labelStyle(TintedIconLabel(icon: service.status == "down" || service.status == "degraded" ? palette.alert.color : accent))
                            .font(.callout)
                            .foregroundStyle(inkDim)
                    }
                }
                .staggered(running.count)
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
            rows()
                .font(.body)
                .foregroundStyle(ink)
                // Shrinks a step rather than clipping when a card is full.
                .minimumScaleFactor(0.85)
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
