// The Today tab: Jarvis's greeting, his offers, what's next, the house,
// and what he's working on. Reads the home page's snapshot.
import SwiftUI
import JarvisKit

@MainActor
final class TodayModel: ObservableObject {
    @Published private(set) var snapshot: Snapshot?
    @Published private(set) var loading = false
    @Published var problem: String?
    /// Offers hidden here, so they vanish before the next snapshot drops them.
    @Published private(set) var hidden: Set<String> = []

    /// Fetches the snapshot; keeps the last one on screen if this fails.
    func load(app: AppModel) async {
        loading = true
        do {
            snapshot = try await app.client.snapshot()
            problem = nil
            app.noteReach(nil)
        } catch {
            problem = error.localizedDescription
            app.noteReach(error)
        }
        loading = false
    }

    /// Hide on an offer card.
    func hide(_ offer: Offer, app: AppModel) async {
        hidden.insert(offer.id)
        do {
            try await app.client.hideOffer(offer.id)
        } catch {
            hidden.remove(offer.id)
            problem = error.localizedDescription
        }
    }

    /// Offers still showing.
    var offers: [Offer] {
        (snapshot?.offers?.offers ?? []).filter { !hidden.contains($0.id) }
    }
}

struct TodayView: View {
    @EnvironmentObject private var app: AppModel
    @ObservedObject var today: TodayModel

    /// Status line over a scrolling column of panels. Refreshes every 15 s
    /// while showing, like the page.
    var body: some View {
        ZStack {
            Theme.sky.ignoresSafeArea()
            VStack(spacing: 0) {
                StatusLine()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        content
                    }
                    .padding(16)
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                }
                .refreshable { await today.load(app: app) }
            }
        }
        .task {
            while !Task.isCancelled {
                await today.load(app: app)
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    /// The panels, or a labelled spinner on the very first load.
    @ViewBuilder
    private var content: some View {
        if let problem = today.problem {
            Text(problem).font(.footnote).foregroundStyle(Theme.rose)
        }
        if let snapshot = today.snapshot {
            if let greeting = snapshot.offers?.greeting {
                Text(greeting).font(.title3).foregroundStyle(Theme.frost.opacity(0.85))
            }
            ForEach(snapshot.alerts) { service in
                Label("\(service.name) is \(service.status)", systemImage: "exclamationmark.triangle")
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassPanel(tint: Theme.ember)
            }
            ForEach(today.offers) { offer in
                offerCard(offer)
            }
            agenda(snapshot.today)
            if let home = snapshot.home {
                house(home, thermostat: snapshot.thermostat)
            }
            if let running = snapshot.jobs?.running, !running.isEmpty {
                panel("Jarvis is working on") {
                    ForEach(running) { task in
                        row { Text(task.label) }
                    }
                }
            }
        } else if today.loading {
            HStack(spacing: 10) {
                ProgressView()
                Text("Asking Jarvis…").foregroundStyle(Theme.frostDim)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 80)
        }
    }

    /// One of Jarvis's offers, with Hide and Start.
    private func offerCard(_ offer: Offer) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("From Jarvis").font(.footnote.weight(.semibold)).foregroundStyle(Theme.glacier)
            Text(offer.title).font(.headline)
            Text(offer.body).foregroundStyle(Theme.frostDim)
            HStack(spacing: 10) {
                Button { Task { await today.hide(offer, app: app) } } label: {
                    Text("Hide").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(Theme.frost)
                Button { app.start(offer) } label: {
                    Text("Start").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.glacier)
                .foregroundStyle(Theme.basalt)
            }
            .font(.body.weight(.semibold))
        }
        .padding(14)
        .glassPanel(tint: Theme.glacier)
    }

    /// Today's agenda, or a plain "nothing booked".
    private func agenda(_ items: [AgendaItem]) -> some View {
        panel("Agenda") {
            if items.isEmpty {
                row { Text("Nothing booked").foregroundStyle(Theme.frostDim) }
            }
            ForEach(items) { item in
                row {
                    Text(AgendaTime.label(at: item.at, allDay: item.allDay ?? false))
                        .foregroundStyle(Theme.glacier)
                        .frame(width: 84, alignment: .leading)
                    Text(item.title)
                }
            }
        }
    }

    /// Weather and the thermostat.
    private func house(_ home: Home, thermostat: Device?) -> some View {
        panel("Home") {
            if let weather = home.weather {
                row {
                    Text("Outside")
                    Spacer()
                    Text(weatherText(weather)).foregroundStyle(Theme.frostDim)
                }
            }
            if let thermostat {
                row {
                    Text(thermostat.name)
                    Spacer()
                    Text(thermostatText(thermostat)).foregroundStyle(Theme.frostDim)
                }
            }
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

    /// A titled glass panel of rows.
    private func panel<Rows: View>(_ title: String, @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(Theme.frostDim)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 4)
            rows()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel()
    }

    /// One 52 pt row inside a panel.
    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 12) { content() }
            .frame(minHeight: 52)
            .padding(.horizontal, 16)
    }
}
