// The Diet screen (Dylan, 2026-11-18/19): the week strip with two rings
// per day (calories outside, protein inside, full when the goal is met),
// the totals for the day in view, and one endless timeline below: newest at
// the top, scrolling back into the past, every logged item its own entry on
// a rail at its exact time. As he scrolls, the title, the highlighted ring
// and the totals follow the day at the top. Read-only. The grouping, rings
// and paging rules are JarvisKit's Diet and DietTimeline.
import SwiftUI
import JarvisKit

/// The timeline's data: days newest first, loaded 14 at a time.
@MainActor
final class DietModel: ObservableObject {
    enum State: Equatable { case loading, ready, unreachable, failed(String) }

    @Published private(set) var state: State = .loading
    /// Days loaded so far, newest first.
    @Published private(set) var days: [NutritionDay] = []
    /// The first meal ever logged, when Jarvis says.
    @Published private(set) var earliest: String?
    /// True while an older page is on its way.
    @Published private(set) var loadingOlder = false
    /// True once there's nothing older to load.
    @Published private(set) var reachedEnd = false
    /// Weeks loaded for the rings, by their Monday.
    @Published private(set) var weeks: [String: NutritionWeek] = [:]
    /// The day at the top of the timeline.
    @Published var dayInView: String = Diet.dayString(Date())
    /// Fresh numbers on their way, with the last ones still showing.
    @Published private(set) var refreshing = false
    /// A refresh that didn't come through, in plain words.
    @Published private(set) var note: String?

    /// One model for the app's life, so opening Diet again shows the last
    /// numbers at once while it fetches new ones.
    static let shared = DietModel()

    /// The timeline's blocks (days, empty days, runs of empty days).
    var blocks: [DietTimeline.Block] { DietTimeline.blocks(days) }

    /// A loaded day.
    func day(_ date: String) -> NutritionDay? { days.first { $0.date == date } }

    /// The first page, ending today.
    func loadFirst(client: JarvisClient) async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-demoDiet") {
            let today = Diet.dayString(Date())
            days = (0..<14).map { i in
                let date = Diet.shift(today, by: -i) ?? today
                return i % 4 == 3 ? NutritionDay(date: date, goals: Macros(calories: 1750, protein: 140), totals: Macros(), items: []) : DemoDiet.day(date)
            }
            state = .ready
            reachedEnd = true
            await loadWeek(for: today, client: client)
            return
        }
        #endif
        // What's already here stays on screen while the fresh numbers come
        // (a small "Updating" in the header); only a first-ever open waits.
        if days.isEmpty { state = .loading } else { refreshing = true }
        defer { refreshing = false }
        guard let page = await fetchPage(end: Diet.dayString(Date()), client: client) else {
            if !days.isEmpty { note = "Couldn’t refresh just now. These are the last numbers." }
            return
        }
        note = nil
        days = page.days
        earliest = page.earliest
        reachedEnd = !DietTimeline.shouldLoadOlder(loaded: days, earliest: earliest)
        state = .ready
        #if DEBUG
        // `-dietYesterday` shows yesterday's totals (simulator check of an over day).
        if ProcessInfo.processInfo.arguments.contains("-dietYesterday") { dayInView = Diet.shift(Diet.dayString(Date()), by: -1) ?? dayInView }
        #endif
        await loadWeek(for: dayInView, client: client)
    }

    /// The next 14 older days, when there are any.
    func loadOlder(client: JarvisClient) async {
        guard state == .ready, !loadingOlder, !reachedEnd, let end = DietTimeline.nextEnd(after: days) else { return }
        loadingOlder = true
        defer { loadingOlder = false }
        guard let page = await fetchPage(end: end, client: client) else { return }
        // Skip any day already held, so nothing shows twice.
        let held = Set(days.map(\.date))
        days.append(contentsOf: page.days.filter { !held.contains($0.date) })
        if let first = page.earliest { earliest = first }
        reachedEnd = page.days.isEmpty || !DietTimeline.shouldLoadOlder(loaded: days, earliest: earliest)
    }

    /// Loads pages until `date` is held (a tapped ring, a swiped week).
    func ensureLoaded(through date: String, client: JarvisClient) async {
        var guardrail = 0
        while let oldest = days.last?.date, oldest > date, !reachedEnd, guardrail < 12 {
            await loadOlder(client: client)
            guardrail += 1
        }
    }

    /// The week holding `date`, for the rings (cached).
    func loadWeek(for date: String, client: JarvisClient) async {
        guard let start = Diet.weekStart(of: date), weeks[start] == nil else { return }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-demoDiet") { weeks[start] = DemoDiet.week(start); return }
        #endif
        if let week = try? await client.nutritionWeek(start: start) { weeks[start] = week }
    }

    /// One page: the days call, or one day at a time from an older server.
    private func fetchPage(end: String, client: JarvisClient) async -> NutritionDays? {
        do {
            if let page = try await client.nutritionDays(end: end, count: 14) { return page }
            // Older server: seven single days.
            var days: [NutritionDay] = []
            for i in 0..<7 {
                guard let date = Diet.shift(end, by: -i) else { break }
                guard let day = try await client.nutritionDay(date: date) else {
                    if self.days.isEmpty { state = .unreachable }
                    return days.isEmpty ? nil : NutritionDays(days: days, earliest: nil)
                }
                days.append(day)
            }
            return NutritionDays(days: days, earliest: nil)
        } catch {
            if self.days.isEmpty { state = .failed(error.localizedDescription) }
            return nil
        }
    }
}

