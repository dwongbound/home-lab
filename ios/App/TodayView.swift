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
    /// The first tries all missed with no snapshot yet: Home says it
    /// couldn't reach Jarvis (and keeps trying). Cleared by a snapshot.
    @Published private(set) var firstLoadFailed = false
    /// Tries in a row with no snapshot to show.
    private(set) var misses = 0
    /// When the first try started.
    private var firstTry: Date?
    @Published var problem: String?
    /// Offers hidden here, so they vanish before the next snapshot drops them.
    @Published private(set) var hidden: Set<String> = []
    /// Jarvis's suggestions start folded, like the home page's (OfferCards).
    @Published var offersOpen = false

    /// Fetches the snapshot; keeps the last one on screen if this fails.
    func load(app: AppModel) async {
        loading = true
        if firstTry == nil { firstTry = Date() }
        #if DEBUG
        // `-demoSnapshot` shows the sample data even when Jarvis answers.
        if let demo = DemoSnapshot.snapshot { snapshot = demo; WidgetShare.write(demo); loading = false; return }
        #endif
        do {
            snapshot = try await app.client.snapshot()
            misses = 0
            if firstLoadFailed { firstLoadFailed = false }
            // The Watch's board and complications follow every snapshot,
            // and so do the Home Screen widgets.
            WatchBridge.shared.push(snapshot)
            if let snapshot { WidgetShare.write(snapshot) }
            // A notice about a chat turn Chat doesn't have yet (a message
            // Jarvis sent unasked): lay it into Chat now, quietly, so it's
            // there before he swipes over or taps the notice.
            let chat = app.chat
            if chat.loaded, !chat.isSending, let newest = chat.items.compactMap(\.turnId).max(),
               (snapshot?.notices ?? []).contains(where: { ($0.turnId ?? 0) > newest }) {
                Task { await chat.load(app: app) }
            }
            problem = nil
            app.noteReach(nil)
        } catch {
            problem = ConnectionStatus.isJustNotAnswering(error) || (error as? JarvisError) == .unreachable ? nil : error.localizedDescription
            app.noteReach(error)
            if snapshot == nil {
                misses += 1
                let since = Date().timeIntervalSince(firstTry ?? Date())
                if HomeScreen.gaveUp(misses: misses, sinceFirstTry: since), !firstLoadFailed { firstLoadFailed = true }
            }
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
    /// The page has been laid out under the loader and handed over (one
    /// cross-fade, Dylan 2026-11-21: "should be smoother").
    @State private var pageShown = false
    /// When the loader first showed, so a fast answer still lets it be seen.
    @State private var loaderSince = Date()
    /// Which shortcut's screen is up (Reports, Diet or Playbooks).
    @State private var shortcut: Shortcut?
    /// The Home drawer: every device, full names.
    @State private var showDevices = false
    /// The Sleep screen.
    @State private var showSleep = false
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The one-time "send your sleep" card (App/SleepSync.swift).
    @ObservedObject private var sleepSync = SleepSync.shared
    /// The iPhone's Activity card reads from Health here (App/ActivitySync.swift).
    @ObservedObject private var activitySync = ActivitySync.shared

    /// Loader, couldn't-reach, or the page (JarvisKit HomeScreen).
    private var screen: HomeScreen {
        HomeScreen.state(hasSnapshot: today.snapshot != nil, firstLoadFailed: today.firstLoadFailed)
    }
    /// Home is off to the side (its spinners rest).
    @Environment(\.orbOffScreen) private var pageOffScreen
    /// The playbook ids, fetched lightly when Home shows (at most once a minute).
    @State private var playbookIds: [String]?
    @State private var playbooksFetched: Date?
    /// Bumped when something is marked seen, so the dots redraw.
    @State private var seenTick = 0
    /// The tile whose screen was opened last.
    @State private var lastOpened: Shortcut?

    /// The three screens the pinned row opens.
    enum Shortcut: String, Identifiable {
        case reports, diet, playbooks
        var id: String { rawValue }
    }

    /// Status line over a scrolling column of cards. Refreshes every 15 s
    /// while showing, like the page.
    var body: some View {
        #if DEBUG
        let _ = PerfCount.bump("home")
        #endif
        ZStack {
            Theme.sky.ignoresSafeArea()
            VStack(spacing: 0) {
                ScrollView {
                    GlassGroup {
                        VStack(alignment: .leading, spacing: 14) {
                            // Reports, Diet and Playbooks scroll with the page
                            // (Dylan, 2026-11-20: they were pinned).
                            shortcutRow
                            content
                        }
                    }
                    // The iPad's full width, with normal margins (no narrow
                    // centred column); the phone's column as before.
                    .padding(.horizontal, sizeClass == .regular ? 24 : 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: sizeClass == .regular ? .infinity : 720)
                    .frame(maxWidth: .infinity)
                }
                // Starts below the floating status; scrolls up under it.
                .contentMargins(.top, FloatingStatus.room, for: .scrollContent)
                .refreshable {
                    await today.load(app: app)
                    await loadPlaybooksLine()
                }
                .reportsScrollToTabBar()
            }
            // The whole page, tiles and status included, waits for the
            // first snapshot and then fades in at once (Dylan, 2026-11-20:
            // "including the top 3 panels? right now it just flashes in").
            // Built as soon as the snapshot is here, but shown only once
            // it's laid out (pageShown), so the fade never carries layout.
            .opacity(pageShown ? 1 : 0)
            // Settles up into place as it fades in (Dylan, 2026-11-21:
            // "should be smoother"), instead of only appearing.
            .scaleEffect(pageShown || reduceMotion ? 1 : 0.985, anchor: .top)
            VStack { TopFade(); Spacer() }
            if !pageShown {
                HomeLoader(failed: screen == .failed) {
                    Task { await today.load(app: app) }
                }
                // The orb settles back a touch as it fades; the page fades in
                // over the same third of a second (one cross-fade).
                .transition(.opacity.combined(with: .scale(scale: reduceMotion ? 1 : 0.94)))
            }
        }
        .floatingStatus(showsStatus: true, visible: pageShown)
        .onAppear { if screen == .ready { pageShown = true } }
        .task(id: screen == .ready) {
            guard screen == .ready, !pageShown else { return }
            // Let the page lay out under the loader first (a couple of
            // frames), and keep a fast answer from flashing the loader.
            let seen = Date().timeIntervalSince(loaderSince)
            try? await Task.sleep(for: .milliseconds(Int(max(80, (0.45 - seen) * 1000))))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? .linear(duration: 0.15) : .smooth(duration: 0.55)) { pageShown = true }
        }
        .sheet(isPresented: $showSleep) {
            SleepDetailView().environmentObject(app)
        }
        .sheet(isPresented: $showDevices) {
            if let home = today.snapshot?.home { DevicesSheet(home: home) }
        }
        .sheet(item: $shortcut, onDismiss: { if let which = lastOpened { markSeen(which, refetch: true) } }) { which in
            switch which {
            case .reports: ReportsListView().environmentObject(app)
            case .diet: DietView().environmentObject(app)
            case .playbooks: PlaybooksView().environmentObject(app)
            }
        }
        .task {
            await loadPlaybooksLine()
            #if DEBUG
            // `-pretendNew` makes every tile look new (simulator checks).
            if ProcessInfo.processInfo.arguments.contains("-pretendNew") {
                SeenStore.seeReports(["x"]); SeenStore.seePlaybooks(["x"]); SeenStore.seeDiet(nil)
            }
            #endif
            SeenStore.baseline(reports: reportIds, diet: .some(SeenTracker.dietMark(today.snapshot?.nutrition)), playbooks: playbookIds)
            seenTick += 1
        }
        .onChange(of: shortcut) { _, opened in
            if let opened {
                lastOpened = opened
                markSeen(opened, refetch: false)
            }
        }
        #if DEBUG
        .onAppear {
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-openDiet") { shortcut = .diet }
            if args.contains("-openSleep") { showSleep = true }
            if args.contains("-openDevices") { showDevices = true }
            if args.contains("-openReports") { shortcut = .reports }
            if args.contains("-openPlaybooks") { shortcut = .playbooks }
        }
        #endif
        .fontDesign(.rounded)
        #if DEBUG
        .onAppear { if ProcessInfo.processInfo.arguments.contains("-openKiosk") { app.padKiosk = true } }
        #endif

    }

    /// The cards, or a labelled spinner on the very first load.
    @ViewBuilder
    private var content: some View {
        // "Jarvis isn't answering" is said in the top line now; only other
        // problems show here.
        if let problem = today.problem {
            Text(problem).font(.footnote).foregroundStyle(Theme.rose)
        }
        if let snapshot = today.snapshot {
            #if DEBUG
            // `-gpuFirst` puts the GPU card at the top (simulator screenshots).
            if ProcessInfo.processInfo.arguments.contains("-gpuFirst"), !snapshot.systemGauges.isEmpty { SystemPanel(snapshot: snapshot) }
            // `-sleepFirst`: the Sleep card at the top (simulator screenshots).
            if ProcessInfo.processInfo.arguments.contains("-sleepFirst"), SleepSlide.shows(snapshot) { sleepCard(SleepSlide.card(snapshot)) }
            #endif
            hero(snapshot)
            if sleepSync.showsCard { sleepAllowCard }
            // On an iPad's full width the cards sit side by side, each in
            // the shortest column (Dylan, 2026-11-20: more on screen, no
            // empty side margins); otherwise one column, as on the iPhone.
            if sizeClass == .regular {
                Masonry(minColumnWidth: 340, spacing: 14) { cards(snapshot) }
            } else {
                cards(snapshot)
            }
        }
    }

    /// Home's cards, in order: alerts, suggestions, devices, money, you,
    /// the graphics card and what Jarvis is working on.
    @ViewBuilder
    private func cards(_ snapshot: Snapshot) -> some View {
        Group {
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
            // Sleep has its own card when Jarvis sends the sleep slice; the
            // "You" card keeps steps (and minutes asleep from an older Jarvis).
            if SleepSlide.shows(snapshot) {
                sleepCard(SleepSlide.card(snapshot))
            }
            // On the iPhone: rings, a week of steps, heart and weight read
            // from Health on the phone (ActivityCard). Elsewhere, Jarvis's steps.
            if ActivitySync.available {
                ActivityCard(sync: activitySync, fallbackSteps: snapshot.health?.yesterday?.steps)
            } else if SleepSlide.showsYou(snapshot), let health = snapshot.health {
                healthCard(health, withSleep: !SleepSlide.shows(snapshot))
            }
            // The PC: GPU, memory, disk and processor (Dylan, 2026-11-21).
            if !snapshot.systemGauges.isEmpty {
                SystemPanel(snapshot: snapshot)
            }
            if let running = snapshot.jobs?.running, !running.isEmpty {
                card("Jarvis is working on", icon: "sparkles") {
                    ForEach(running) { task in
                        HStack(spacing: 10) {
                            // Spins only while Home is on screen.
                            if pageOffScreen {
                                Image(systemName: "circle.dotted").font(.footnote).foregroundStyle(Theme.ember)
                            } else {
                                ProgressView().controlSize(.small).tint(Theme.ember)
                            }
                            Text(task.label).font(.subheadline)
                        }
                    }
                }
            }
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
                    // Edge to edge across the card, past its padding (Apple's style).
                    if offer.id != today.offers.last?.id { Divider().overlay(Theme.glassEdge).padding(.horizontal, -16) }
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
        return card("Home", icon: "house.fill", trailing: (lights.isEmpty ? "All devices" : "\(lit) of \(lights.count) lights on") + "  ›") {
            // Two to a row on every iPhone (Dylan, 2026-11-20), more on iPad.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 10)], spacing: 10) {
                ForEach(devices) { device in
                    DeviceTile(device: device)
                }
            }
        }
        // Tapping the card opens every device in a drawer.
        .contentShape(Rectangle())
        .onTapGesture { showDevices = true }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Shows every device")
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

    /// Last night's sleep: the score ring, time asleep, bed and wake, the
    /// stage bar and the score's parts, then vitals and the week on the
    /// iPad's wider column. The whole card opens the Sleep screen.
    private func sleepCard(_ sleep: SleepCard) -> some View {
        Button { showSleep = true } label: {
            card("Sleep", icon: "bed.double.fill", trailing: "Details  ›") {
                VStack(alignment: .leading, spacing: 14) {
                    switch sleep.kind {
                    case .night, .minutesOnly:
                        SleepHeadline(card: sleep)
                        if !sleep.stages.isEmpty { SleepStageBar(shares: sleep.stages) }
                        if !sleep.parts.isEmpty { SleepPartBars(parts: sleep.parts) }
                        if !sleep.vitals.isEmpty { SleepVitalTiles(vitals: sleep.vitals, columns: sizeClass == .regular ? 3 : 2) }
                    case .noNight:
                        Text(sleep.emptyWords ?? "").font(.subheadline).foregroundStyle(Theme.frostDim)
                    }
                    if !sleep.trend.isEmpty {
                        HStack(alignment: .bottom) {
                            SleepTrendBars(trend: sleep.trend)
                            Spacer()
                            if let average = sleep.trendAverage {
                                Text(average).font(.caption).foregroundStyle(Theme.frostDim)
                            }
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens your sleep")
    }

    /// Asked once, here, never at launch: Apple Health's own sheet follows Allow.
    private var sleepAllowCard: some View {
        card("Apple Health", icon: "heart.text.square.fill") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Send your Apple Watch sleep to Jarvis each morning: stages, heart rate, breathing and more.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.frost)
                    .fixedSize(horizontal: false, vertical: true)
                if let problem = sleepSync.askProblem {
                    Text(problem).font(.footnote).foregroundStyle(Theme.rose)
                }
                HStack(spacing: 10) {
                    Button("Allow") { Task { await sleepSync.allow() } }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.glacier)
                        .foregroundStyle(Theme.basalt)
                        .frame(minHeight: 44)
                    Button("Not now") { sleepSync.dismissCard() }
                        .buttonStyle(.bordered)
                        .tint(Theme.frostDim)
                        .frame(minHeight: 44)
                }
            }
        }
    }

    /// Last night's sleep and yesterday's steps, side by side.
    private func healthCard(_ health: Health, withSleep: Bool) -> some View {
        card("You", icon: "heart.fill") {
            HStack(spacing: 10) {
                if withSleep, let asleep = health.sleep?.asleepMin {
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
    // MARK: Shortcuts

    /// Three large tiles, each with its icon, name and one live line.
    private var shortcutRow: some View {
        HStack(spacing: 10) {
            let _ = seenTick
            tile(.reports, "Reports", "doc.richtext", isNew: reportIds.map { SeenTracker.hasNew(current: $0, seen: SeenStore.reports) } ?? false)
            tile(.diet, "Diet", "fork.knife", isNew: SeenTracker.dietHasNew(current: SeenTracker.dietMark(today.snapshot?.nutrition), seen: SeenStore.diet))
            tile(.playbooks, "Playbooks", "list.bullet.rectangle", isNew: playbookIds.map { SeenTracker.hasNew(current: $0, seen: SeenStore.playbooks) } ?? false)
        }
    }

    /// One tile: its icon and name, and an orange dot when there's
    /// something new in it (no other words: Dylan, 2026-11-19). A tap opens
    /// its screen.
    private func tile(_ which: Shortcut, _ name: String, _ icon: String, isNew: Bool) -> some View {
        Button {
            shortcut = which
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                // A fixed box for the icon, so the three names share one line
                // however tall each symbol draws.
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.glacier)
                    .frame(width: 26, height: 26, alignment: .leading)
                HStack(spacing: 6) {
                    Text(name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.frost)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    // Always laid out, only shown when new, so nothing shifts.
                    Circle()
                        .fill(OrbView.noticeOrange(onLight: false))
                        .frame(width: 7, height: 7)
                        .opacity(isNew ? 1 : 0)
                        .accessibilityHidden(!isNew)
                        .accessibilityLabel("New")
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .glassPanel()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens \(name)")
    }

    /// The report ids Home knows about.
    private var reportIds: [String]? {
        app.reportShelf.map { $0.reports.map(\.id) }
    }

    /// Marks a tile seen as it stands, when its screen opens and again
    /// when it closes (so a playbook he just made doesn't light the dot).
    private func markSeen(_ which: Shortcut, refetch: Bool) {
        switch which {
        case .reports: if let ids = reportIds { SeenStore.seeReports(ids) }
        case .diet: SeenStore.seeDiet(SeenTracker.dietMark(today.snapshot?.nutrition))
        case .playbooks:
            if let ids = playbookIds { SeenStore.seePlaybooks(ids) }
            if refetch {
                Task {
                    playbooksFetched = nil
                    await loadPlaybooksLine()
                    if let ids = playbookIds { SeenStore.seePlaybooks(ids) }
                    seenTick += 1
                }
            }
        }
        seenTick += 1
    }

    /// Fetches the playbook ids, lightly: at most once a minute, quietly.
    private func loadPlaybooksLine() async {
        if let last = playbooksFetched, Date().timeIntervalSince(last) < 60 { return }
        playbooksFetched = Date()
        if let list = try? await app.client.playbooks() { playbookIds = list.map(\.id) }
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
    /// The devices drawer: every word of the name and state, wrapping as
    /// far as it needs, never cut.
    var full = false

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
                // Two lines before any "…", a touch smaller if need be
                // (Dylan, 2026-11-19: "i cant see the full name").
                Text(device.name)
                    .font(large || full ? .body.weight(.semibold) : .footnote.weight(.semibold))
                    .lineLimit(full ? nil : 2)
                    .minimumScaleFactor(full ? 1 : 0.85)
                    .fixedSize(horizontal: false, vertical: true)
                Text(device.isAvailable ? TodayWording.deviceState(device) : "Not responding")
                    .font(large || full ? .subheadline : .caption)
                    .foregroundStyle(device.isOn ? Theme.ember : Theme.frostDim)
                    .lineLimit(full ? nil : 1)
                    .fixedSize(horizontal: false, vertical: full)
            }
            Spacer(minLength: 0)
        }
        .padding(large ? 14 : 10)
        // Equal heights whether a name takes one line or two.
        .frame(maxHeight: .infinity)
        .frame(minHeight: large ? 76 : 62)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(on ? Theme.ember.opacity(0.08) : Color.white.opacity(0.04))
        )
        .accessibilityElement(children: .combine)
    }
}

/// Cards side by side in columns, each placed in the column that's
/// shortest so far, so cards of different heights pack without gaps. As
/// many columns of at least `minColumnWidth` as fit.
struct Masonry: Layout {
    var minColumnWidth: CGFloat
    var spacing: CGFloat

    private func columns(for width: CGFloat) -> Int {
        max(1, Int((width + spacing) / (minColumnWidth + spacing)))
    }

    /// Each subview's column and top edge, and the total height.
    private func arrange(_ subviews: Subviews, width: CGFloat) -> (spots: [(column: Int, y: CGFloat)], columnWidth: CGFloat, height: CGFloat) {
        let count = columns(for: width)
        let columnWidth = (width - spacing * CGFloat(count - 1)) / CGFloat(count)
        var heights = Array(repeating: CGFloat(0), count: count)
        var spots: [(Int, CGFloat)] = []
        for view in subviews {
            let height = view.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height
            guard height > 0 else { spots.append((0, 0)); continue }
            let column = heights.indices.min { heights[$0] < heights[$1] } ?? 0
            let y = heights[column] == 0 ? 0 : heights[column] + spacing
            spots.append((column, y))
            heights[column] = y + height
        }
        return (spots, columnWidth, heights.max() ?? 0)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? minColumnWidth
        return CGSize(width: width, height: arrange(subviews, width: width).height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let laid = arrange(subviews, width: bounds.width)
        for (view, spot) in zip(subviews, laid.spots) {
            view.place(at: CGPoint(x: bounds.minX + CGFloat(spot.column) * (laid.columnWidth + spacing), y: bounds.minY + spot.y),
                       proposal: ProposedViewSize(width: laid.columnWidth, height: nil))
        }
    }
}

/// Home before its first snapshot: the orb, thinking, with "Loading" under
/// it; or, when the first tries all missed, "Couldn't reach Jarvis" with
/// Retry. The orb rests while Home is off to the side (orbOffScreen).
private struct HomeLoader: View {
    let failed: Bool
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            OrbView(state: failed ? .listening : .thinking, size: 140, tappable: false, dim: failed ? 0.55 : 1)
            if failed {
                Text("Couldn't reach Jarvis.")
                    .foregroundStyle(Theme.frostDim)
                Button("Retry", action: retry)
                    .buttonStyle(.bordered)
                    .tint(Theme.glacier)
                    .frame(minHeight: 44)
            } else {
                Text("Loading")
                    .font(.subheadline)
                    .foregroundStyle(Theme.frostDim)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(failed ? "Couldn't reach Jarvis" : "Loading")
    }
}
