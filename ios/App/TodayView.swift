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
        #if DEBUG
        // `-demoSnapshot` shows the sample data even when Jarvis answers.
        if let demo = DemoSnapshot.snapshot { snapshot = demo; loading = false; return }
        #endif
        do {
            snapshot = try await app.client.snapshot()
            // The Watch's board and complications follow every snapshot.
            WatchBridge.shared.push(snapshot)
            problem = nil
            app.noteReach(nil)
        } catch {
            problem = error.localizedDescription
            app.noteReach(error)
            #if DEBUG
            if snapshot == nil, let demo = DemoSnapshot.snapshot { snapshot = demo }
            #endif
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
    /// True once the greeting's body has been tapped open.
    @State private var greetingOpen = false
    /// The report waiting on "Delete this report?".
    @State private var deleting: Report?
    /// True once "Show all" has been tapped on the Reports card.
    @State private var allReports = false
    /// True while the Diet screen is up.
    @State private var showingDiet = false

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
            // A Keep or Delete waiting on the PC: labelled and blocking.
            if let busy = app.reportBusy, app.report == nil {
                Color.black.opacity(0.35).ignoresSafeArea()
                VStack(spacing: 14) {
                    ProgressView().controlSize(.large).tint(Theme.frost)
                    Text(busy).font(.headline).foregroundStyle(Theme.frost)
                }
                .padding(28)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.ultraThinMaterial))
            }
        }
        .sheet(isPresented: $showingDiet) {
            DietView().environmentObject(app)
        }
        .confirmationDialog("Delete this report?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible, presenting: deleting) { report in
            Button("Delete", role: .destructive) { Task { await app.deleteReport(report.id) } }
            Button("Close", role: .cancel) {}
        } message: { report in
            Text("“\(report.title)” goes for good, here and on the PC.")
        }
        .fontDesign(.rounded)
        #if DEBUG
        .onAppear { if ProcessInfo.processInfo.arguments.contains("-openKiosk") { app.padKiosk = true } }
        #endif

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
            dietCard(snapshot.nutrition)
            if let health = snapshot.health, health.sleep?.asleepMin != nil || health.yesterday?.steps != nil {
                healthCard(health)
            }
            if let shelf = app.reportShelf {
                reportsCard(shelf)
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
            HStack {
                Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()).uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.glacier)
                Spacer()
                if UIDevice.current.userInterfaceIdiom == .pad {
                    // The iPad's always-on room display.
                    Button { app.padKiosk = true } label: {
                        Label("Kiosk", systemImage: "rectangle.expand.vertical")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)
                            .glassPanel(radius: 22)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open kiosk mode")
                }
            }
            greetingBlock(snapshot.offers?.greeting ?? TodayWording.greeting(for: .now))
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

    /// Jarvis's greeting as an emoji and a short headline, with the rest
    /// smaller and dimmer underneath, three lines until tapped (Dylan,
    /// 2026-11-17: "very wordy"; same split as the TV, TodayWording.greetingParts).
    private func greetingBlock(_ text: String) -> some View {
        let parts = TodayWording.greetingParts(text)
        return VStack(alignment: .leading, spacing: 4) {
            Text("\(KioskIcons.greetingEmoji(hour: Calendar.current.component(.hour, from: .now))) \(parts.headline)")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.frost)
            if let body = parts.body {
                Text(body)
                    .font(.subheadline)
                    .foregroundStyle(Theme.frostDim)
                    .lineLimit(greetingOpen ? nil : 3)
                    .onTapGesture { withAnimation(.smooth) { greetingOpen.toggle() } }
                    .accessibilityHint(greetingOpen ? "Shows less" : "Shows the rest")
            }
        }
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
                    DeviceTile(device: device)
                }
            }
        }
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
        guard let temperature = weather.temperature else { return TodayWording.weatherWords(weather.condition) }
        return "\(TodayWording.weatherWords(weather.condition)), \(Int(temperature.rounded()))\(weather.unit)"
    }

    /// A glass card with a small header (symbol, title, optional note).
    // MARK: Diet

    /// Calories left and protein today; a tap opens the Diet screen.
    private func dietCard(_ food: Nutrition?) -> some View {
        Button {
            showingDiet = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "fork.knife")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.glacier)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Diet").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.frost)
                    if let food, food.isToday() {
                        Text(dietLine(food)).font(.caption).foregroundStyle(Theme.frostDim)
                    } else {
                        Text("What you've eaten today").font(.caption).foregroundStyle(Theme.frostDim)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.frostDim)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .glassPanel()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        #if DEBUG
        .onAppear { if ProcessInfo.processInfo.arguments.contains("-openDiet") { showingDiet = true } }
        #endif
    }

    /// "570 left · 59 / 140 g protein".
    private func dietLine(_ food: Nutrition) -> String {
        var line = food.leftWords
        if let protein = food.protein {
            line += " · \(Diet.whole(protein))"
            if let goal = food.proteinGoal { line += " / \(Diet.whole(goal))" }
            line += " g protein"
        }
        return line
    }

    // MARK: Reports

    /// Jarvis's reports: how long they're kept and the room they take, then
    /// one row each (newest first, five until "Show all"). A row opens the
    /// report in the app's reader; its "…" has Keep and Delete.
    private func reportsCard(_ shelf: ReportShelf) -> some View {
        card("Reports", icon: "doc.richtext", trailing: shelf.reports.isEmpty ? nil : "\(shelf.reports.count)") {
            Text(Reports.rulesText(shelf))
                .font(.caption)
                .foregroundStyle(Theme.frostDim)
            if shelf.reports.isEmpty {
                Text("None yet. Jarvis writes one when a long task ends.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.frostDim)
            }
            ForEach(allReports ? shelf.reports : Array(shelf.reports.prefix(5))) { report in
                reportRow(report, days: shelf.keepDays)
            }
            if shelf.reports.count > 5 {
                Button(allReports ? "Show fewer" : "Show all \(shelf.reports.count)") {
                    withAnimation(.smooth) { allReports.toggle() }
                }
                .font(.footnote.weight(.semibold))
                .frame(minHeight: 44)
            }
        }
    }

    /// One report: title, a line of summary, size and when it's deleted.
    private func reportRow(_ report: Report, days: Int) -> some View {
        HStack(spacing: 8) {
            Button {
                Task { await app.openReport(id: report.id, title: report.title) }
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(report.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.frost)
                        .lineLimit(2)
                    if !report.summary.isEmpty {
                        Text(report.summary)
                            .font(.caption)
                            .foregroundStyle(Theme.frostDim)
                            .lineLimit(2)
                    }
                    Text("\(Reports.sizeText(report.bytes)) · \(Reports.endText(report))")
                        .font(.caption2)
                        .foregroundStyle(report.kept ? Theme.glacier : Theme.frostDim)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .multilineTextAlignment(.leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Menu {
                Toggle("Keep", isOn: Binding(get: { report.kept }, set: { keep in Task { await app.keepReport(report.id, keep: keep) } }))
                Button("Delete…", role: .destructive) { deleting = report }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.frostDim)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Keep or delete \(report.title)")
        }
    }

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

/// One Home Assistant device as a small tile: its symbol, name and state,
/// glowing amber when it's on. Shared by Today and the kiosk.
struct DeviceTile: View {
    let device: Device
    /// Bigger type for the kiosk across the room.
    var large = false

    /// Symbol in a circle, then the name over the state.
    var body: some View {
        let on = device.isOn
        HStack(spacing: large ? 14 : 10) {
            Image(systemName: TodayWording.deviceSymbol(device))
                .font(.system(size: large ? 22 : 17, weight: .semibold))
                .foregroundStyle(on ? Theme.ember : Theme.frostFaint)
                .frame(width: large ? 40 : 30, height: large ? 40 : 30)
                .background(Circle().fill(on ? Theme.ember.opacity(0.18) : Color.white.opacity(0.06)))
            VStack(alignment: .leading, spacing: 1) {
                Text(device.name)
                    .font(large ? .body.weight(.semibold) : .footnote.weight(.semibold))
                    .lineLimit(1)
                Text(TodayWording.deviceState(device))
                    .font(large ? .subheadline : .caption)
                    .foregroundStyle(Theme.frostDim)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(large ? 14 : 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(on ? Theme.ember.opacity(0.08) : Color.white.opacity(0.04))
        )
        .accessibilityElement(children: .combine)
    }
}
