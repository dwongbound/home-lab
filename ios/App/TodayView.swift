// The Today tab (Dylan, 2026-11-17): a greeting with the weather, alerts,
// Jarvis's suggestions folded away like the page's, then the house, money,
// last night's sleep and what Jarvis is working on. No agenda. Everything
// sits on Liquid Glass over the night sky, in SF Pro Rounded.
import SwiftUI
import JarvisKit

@MainActor
final class TodayModel: ObservableObject {
    @Published private(set) var snapshot: Snapshot?
    @Published private(set) var loading = false
    @Published var problem: String?
    /// Offers hidden here, so they vanish before the next snapshot drops them.
    @Published private(set) var hidden: Set<String> = []
    /// Jarvis's suggestions start folded, like the home page's (OfferCards).
    @Published var offersOpen = false

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

    /// Status line over a scrolling column of cards. Refreshes every 15 s
    /// while showing, like the page.
    var body: some View {
        ZStack {
            Theme.sky.ignoresSafeArea()
            VStack(spacing: 0) {
                StatusLine()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        content
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                }
                .refreshable { await today.load(app: app) }
            }
        }
        .fontDesign(.rounded)

    }

    /// The cards, or a labelled spinner on the very first load.
    @ViewBuilder
    private var content: some View {
        if let problem = today.problem {
            Text(problem).font(.footnote).foregroundStyle(Theme.rose)
        }
        if let snapshot = today.snapshot {
            hero(snapshot)
            ForEach(snapshot.alerts) { service in
                Label("\(service.name) is \(service.status)", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.ember)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassPanel(tint: Theme.ember, radius: 18)
            }
            if !today.offers.isEmpty {
                suggestions
            }
            if !snapshot.homeTiles.isEmpty {
                homeCard(snapshot.homeTiles)
            }
            if let money = snapshot.money {
                if app.moneyUnlocked {
                    moneyCard(money)
                } else {
                    lockedMoney
                }
            }
            if let health = snapshot.health, health.sleep?.asleepMin != nil || health.yesterday?.steps != nil {
                healthCard(health)
            }
            if let running = snapshot.jobs?.running, !running.isEmpty {
                card("Jarvis is working on", icon: "sparkles") {
                    ForEach(running) { task in
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small).tint(Theme.ember)
                            Text(task.label).font(.subheadline)
                        }
                    }
                }
            }
        } else if today.loading {
            HStack(spacing: 10) {
                ProgressView()
                Text("Jarvis is thinking…").foregroundStyle(Theme.frostDim)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 80)
        }
    }

    // MARK: Hero

    /// "Good evening" in large type, the date, and the weather with sunset.
    private func hero(_ snapshot: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()).uppercased())
                .font(.caption.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(Theme.glacier)
            Text(snapshot.offers?.greeting ?? TodayWording.greeting(for: .now))
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.frost)
            if let weather = snapshot.home?.weather {
                HStack(spacing: 14) {
                    Label(weatherText(weather), systemImage: TodayWording.weatherSymbol(weather.condition))
                    if let sunset = TodayWording.time(snapshot.home?.sun?.setting) {
                        Label(sunset, systemImage: "sunset.fill")
                    }
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.frostDim)
                .symbolRenderingMode(.multicolor)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    // MARK: Suggestions

    /// "3 suggestions from Jarvis", folded until tapped.
    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.snappy) { today.offersOpen.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Theme.glacier)
                    Text(today.offers.count == 1 ? "1 suggestion from Jarvis" : "\(today.offers.count) suggestions from Jarvis")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .rotationEffect(.degrees(today.offersOpen ? 180 : 0))
                        .foregroundStyle(Theme.frostDim)
                }
                .frame(minHeight: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(today.offersOpen ? "Hides them" : "Shows them")
            if today.offersOpen {
                ForEach(today.offers) { offer in
                    offerRow(offer)
                    if offer.id != today.offers.last?.id { Divider().overlay(Theme.glassEdge) }
                }
            }
        }
        .padding(16)
        .glassPanel(tint: Theme.glacier)
    }

    /// One suggestion, with Hide and Start.
    private func offerRow(_ offer: Offer) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(offer.title).font(.headline)
            Text(offer.body).font(.subheadline).foregroundStyle(Theme.frostDim)
            HStack(spacing: 10) {
                Button { Task { await today.hide(offer, app: app) } } label: {
                    Text("Hide").frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.bordered)
                .tint(Theme.frost)
                Button { app.start(offer) } label: {
                    Text("Start").frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.glacier)
                .foregroundStyle(Theme.basalt)
            }
            .font(.subheadline.weight(.semibold))
        }
    }

    // MARK: Home

    /// The devices that answer, as a grid of glass tiles: lit ones glow.
    private func homeCard(_ devices: [Device]) -> some View {
        let lights = devices.filter { $0.kind == "light" }
        let lit = lights.filter(\.isOn).count
        return card("Home", icon: "house.fill", trailing: lights.isEmpty ? nil : "\(lit) of \(lights.count) lights on") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                ForEach(devices) { device in
                    deviceTile(device)
                }
            }
        }
    }

    /// One device: its symbol, name and state.
    private func deviceTile(_ device: Device) -> some View {
        let on = device.isOn
        return HStack(spacing: 10) {
            Image(systemName: TodayWording.deviceSymbol(device))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(on ? Theme.ember : Theme.frostFaint)
                .frame(width: 30, height: 30)
                .background(Circle().fill(on ? Theme.ember.opacity(0.18) : Color.white.opacity(0.06)))
            VStack(alignment: .leading, spacing: 1) {
                Text(device.name)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                Text(TodayWording.deviceState(device))
                    .font(.caption)
                    .foregroundStyle(Theme.frostDim)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(on ? Theme.ember.opacity(0.08) : Color.white.opacity(0.04))
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: Money

    /// Money before Face ID: blurred stand-in figures and a "Show" button,
    /// so nothing real is on screen until Dylan unlocks it.
    private var lockedMoney: some View {
        card("Money", icon: "creditcard.fill") {
            ZStack {
                VStack(alignment: .leading, spacing: 10) {
                    Text("$000,000").font(.system(size: 26, weight: .bold, design: .rounded))
                    Capsule().fill(Color.white.opacity(0.15)).frame(height: 6)
                    Text("$0,000 of $0,000 this month").font(.subheadline)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .blur(radius: 9)
                .accessibilityHidden(true)
                Button {
                    Task { await app.unlockMoney() }
                } label: {
                    Label("Show", systemImage: "faceid")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Theme.glacier))
                        .foregroundStyle(Theme.basalt)
                }
                .accessibilityLabel("Show money details")
            }
        }
    }

    /// Net worth, this month against budget, what's over, and Jarvis's notes.
    private func moneyCard(_ money: Money) -> some View {
        card("Money", icon: "creditcard.fill") {
            HStack(alignment: .firstTextBaseline) {
                if let worth = money.netWorth {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(TodayWording.dollars(worth))
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text("Net worth").font(.caption).foregroundStyle(Theme.frostDim)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(TodayWording.dollars(money.cardDebt))
                        .font(.headline)
                        .monospacedDigit()
                    Text("On cards").font(.caption).foregroundStyle(Theme.frostDim)
                }
            }
            if let spending = money.spending {
                spendingBar(spending)
            }
            if !money.overBudget.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(money.overBudget.prefix(3), id: \.name) { category in
                        HStack {
                            Circle().fill(Theme.rose).frame(width: 6, height: 6)
                            Text(category.name).font(.subheadline)
                            Spacer()
                            Text("\(TodayWording.dollars(category.spent)) of \(TodayWording.dollars(category.budget ?? 0))")
                                .font(.subheadline)
                                .monospacedDigit()
                                .foregroundStyle(Theme.rose)
                        }
                    }
                }
            }
            if let flag = money.flags.first {
                Label(flag.text, systemImage: "sparkles")
                    .font(.footnote)
                    .foregroundStyle(Theme.frostDim)
            }
        }
    }

    /// "Spent $6,008 of $3,996" with a bar that turns rose past the budget.
    private func spendingBar(_ spending: Money.Spending) -> some View {
        let budget = spending.budget ?? 0
        let fraction = budget > 0 ? spending.thisMonth / budget : 0
        let over = budget > 0 && spending.thisMonth > budget
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("This month").font(.subheadline)
                Spacer()
                Text(budget > 0 ? "\(TodayWording.dollars(spending.thisMonth)) of \(TodayWording.dollars(budget))" : TodayWording.dollars(spending.thisMonth))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(over ? Theme.rose : Theme.frost)
            }
            if budget > 0 {
                GeometryReader { area in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08))
                        Capsule()
                            .fill(over ? Theme.rose : Theme.glacier)
                            .frame(width: area.size.width * min(fraction, 1))
                    }
                }
                .frame(height: 6)
            }
            if let last = spending.lastMonthToDate {
                Text("\(TodayWording.dollars(last)) by this point last month")
                    .font(.caption)
                    .foregroundStyle(Theme.frostFaint)
            }
        }
    }

    // MARK: Health

    /// Last night's sleep and yesterday's steps, side by side.
    private func healthCard(_ health: Health) -> some View {
        card("You", icon: "heart.fill") {
            HStack(spacing: 10) {
                if let asleep = health.sleep?.asleepMin {
                    stat(TodayWording.hours(asleep), "Asleep last night", symbol: "bed.double.fill", tint: Color(red: 0.73, green: 0.65, blue: 0.94))
                }
                if let steps = health.yesterday?.steps {
                    stat(steps.formatted(), "Steps yesterday", symbol: "figure.walk", tint: Theme.moss)
                }
            }
        }
    }

    /// One big number with a caption.
    private func stat(_ value: String, _ caption: String, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text(caption).font(.caption).foregroundStyle(Theme.frostDim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.04)))
    }

    // MARK: Pieces

    /// "Cloudy, 58°F".
    private func weatherText(_ weather: Weather) -> String {
        guard let temperature = weather.temperature else { return weather.condition.capitalized }
        return "\(weather.condition.capitalized), \(Int(temperature.rounded()))\(weather.unit)"
    }

    /// A glass card with a small header (symbol, title, optional note).
    private func card<Body: View>(_ title: String, icon: String, trailing: String? = nil, @ViewBuilder body: () -> Body) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.glacier)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let trailing {
                    Text(trailing).font(.caption).foregroundStyle(Theme.frostDim)
                }
            }
            body()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel()
    }
}

