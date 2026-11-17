// Jarvis on Apple TV: the always-on display. A big orb and the time on the
// left; his greeting, what's next, the house and what he's working on on
// the right. Refreshes every 15 s like the page, and keeps the TV from
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

    /// Two columns over the night sky; a waiting line on the very first load.
    var body: some View {
        ZStack {
            Theme.sky.ignoresSafeArea()
            HStack(alignment: .center, spacing: 80) {
                left.frame(maxWidth: .infinity)
                right.frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(80)
        }
        .task {
            while !Task.isCancelled {
                await model.load()
                try? await Task.sleep(for: .seconds(15))
            }
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    /// The orb, the time and the date, and the connection line.
    private var left: some View {
        VStack(spacing: 28) {
            OrbView(state: model.snapshot?.jobs?.running.isEmpty == false ? .working : .listening, size: 420, work: model.snapshot?.jobs?.running ?? [], tappable: false)
            TimelineView(.everyMinute) { context in
                VStack(spacing: 6) {
                    Text(context.date, format: .dateTime.hour().minute())
                        .font(.system(size: 96, weight: .light))
                        .monospacedDigit()
                    Text(context.date, format: .dateTime.weekday(.wide).month(.wide).day())
                        .font(.title3)
                        .foregroundStyle(Theme.frostDim)
                }
            }
            Text(connectionWords)
                .font(.caption)
                .foregroundStyle(model.reachable == false ? Theme.rose : Theme.frostFaint)
        }
    }

    /// Greeting, alerts, agenda, the house, background work.
    @ViewBuilder
    private var right: some View {
        if let snapshot = model.snapshot {
            VStack(alignment: .leading, spacing: 28) {
                if let greeting = snapshot.offers?.greeting {
                    Text(greeting).font(.title2).foregroundStyle(Theme.frost.opacity(0.9))
                }
                ForEach(snapshot.alerts) { service in
                    Label("\(service.name) is \(service.status)", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Theme.ember)
                }
                panel("Today") {
                    if snapshot.today.isEmpty {
                        Text("Nothing booked").foregroundStyle(Theme.frostDim)
                    }
                    ForEach(snapshot.today.prefix(6)) { item in
                        HStack(alignment: .firstTextBaseline, spacing: 24) {
                            Text(AgendaTime.label(at: item.at, allDay: item.allDay ?? false))
                                .foregroundStyle(Theme.glacier)
                                .frame(width: 180, alignment: .leading)
                            Text(item.title).lineLimit(1)
                        }
                    }
                }
                if let home = snapshot.home {
                    panel("Home") {
                        if let weather = home.weather {
                            row("Outside", weatherText(weather))
                        }
                        if let thermostat = snapshot.thermostat {
                            row(thermostat.name, thermostatText(thermostat))
                        }
                    }
                }
                if let running = snapshot.jobs?.running, !running.isEmpty {
                    panel("Jarvis is working on") {
                        ForEach(running) { task in Text(task.label).lineLimit(1) }
                    }
                }
            }
        } else {
            HStack(spacing: 16) {
                ProgressView()
                Text("Jarvis is thinking…").foregroundStyle(Theme.frostDim)
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

    /// A titled glass panel.
    private func panel<Rows: View>(_ title: String, @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .tracking(1)
                .foregroundStyle(Theme.frostDim)
            rows()
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel()
    }

    /// A name on the left, its value on the right.
    private func row(_ name: String, _ value: String) -> some View {
        HStack {
            Text(name)
            Spacer()
            Text(value).foregroundStyle(Theme.frostDim)
        }
    }

    /// "Clear, 61°F", or just the condition when there's no number.
    private func weatherText(_ weather: Weather) -> String {
        guard let temperature = weather.temperature else { return weather.condition.capitalized }
        return "\(weather.condition.capitalized), \(Int(temperature.rounded()))\(weather.unit)"
    }

    /// "68° · heat to 70°".
    private func thermostatText(_ device: Device) -> String {
        var parts: [String] = []
        if let current = device.current { parts.append("\(Int(current.rounded()))°") }
        if let target = device.target { parts.append("\(device.state) to \(Int(target.rounded()))°") }
        if parts.isEmpty { return device.state }
        return parts.joined(separator: " · ")
    }
}