struct DietView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var model = DietModel.shared
    @Environment(\.scenePhase) private var scenePhase
    /// The block at the top of the timeline.
    @State private var topBlock: String?
    /// The entry whose full photo is open.
    @State private var photo: FoodItem?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.sky.ignoresSafeArea()
                VStack(spacing: 10) {
                    if let note = model.note {
                        Text(note).font(.footnote).foregroundStyle(Theme.frostDim).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    weekStrip
                    totals
                    timeline
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle(Diet.title(model.dayInView))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if model.refreshing {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Updating").font(.footnote).foregroundStyle(Theme.frostDim)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .toolbar {
                SheetClose { dismiss() }
            }
        }
        .preferredColorScheme(.dark)
        .fontDesign(.rounded)
        .fullScreenCover(item: $photo) { item in
            MealPhotoViewer(item: item).environmentObject(app)
        }
        .task { await model.loadFirst(client: app.client) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.loadFirst(client: app.client) } }
        }
        .onChange(of: model.dayInView) { _, date in
            Task { await model.loadWeek(for: date, client: app.client) }
        }
    }

    // MARK: Week strip

    /// The week of the day in view: two rings a day; tap one to go there,
    /// swipe sideways for the week before or after.
    private var weekStrip: some View {
        let start = Diet.weekStart(of: model.dayInView) ?? model.dayInView
        let week = model.weeks[start]?.days ?? (0..<7).map { WeekDay(date: Diet.shift(start, by: $0) ?? start, calories: nil, goal: nil) }
        return HStack(spacing: 4) {
            ForEach(week) { raw in
                let day = raw.withProtein(from: model.day(raw.date))
                Button {
                    go(to: day.date)
                } label: {
                    VStack(spacing: 6) {
                        Text(Diet.weekdayInitials(day.date))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(day.date == model.dayInView ? Theme.frost : Theme.frostDim)
                        rings(day)
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(day.date == model.dayInView ? Color.white.opacity(0.10) : .clear))
                    }
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(day.date > Diet.dayString(Date()))
                .accessibilityLabel(DietTimeline.ringLabel(day))
                .accessibilityAddTraits(day.date == model.dayInView ? .isSelected : [])
            }
        }
        .padding(.vertical, 8)
        .glassPanel()
        .gesture(DragGesture(minimumDistance: 30).onEnded { drag in
            guard abs(drag.translation.width) > abs(drag.translation.height) else { return }
            let step = drag.translation.width < 0 ? 7 : -7
            guard let target = Diet.shift(start, by: step).flatMap({ Diet.shift($0, by: 6) }) else { return }
            go(to: min(target, Diet.dayString(Date())))
        })
    }

    /// Calories outside (amber when over), protein inside (blue), the date
    /// number in the middle; empty tracks with no data or no goal.
    private func rings(_ day: WeekDay) -> some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.10), lineWidth: 2.5)
            if let ring = day.ring {
                Circle().trim(from: 0, to: ring)
                    .stroke(Diet.isOver(day.calories, goal: day.goal) ? Theme.ember : Theme.moss, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            Circle().stroke(Color.white.opacity(0.08), lineWidth: 2.5).padding(5)
            if let protein = day.proteinRing {
                Circle().trim(from: 0, to: protein)
                    .stroke(Theme.glacier, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(5)
            }
            Text(Diet.dayNumber(day.date))
                .font(.caption.weight(day.date == Diet.dayString(Date()) ? .bold : .medium))
                .foregroundStyle(day.date == Diet.dayString(Date()) ? Theme.glacier : Theme.frost)
        }
    }

    /// Scrolls the timeline to a day, loading older pages first if needed.
    private func go(to date: String) {
        Task {
            await model.ensureLoaded(through: date, client: app.client)
            if let block = DietTimeline.block(holding: date, in: model.blocks) {
                withAnimation(.smooth) { topBlock = block.id }
                model.dayInView = date
            }
        }
    }

    // MARK: Totals

    /// The day in view against its goals: one strict grid of four equal
    /// columns, every column the same four rows (label, number, caption,
    /// bar) so labels, numbers and bars share their lines (Dylan,
    /// 2026-11-19). Over a limit turns that column's number and bar orange.
    private var totals: some View {
        let day = model.day(model.dayInView)
        // Fat and carbs are limits on a cut: Jarvis's goals, else 55 g and 175 g.
        let goals = DietGoals.effective(day?.goals ?? Macros())
        let sums = day?.totals ?? Macros()
        let columns: [TotalColumn] = [
            TotalColumn(name: "Calories", value: sums.calories, goal: goals.calories, unit: "", tint: Theme.moss, limit: true),
            TotalColumn(name: "Protein", value: sums.protein, goal: goals.protein, unit: "g", tint: Theme.glacier, limit: false),
            TotalColumn(name: "Fat", value: sums.fat, goal: goals.fat, unit: "g", tint: Theme.glacier.opacity(0.7), limit: true),
            TotalColumn(name: "Carbs", value: sums.carbs, goal: goals.carbs, unit: "g", tint: Theme.moss.opacity(0.8), limit: true),
        ]
        return Grid(horizontalSpacing: 12, verticalSpacing: 4) {
            GridRow {
                ForEach(columns) { c in
                    Text(c.name).font(.caption2.weight(.semibold)).foregroundStyle(Theme.frostDim)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            GridRow {
                ForEach(columns) { c in
                    Text(Diet.whole(c.value ?? 0) + c.unit)
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(c.caption.over ? Theme.ember : Theme.frost)
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            GridRow {
                ForEach(columns) { c in
                    Text(c.caption.words)
                        .font(.caption2.weight(c.caption.over ? .semibold : .regular).monospacedDigit())
                        .foregroundStyle(c.caption.over ? Theme.ember : Theme.frostDim)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            GridRow {
                ForEach(columns) { c in
                    // Every column keeps its bar track, so all four sit on one line.
                    GeometryReader { area in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.10))
                            Capsule().fill(c.caption.over ? Theme.ember : c.tint)
                                .frame(width: area.size.width * (Diet.fraction(c.value ?? 0, of: c.goal) ?? 0))
                        }
                    }
                    .frame(height: 4)
                    .padding(.top, 2)
                    .accessibilityHidden(true)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glassPanel()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(columns.map { "\($0.name) \(Diet.whole($0.value ?? 0))\($0.unit), \($0.caption.words)" }.joined(separator: "; "))
    }

    /// One column of the totals grid.
    private struct TotalColumn: Identifiable {
        let name: String
        let value: Double?
        let goal: Double?
        let unit: String
        let tint: Color
        let limit: Bool
        var id: String { name }
        var caption: (words: String, over: Bool) { DietGoals.caption(eaten: value, goal: goal, unit: unit, limit: limit) }
    }

    // MARK: Timeline

    /// Every day, newest first, each entry on the rail at its own time.
    @ViewBuilder
    private var timeline: some View {
        switch model.state {
        case .loading:
            waiting("Loading what you ate…")
            Spacer()
        case .unreachable:
            note("Jarvis can’t be reached, so the food log can’t be shown right now.")
            Spacer()
        case .failed(let words):
            note(words)
            Spacer()
        case .ready:
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(model.blocks) { block in
                        blockView(block).id(block.id)
                    }
                    if model.loadingOlder {
                        waiting("Loading earlier days…").padding(.vertical, 16)
                    } else if model.reachedEnd {
                        Text(model.days.isEmpty ? "Nothing logged yet." : "That's everything logged. To fix an entry, tell Jarvis in Chat.")
                            .font(.caption)
                            .foregroundStyle(Theme.frostDim)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                    } else {
                        // Reaching the bottom fetches the next 14 days.
                        Color.clear.frame(height: 1)
                            .onAppear { Task { await model.loadOlder(client: app.client) } }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollPosition(id: $topBlock, anchor: .top)
            .onChange(of: topBlock) { _, id in
                if let id { model.dayInView = id }
            }
            // A sideways swipe on the page moves a day (Dylan, 2026-11-21:
            // "swiping the page in the drawer should also change the
            // dates"); the week row follows. Decided per touch: a mostly
            // vertical drag is the list's scroll.
            .simultaneousGesture(DragGesture(minimumDistance: 24).onEnded { drag in
                guard let step = DaySwipe.step(width: drag.translation.width, height: drag.translation.height),
                      let target = Diet.shift(model.dayInView, by: step), target <= Diet.dayString(Date()) else { return }
                Haptics.play(.tab)
                go(to: target)
            })
            // No pull to refresh (Dylan, 2026-11-20): it loads each time Diet
            // opens and when the app comes back to it.
        }
    }

    /// One block: a day with its header and entries, or an empty row.
    @ViewBuilder
    private func blockView(_ block: DietTimeline.Block) -> some View {
        switch block {
        case .day(let day):
            VStack(alignment: .leading, spacing: 0) {
                dayHeader(day)
                ForEach(Array(day.items.enumerated()), id: \.offset) { index, item in
                    entry(item, last: index == day.items.count - 1)
                }
            }
            .padding(.bottom, 8)
        case .empty(let date):
            slim("\(Diet.title(date)) · Nothing logged")
        case .emptyRun(let from, let to, _):
            slim(DietTimeline.runLabel(from: from, to: to))
        }
    }

    /// The day's name and its totals, once.
    private func dayHeader(_ day: NutritionDay) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(Diet.title(day.date)).font(.headline).foregroundStyle(Theme.frost)
            Spacer()
            Text("\(Diet.whole(day.totals.calories)) kcal  \(Diet.macroLine(day.totals))")
                .font(.caption)
                .foregroundStyle(Theme.frostDim)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
    }

    /// One entry: its time on the left, a node on the rail, then the food
    /// with its portion, calories and macros (once).
    private func entry(_ item: FoodItem, last: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(DietTimeline.timeLabel(item))
                .font(.caption.monospacedDigit())
                // One line at any text size: shrinks rather than splitting "PM" off.
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(Theme.frostDim)
                .frame(width: 64, alignment: .trailing)
                .padding(.top, 2)
            VStack(spacing: 0) {
                Circle().fill(Theme.glacier).frame(width: 9, height: 9).padding(.top, 5)
                Rectangle().fill(Color.white.opacity(last ? 0 : 0.15)).frame(width: 1.5)
            }
            .frame(width: 12)
            HStack(alignment: .top, spacing: 10) {
                // The meal's photo, when it was logged from one.
                if MealPhotos.shouldFetch(item) {
                    MealThumbnail(item: item) { photo = item }
                }
                // The title gets the width: calories top right, the macros
                // under the title (Dylan, 2026-11-19: titles wrapped to six lines).
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(item.name).font(.subheadline).foregroundStyle(Theme.frost)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(Diet.whole(item.macros.calories)).font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(Theme.frost)
                            .layoutPriority(1)
                    }
                    Text([item.portion, Diet.macroLine(item.macros)].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption.monospacedDigit()).foregroundStyle(Theme.frostDim)
                        .lineLimit(2)
                }
            }
            .padding(10)
            .glassPanel()
            .padding(.bottom, 8)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }

    /// A slim "Nothing logged" row.
    private func slim(_ words: String) -> some View {
        Text(words)
            .font(.caption)
            .foregroundStyle(Theme.frostDim)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            .padding(.horizontal, 4)
    }

    /// A spinner with words.
    private func waiting(_ words: String) -> some View {
        HStack(spacing: 10) {
            ProgressView().tint(Theme.frost)
            Text(words).foregroundStyle(Theme.frostDim)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
    }

    /// A plain message.
    private func note(_ words: String) -> some View {
        Text(words)
            .multilineTextAlignment(.center)
            .foregroundStyle(Theme.frost)
            .frame(maxWidth: .infinity)
            .padding(24)
            .glassPanel()
    }
}
