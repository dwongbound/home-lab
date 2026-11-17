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
    private let client = JarvisClient()

    /// Fetches the snapshot; keeps the last one on screen if this fails.
    func load() async {
        do {
            snapshot = try await client.snapshot()
            reachable = true
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

    /// The orb and the time on the left; one roomy panel at a time on the
    /// right, cross-fading every 20 s (Dylan, 2026-11-17: the right was
    /// cluttered and not dynamic enough for a kiosk).
    var body: some View {
        ZStack {
            LampSky(lamp: lamp).ignoresSafeArea()
            HStack(alignment: .center, spacing: 80) {
                left.frame(maxWidth: .infinity)
                right.frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(80)
            // Dim at night so the bedroom stays dark; full in daylight.
            .opacity(0.35 + 0.65 * min(1, lamp.brightness * 3))
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
                try? await Task.sleep(for: .seconds(KioskPlan.turnSeconds))
                withAnimation(reduceMotion ? nil : .smooth(duration: 1.2)) { turn += 1 }
            }
        }
        // The lamp follows the clock: checked every 30 s, each change eased
        // over 20 s so it never jumps; the layout drifts a few points.
        .task {
            let preview = SunLampPreview.enabled
            while !Task.isCancelled {
                let now = SunLampPreview.now()
                let next = lampState(at: now)
                withAnimation(reduceMotion ? nil : .easeInOut(duration: preview ? 0.5 : 20)) {
                    lamp = next
                    let minutes = now.timeIntervalSinceReferenceDate / 60
                    drift = CGSize(width: 10 * sin(minutes / 7), height: 8 * cos(minutes / 11))
                }
                try? await Task.sleep(for: .seconds(preview ? 0.5 : 30))
            }
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
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

    /// Text colour for the lamp: dark ink on a bright sky, light otherwise.
    private var ink: Color {
        lamp.brightness > 0.55 ? Theme.basalt : Theme.frost
    }

    /// Secondary text.
    private var inkDim: Color { ink.opacity(0.68) }

    /// Faint text.
    private var inkFaint: Color { ink.opacity(0.45) }

    // MARK: Left

    /// The orb, the time and the date, the weather and the sun, and the
    /// connection line.
    private var left: some View {
        VStack(spacing: 26) {
            OrbView(state: model.snapshot?.jobs?.running.isEmpty == false ? .working : .listening, size: 400, work: model.snapshot?.jobs?.running ?? [], tappable: false, onLight: lamp.brightness > 0.55)
            TimelineView(.periodic(from: .now, by: SunLampPreview.enabled ? 0.5 : 30)) { tick in
                let context = (date: SunLampPreview.now(at: tick.date), ())
                VStack(spacing: 8) {
                    Text(context.date, format: .dateTime.hour().minute())
                        .font(.system(size: 104, weight: .light, design: .rounded))
                        .monospacedDigit()
                        // Never clipped: the clock always shows in full.
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(ink)
                    Text(context.date, format: .dateTime.weekday(.wide).month(.wide).day())
                        .font(.title3)
                        .foregroundStyle(inkDim)
                        .foregroundStyle(inkDim)
                    if let weather = model.snapshot?.home?.weather {
                        Label(weatherText(weather), systemImage: TodayWording.weatherSymbol(weather.condition))
                            .font(.headline)
                            .foregroundStyle(inkDim)
                            .symbolRenderingMode(.multicolor)
                            .padding(.top, 6)
                    }
                    if let sun = model.snapshot?.home?.sun,
                       let line = TodayWording.sunLine(rising: sun.rising, setting: sun.setting, now: context.date) {
                        Label(line, systemImage: "sun.horizon.fill")
                            .font(.headline)
                            .foregroundStyle(inkDim)
                            .symbolRenderingMode(.multicolor)
                    }
                }
            }
            Text(connectionWords)
                .font(.caption)
                .foregroundStyle(model.reachable == false ? Theme.rose : inkFaint)
        }
    }

    // MARK: Right

    /// A hero line when something's pressing, then one panel, then where in
    /// the rotation it is.
    @ViewBuilder
    private var right: some View {
        if let snapshot = model.snapshot {
            let panels = KioskPlan.panels(snapshot: snapshot)
            let showing = KioskPlan.showing(panels, turn: turn, count: 1)
            VStack(alignment: .leading, spacing: 32) {
                hero(snapshot)
                ZStack(alignment: .topLeading) {
                    ForEach(showing, id: \.self) { panel in
                        bigPanel(panel, snapshot: snapshot)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .offset(x: 24)),
                                removal: .opacity.combined(with: .offset(x: -24))
                            ))
                    }
                }
                if panels.count > 1 {
                    HStack(spacing: 10) {
                        ForEach(Array(panels.enumerated()), id: \.offset) { index, _ in
                            Circle()
                                .fill(index == turn % panels.count ? ink : inkFaint.opacity(0.5))
                                .frame(width: 10, height: 10)
                        }
                    }
                    // Centred under the panel, however many there are.
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
                }
            }
        } else {
            HStack(spacing: 16) {
                ProgressView()
                Text("Jarvis is thinking…").foregroundStyle(inkDim)
            }
        }
    }

    /// An alert or something starting soon, above the rotating panel.
    @ViewBuilder
    private func hero(_ snapshot: Snapshot) -> some View {
        switch KioskPlan.hero(snapshot: snapshot, pending: []) {
        case .alert(let name, let status):
            Label("\(name) is \(status)", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(Theme.ember)
        case .soon(let title, let minutes):
            Label(minutes <= 0 ? "\(title) is starting" : "\(title) in \(minutes) min", systemImage: "calendar.badge.clock")
                .font(.headline)
                .foregroundStyle(Theme.glacier)
        default:
            if let greeting = snapshot.offers?.greeting {
                // A short headline ("Late night, Dylan"), then the rest
                // smaller and dimmer, clamped (TodayWording.greetingParts).
                let parts = TodayWording.greetingParts(greeting)
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(KioskIcons.greetingEmoji(hour: Calendar.current.component(.hour, from: SunLampPreview.now()))) \(parts.headline)")
                        .font(.headline.weight(.medium))
                        .foregroundStyle(ink)
                    if let body = parts.body {
                        Text(body)
                            .font(.callout)
                            .foregroundStyle(inkDim)
                            .lineLimit(3)
                            .frame(maxWidth: 760, alignment: .leading)
                    }
                }
            }
        }
    }

    /// One panel, roomy and readable from the couch. Never money.
    @ViewBuilder
    private func bigPanel(_ panel: KioskPanel, snapshot: Snapshot) -> some View {
        switch panel {
        case .schedule:
            card("Today", icon: "calendar") {
                if snapshot.today.isEmpty {
                    Text("Nothing booked").foregroundStyle(inkDim)
                }
                ForEach(snapshot.today.prefix(7)) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 22) {
                        Image(systemName: KioskIcons.agendaSymbol(item.title))
                            .foregroundStyle(Theme.glacier)
                            .frame(width: 36)
                        Text(AgendaTime.label(at: item.at, allDay: item.allDay ?? false))
                            .foregroundStyle(Theme.glacier)
                            .monospacedDigit()
                            .frame(width: 140, alignment: .leading)
                        Text(item.title)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if snapshot.today.count > 7 {
                    Text("+\(snapshot.today.count - 7) more").foregroundStyle(inkDim)
                }
            }
        case .home:
            card("Home", icon: "house.fill") {
                if let thermostat = snapshot.thermostat {
                    row(thermostat.name, TodayWording.deviceState(thermostat), symbol: TodayWording.deviceSymbol(thermostat))
                }
                let on = snapshot.homeTiles.filter { $0.isOn && $0.kind != "climate" }
                let lights = snapshot.homeTiles.filter { $0.kind == "light" }
                if !lights.isEmpty {
                    row("Lights", "\(lights.filter(\.isOn).count) of \(lights.count) on", symbol: "lightbulb.fill")
                }
                ForEach(on.filter { $0.kind != "light" }.prefix(3)) { device in
                    row(device.name, TodayWording.deviceState(device), symbol: TodayWording.deviceSymbol(device))
                }
            }
        case .work:
            card("Jarvis is working on", icon: "sparkles") {
                ForEach((snapshot.jobs?.running ?? []).prefix(3)) { task in
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        Circle().fill(OrbView.workAmber).frame(width: 14, height: 14)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(task.label).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                            Text(task.runningWords()).font(.caption).foregroundStyle(inkDim)
                        }
                    }
                }
            }
        case .health:
            card("You", icon: "heart.fill") {
                HStack(spacing: 60) {
                    if let asleep = snapshot.health?.sleep?.asleepMin {
                        stat(TodayWording.hours(asleep), "asleep last night", symbol: "bed.double.fill")
                    }
                    if let steps = snapshot.health?.yesterday?.steps {
                        stat(steps.formatted(), "steps yesterday", symbol: "figure.walk")
                    }
                }
            }
        case .offers:
            card("From Jarvis", icon: "lightbulb.fill") {
                ForEach((snapshot.offers?.offers ?? []).prefix(4)) { offer in
                    HStack(alignment: .firstTextBaseline, spacing: 18) {
                        Image(systemName: "sparkle").foregroundStyle(Theme.ember).frame(width: 36)
                        Text(offer.title).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    /// "On Tailscale · jarvis", or what's wrong.
    private var connectionWords: String {
        switch model.reachable {
        case .some(true): return "On Tailscale · jarvis"
        case .some(false): return "Can’t reach Jarvis. Is Tailscale on for this Apple TV?"
        case .none: return "Connecting…"
        }
    }

    /// A roomy titled glass panel with large type.
    private func card<Rows: View>(_ title: String, icon: String, @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: icon)
                .font(.callout.weight(.semibold))
                .foregroundStyle(inkDim)
            rows()
                .font(.body)
                .foregroundStyle(ink)
                // Shrinks a step rather than clipping when a panel is full.
                .minimumScaleFactor(0.85)
        }
        .padding(34)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            // Frosted white by day so dark text reads; glass at night.
            if lamp.brightness > 0.55 {
                RoundedRectangle(cornerRadius: 34, style: .continuous).fill(Color.white.opacity(0.55))
            }
        }
        .glassPanel(radius: 34)
    }

    /// An icon, a name on the left, its value on the right.
    private func row(_ name: String, _ value: String, symbol: String? = nil) -> some View {
        HStack(spacing: 18) {
            if let symbol {
                Image(systemName: symbol)
                    .foregroundStyle(Theme.ember)
                    .frame(width: 36)
            }
            Text(name)
            Spacer()
            Text(value).foregroundStyle(inkDim)
        }
    }

    /// An icon, a big number, and a caption.
    private func stat(_ value: String, _ caption: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol).font(.title3).foregroundStyle(Theme.glacier)
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

    /// A top-to-bottom gradient mixed from the lamp's brightness and warmth.
    var body: some View {
        LinearGradient(colors: [color(top: true), color(top: false)], startPoint: .top, endPoint: .bottom)
    }

    /// One end of the gradient.
    private func color(top: Bool) -> Color {
        let b = lamp.brightness, w = lamp.warmth
        // Night ink, daylight sky, and the warm glow, as RGB.
        let night = top ? (0.02, 0.025, 0.04) : (0.035, 0.045, 0.07)
        let day = top ? (0.86, 0.91, 0.96) : (0.97, 0.94, 0.88)
        // Warm runs deep red when dim, amber, then gold as it brightens.
        let warm = (min(1, 0.55 + b * 0.5), 0.12 + b * 0.62, 0.04 + b * 0.32)
        func mix(_ a: Double, _ c: Double, _ t: Double) -> Double { a + (c - a) * t }
        let base = (mix(night.0, day.0, b), mix(night.1, day.1, b), mix(night.2, day.2, b))
        let glow = w * (top ? 0.75 : 1)
        let lit = min(1, b * 3)
        return Color(
            red: mix(base.0, warm.0 * lit, glow),
            green: mix(base.1, warm.1 * lit, glow),
            blue: mix(base.2, warm.2 * lit, glow)
        )
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

    /// Now, or the fast-forward clock's now.
    static func now(at real: Date = Date()) -> Date {
        guard enabled else { return real }
        let dawn = Calendar.current.date(bySettingHour: 5, minute: 30, second: 0, of: started) ?? started
        return dawn.addingTimeInterval(real.timeIntervalSince(started) * 720)
    }
}
