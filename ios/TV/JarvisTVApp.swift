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
        }
    }
}

struct AlwaysOnView: View {
    @StateObject private var model = AlwaysOnModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Which turn of the panel rotation is showing.
    @State private var turn = 0

    /// The orb and the time on the left; one roomy panel at a time on the
    /// right, cross-fading every 20 s (Dylan, 2026-11-17: the right was
    /// cluttered and not dynamic enough for a kiosk).
    var body: some View {
        ZStack {
            Theme.sky.ignoresSafeArea()
            HStack(alignment: .center, spacing: 80) {
                left.frame(maxWidth: .infinity)
                right.frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(80)
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
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    // MARK: Left

    /// The orb, the time and the date, the weather and the sun, and the
    /// connection line.
    private var left: some View {
        VStack(spacing: 26) {
            OrbView(state: model.snapshot?.jobs?.running.isEmpty == false ? .working : .listening, size: 400, work: model.snapshot?.jobs?.running ?? [], tappable: false)
            TimelineView(.everyMinute) { context in
                VStack(spacing: 8) {
                    Text(context.date, format: .dateTime.hour().minute())
                        .font(.system(size: 104, weight: .light, design: .rounded))
                        .monospacedDigit()
                    Text(context.date, format: .dateTime.weekday(.wide).month(.wide).day())
                        .font(.title3)
                        .foregroundStyle(Theme.frostDim)
                    if let weather = model.snapshot?.home?.weather {
                        Label(weatherText(weather), systemImage: TodayWording.weatherSymbol(weather.condition))
                            .font(.headline)
                            .foregroundStyle(Theme.frostDim)
                            .symbolRenderingMode(.multicolor)
                            .padding(.top, 6)
                    }
                    if let sun = model.snapshot?.home?.sun,
                       let line = TodayWording.sunLine(rising: sun.rising, setting: sun.setting, now: context.date) {
                        Label(line, systemImage: "sun.horizon.fill")
                            .font(.headline)
                            .foregroundStyle(Theme.frostDim)
                            .symbolRenderingMode(.multicolor)
                    }
                }
            }
            Text(connectionWords)
                .font(.caption)
                .foregroundStyle(model.reachable == false ? Theme.rose : Theme.frostFaint)
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
                                .fill(index == turn % panels.count ? Theme.frost : Theme.frostFaint.opacity(0.5))
                                .frame(width: 10, height: 10)
                        }
                    }
                    .accessibilityHidden(true)
                }
            }
        } else {
            HStack(spacing: 16) {
                ProgressView()
                Text("Jarvis is thinking…").foregroundStyle(Theme.frostDim)
            }
        }
    }

    /// An alert or something starting soon, above the rotating panel.
    @ViewBuilder
    private func hero(_ snapshot: Snapshot) -> some View {
        switch KioskPlan.hero(snapshot: snapshot, pending: []) {
        case .alert(let name, let status):
            Label("\(name) is \(status)", systemImage: "exclamationmark.triangle.fill")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.ember)
        case .soon(let title, let minutes):
            Label(minutes <= 0 ? "\(title) is starting" : "\(title) in \(minutes) min", systemImage: "calendar.badge.clock")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.glacier)
        default:
            if let greeting = snapshot.offers?.greeting {
                Text(greeting).font(.title2).foregroundStyle(Theme.frost.opacity(0.9))
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
                    Text("Nothing booked").foregroundStyle(Theme.frostDim)
                }
                ForEach(snapshot.today.prefix(5)) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 28) {
                        Text(AgendaTime.label(at: item.at, allDay: item.allDay ?? false))
                            .foregroundStyle(Theme.glacier)
                            .monospacedDigit()
                            .frame(width: 190, alignment: .leading)
                        Text(item.title).lineLimit(1)
                    }
                }
            }
        case .home:
            card("Home", icon: "house.fill") {
                if let thermostat = snapshot.thermostat {
                    row(thermostat.name, TodayWording.deviceState(thermostat))
                }
                let on = snapshot.homeTiles.filter { $0.isOn && $0.kind != "climate" }
                let lights = snapshot.homeTiles.filter { $0.kind == "light" }
                if !lights.isEmpty {
                    row("Lights", "\(lights.filter(\.isOn).count) of \(lights.count) on")
                }
                ForEach(on.filter { $0.kind != "light" }.prefix(3)) { device in
                    row(device.name, TodayWording.deviceState(device))
                }
            }
        case .work:
            card("Jarvis is working on", icon: "sparkles") {
                ForEach((snapshot.jobs?.running ?? []).prefix(3)) { task in
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        Circle().fill(OrbView.workAmber).frame(width: 14, height: 14)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(task.label).lineLimit(2)
                            Text(task.runningWords()).font(.callout).foregroundStyle(Theme.frostDim)
                        }
                    }
                }
            }
        case .health:
            card("You", icon: "heart.fill") {
                HStack(spacing: 60) {
                    if let asleep = snapshot.health?.sleep?.asleepMin {
                        stat(TodayWording.hours(asleep), "asleep last night")
                    }
                    if let steps = snapshot.health?.yesterday?.steps {
                        stat(steps.formatted(), "steps yesterday")
                    }
                }
            }
        case .offers:
            card("From Jarvis", icon: "lightbulb.fill") {
                ForEach((snapshot.offers?.offers ?? []).prefix(3)) { offer in
                    Text(offer.title).lineLimit(2)
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
        VStack(alignment: .leading, spacing: 22) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(Theme.frostDim)
            rows()
                .font(.title2)
        }
        .padding(40)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(radius: 34)
    }

    /// A name on the left, its value on the right.
    private func row(_ name: String, _ value: String) -> some View {
        HStack {
            Text(name)
            Spacer()
            Text(value).foregroundStyle(Theme.frostDim)
        }
    }

    /// A big number over a caption.
    private func stat(_ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value).font(.system(size: 64, weight: .bold, design: .rounded)).monospacedDigit()
            Text(caption).font(.headline).foregroundStyle(Theme.frostDim)
        }
    }

    /// "Clear, 61°F", or just the condition when there's no number.
    private func weatherText(_ weather: Weather) -> String {
        guard let temperature = weather.temperature else { return weather.condition.capitalized }
        return "\(weather.condition.capitalized), \(Int(temperature.rounded()))\(weather.unit)"
    }
}