/// The small wordings Today needs: greeting, money, hours, device states.
enum TodayWording {
    /// "Good morning" until noon, "Good afternoon" until 5, then "Good evening".
    static func greeting(for date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        if hour < 5 { return "Good evening" }
        if hour < 12 { return "Good morning" }
        if hour < 17 { return "Good afternoon" }
        return "Good evening"
    }

    /// "$127,313" (no cents: Today is a glance).
    static func dollars(_ amount: Double) -> String {
        amount.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }

    /// 422 minutes as "7h 2m".
    static func hours(_ minutes: Int) -> String {
        "\(minutes / 60)h \(minutes % 60)m"
    }

    /// An ISO time as "4:48 PM" in the phone's zone.
    static func time(_ iso: String?) -> String? {
        guard let iso, let date = ISO8601DateFormatter().date(from: iso) else { return nil }
        return date.formatted(date: .omitted, time: .shortened)
    }

    /// An SF Symbol for Home Assistant's weather words.
    static func weatherSymbol(_ condition: String) -> String {
        switch condition.lowercased() {
        case let c where c.contains("sun") || c.contains("clear"): return "sun.max.fill"
        case let c where c.contains("partly"): return "cloud.sun.fill"
        case let c where c.contains("rain") || c.contains("pour"): return "cloud.rain.fill"
        case let c where c.contains("snow"): return "cloud.snow.fill"
        case let c where c.contains("fog"): return "cloud.fog.fill"
        case let c where c.contains("lightning") || c.contains("storm"): return "cloud.bolt.rain.fill"
        case let c where c.contains("wind"): return "wind"
        default: return "cloud.fill"
        }
    }

    /// An SF Symbol per kind of device.
    static func deviceSymbol(_ device: Device) -> String {
        switch device.kind {
        case "light": return device.isOn ? "lightbulb.fill" : "lightbulb"
        case "climate": return "thermometer.medium"
        case "media": return device.name.lowercased().contains("tv") ? "tv.fill" : "hifispeaker.fill"
        case "lock": return device.isOn ? "lock.open.fill" : "lock.fill"
        case "fan": return "fan.fill"
        case "cover": return "blinds.vertical.closed"
        default: return device.name.lowercased().contains("asleep") ? "moon.fill" : "switch.2"
        }
    }

    /// "On", "Off", "68° · heat to 70°", "Playing".
    static func deviceState(_ device: Device) -> String {
        if device.kind == "climate" {
            var parts: [String] = []
            if let current = device.current { parts.append("\(Int(current.rounded()))°") }
            if let target = device.target, device.state != "off" {
                parts.append("\(device.state) to \(Int(target.rounded()))°")
            } else {
                parts.append(device.state.capitalized)
            }
            return parts.joined(separator: " · ")
        }
        return device.state.replacingOccurrences(of: "_", with: " ").capitalized
    }
}
