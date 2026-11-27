// Claude (Dylan 2026-11-26, mockup approved): Jarvis's plan usage as two
// rings with reset times, tokens this week as bars and by kind of work;
// what's running and today's jobs; the Claude project threads. All read
// from the snapshot the app already loads, so it adds no requests.
// Dylan 2026-11-26 5:27 PM: "show more information… like total cost" and
// "make the plots and graphs more interactive": cost tiles, a bar chart you
// tap or scrub for each day's numbers, tappable rings and kind rows.
import SwiftUI
import JarvisKit

struct ClaudeView: View {
    @ObservedObject var today: TodayModel
    @State private var tab = 0
    /// The bars show dollars instead of tokens.
    @State private var showCost = false
    /// Kinds opened to show their calls, tokens and dollars.
    @State private var opened: Set<String> = []

    /// Claude's orange, as on the chat chip.
    static let claude = Color(red: 0xe8 / 255, green: 0x94 / 255, blue: 0x6a / 255)

    var body: some View {
        List {
            Picker("Show", selection: $tab) {
                Text("Usage").tag(0)
                Text("Schedule").tag(1)
                Text("Threads").tag(2)
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
            .onChange(of: tab) { _, _ in Haptics.play(.tab) }

            switch tab {
            case 0: usage
            case 1: schedule
            default: threads
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.sky.ignoresSafeArea())
        .navigationTitle("Claude")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var snapshot: Snapshot? { today.snapshot }

    // MARK: Usage

    /// Rings (when Jarvis knows his limits), then tokens by day and by kind.
    @ViewBuilder private var usage: some View {
        if let use = snapshot?.claudeUsage {
            if !use.rings.isEmpty {
                Section("Plan usage") {
                    HStack {
                        ForEach(use.rings) { limit in
                            LimitRing(limit: limit, tint: limit.name == "session" ? Self.claude : Theme.glacier)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            Section("Cost") {
                CostTiles(use: use)
                    .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
            }
            let tokens = use.hasTokens && !showCost
            Section {
                if use.hasTokens {
                    Picker("Bars show", selection: $showCost) {
                        Text("Tokens").tag(false)
                        Text("Cost").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: showCost) { _, _ in Haptics.play(.tab) }
                }
                WeekBars(days: use.days, tokens: tokens)
                    .padding(.vertical, 6)
                ForEach(use.kindsByUse) { kind in
                    KindRow(kind: kind, top: use.kindsByUse.first, tokens: tokens, open: opened.contains(kind.kind))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            Haptics.play(.tab)
                            withAnimation(.snappy) {
                                if opened.contains(kind.kind) { opened.remove(kind.kind) } else { opened.insert(kind.kind) }
                            }
                        }
                }
                .fullWidthSeparators()
            } header: {
                Text(tokens ? "Tokens this week" : "Spend this week")
            } footer: {
                Text(use.rings.isEmpty
                     ? "Plan usage shows once Jarvis has made a Claude call since his last restart. Dollars are background jobs only, at API prices."
                     : "Dollars are background jobs only, at API prices.")
            }
        } else {
            empty("Jarvis isn't sharing his Claude use yet.")
        }
    }

    // MARK: Schedule

    /// Running now, then today's jobs by time with how each went.
    @ViewBuilder private var schedule: some View {
        let running = snapshot?.jobs?.running ?? []
        if !running.isEmpty {
            Section("Running now") {
                ForEach(running) { task in
                    HStack(spacing: 10) {
                        Circle().fill(Theme.glacier).frame(width: 9, height: 9)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.label).lineLimit(1)
                            Text(task.stepLine()).font(.caption).foregroundStyle(Theme.frostDim).lineLimit(1)
                        }
                        Spacer()
                        if let chip = ModelWording.jobChip(task.model) {
                            Text(chip.label).font(.caption).foregroundStyle(chip.tone == .claude ? Self.claude : Theme.glacier)
                        }
                    }
                    .frame(minHeight: 44)
                }
                .fullWidthSeparators()
            }
        }
        let rows = ScheduleRow.rows(snapshot?.jobs?.jobs ?? [])
        if rows.isEmpty && running.isEmpty {
            empty("No jobs from Jarvis yet.")
        } else if !rows.isEmpty {
            Section("Today") {
                ForEach(rows) { row in
                    HStack(spacing: 10) {
                        Circle().fill(row.tint).frame(width: 9, height: 9)
                        Text(row.name).lineLimit(1)
                        Spacer()
                        Text(row.when).font(.subheadline).foregroundStyle(row.isNext ? Theme.glacier : Theme.frostDim).monospacedDigit()
                    }
                    .frame(minHeight: 44)
                }
                .fullWidthSeparators()
            }
        }
    }

    // MARK: Threads

    /// A bar of thread states, then the threads, newest first.
    @ViewBuilder private var threads: some View {
        let list = (snapshot?.threads ?? []).sorted { ($0.lastActivityAt ?? "") > ($1.lastActivityAt ?? "") }
        if list.isEmpty {
            empty("No project threads in the digest yet.")
        } else {
            Section("Project threads") {
                StateBar(threads: list).padding(.vertical, 6)
                ForEach(list) { thread in
                    HStack(spacing: 10) {
                        Circle().fill(Self.tint(thread.state)).frame(width: 9, height: 9)
                        Text(thread.title).lineLimit(1)
                        Spacer()
                        Text(Self.ago(thread.lastActivityAt)).font(.subheadline).foregroundStyle(Theme.frostDim)
                    }
                    .frame(minHeight: 44)
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(thread.stateWord)
                }
                .fullWidthSeparators()
            }
        }
    }

    /// One quiet line when there's nothing to show.
    private func empty(_ words: String) -> some View {
        Text(words).foregroundStyle(Theme.frostDim).listRowBackground(Color.clear)
    }

    /// Blue = working, orange = needs Dylan, green = ready for review, grey otherwise.
    static func tint(_ state: String) -> Color {
        switch state {
        case "working": return Theme.glacier
        case "blocked": return Theme.ember
        case "review_ready": return Theme.moss
        case "failed": return Theme.rose
        default: return Theme.frostFaint
        }
    }

    /// "2m", "3h", "1d".
    static func ago(_ raw: String?, now: Date = Date()) -> String {
        guard let raw, let at = ISODate.parse(raw) else { return "" }
        let minutes = max(0, Int(now.timeIntervalSince(at) / 60))
        if minutes < 60 { return "\(minutes)m" }
        if minutes < 1440 { return "\(minutes / 60)h" }
        return "\(minutes / 1440)d"
    }
}

/// One plan limit as a ring with its percent, name and reset time; a tap
/// flips between used and left, and the ring fills in when it first shows.
private struct LimitRing: View {
    let limit: ClaudeUsage.Limit
    let tint: Color
    @State private var showLeft = false
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var used: Int { min(max(limit.usedPct, 0), 100) }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.1), lineWidth: 11)
                Circle()
                    .trim(from: 0, to: shown ? CGFloat(used) / 100 : 0)
                    .stroke(tint, style: StrokeStyle(lineWidth: 11, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(showLeft ? 100 - used : used)%").font(.title3.weight(.semibold)).monospacedDigit()
                        .contentTransition(.numericText())
                    Text(ClaudeUsage.limitName(limit.name) + (showLeft ? " left" : " used")).font(.caption2).foregroundStyle(Theme.frostDim)
                }
            }
            .frame(width: 100, height: 100)
            .contentShape(Circle())
            .onTapGesture {
                Haptics.play(.tab)
                withAnimation(.snappy) { showLeft.toggle() }
            }
            .onAppear {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.8)) { shown = true }
            }
            if let reset = ClaudeUsage.resetWords(limit.resetsAt) {
                Text(reset).font(.caption).foregroundStyle(Theme.frostDim)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Seven bars, the picked day solid and the rest faded; tokens, or dollars.
/// Tap a bar or slide a finger across them to read that day's numbers above;
/// a dashed line marks the week's average.
private struct WeekBars: View {
    let days: [ClaudeUsage.Day]
    let tokens: Bool
    /// The picked day (nil: today, the last one).
    @State private var picked: String?

    private func value(_ day: ClaudeUsage.Day) -> Double {
        tokens ? Double(day.tokens ?? 0) : (day.usd ?? 0)
    }

    private var current: ClaudeUsage.Day? {
        days.first { $0.date == picked } ?? days.last
    }

    /// "Today", or "Tue, Nov 25".
    private static func heading(_ date: String) -> String {
        if date == ActivityDay.key(Date()) { return "Today" }
        guard let day = ActivityDay.date(date) else { return date }
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US")
        format.dateFormat = "EEE, MMM d"
        return format.string(from: day)
    }

    /// "1.2M tokens · $1.00" for a day.
    private static func words(_ day: ClaudeUsage.Day) -> String {
        var parts: [String] = []
        if let t = day.tokens { parts.append(ClaudeUsage.tokenWords(t) + " tokens") }
        parts.append(ClaudeUsage.dollars(day.usd ?? 0))
        return parts.joined(separator: " · ")
    }

    var body: some View {
        let top = max(days.map(value).max() ?? 0, 1e-9)
        let average = days.isEmpty ? 0 : days.map(value).reduce(0, +) / Double(days.count)
        VStack(alignment: .leading, spacing: 8) {
            if let current {
                HStack(alignment: .firstTextBaseline) {
                    Text(Self.heading(current.date)).font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(Self.words(current)).font(.subheadline).foregroundStyle(Theme.frostDim).monospacedDigit()
                        .contentTransition(.numericText())
                }
            }
            GeometryReader { geo in
                let width = geo.size.width / CGFloat(max(days.count, 1))
                ZStack(alignment: .bottomLeading) {
                    HStack(alignment: .bottom, spacing: 6) {
                        ForEach(days) { day in
                            RoundedRectangle(cornerRadius: 4)
                                .fill(ClaudeView.claude.opacity(day.date == current?.date ? 1 : 0.4))
                                .frame(height: max(2, 64 * value(day) / top))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    // The week's average as a dashed line across the bars.
                    if average > 0 {
                        Path { path in
                            let y = 64 - 64 * average / top
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: geo.size.width, y: y))
                        }
                        .stroke(Theme.frostFaint, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .frame(height: 64)
                    }
                }
                .frame(height: 64, alignment: .bottom)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                    let index = min(max(Int(drag.location.x / width), 0), days.count - 1)
                    guard days.indices.contains(index), days[index].date != current?.date else { return }
                    Haptics.play(.tab)
                    withAnimation(.snappy(duration: 0.2)) { picked = days[index].date }
                })
            }
            .frame(height: 64)
            HStack(spacing: 6) {
                ForEach(days) { day in
                    Text(ClaudeUsage.dayLetter(day.date)).font(.caption2.weight(day.date == current?.date ? .bold : .regular))
                        .foregroundStyle(day.date == current?.date ? Theme.frost : Theme.frostFaint)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tokens ? "Tokens each day this week" : "Spend each day this week")
        .accessibilityValue(current.map { Self.heading($0.date) + ", " + Self.words($0) } ?? "")
        .accessibilityAdjustableAction { direction in
            guard let at = days.firstIndex(where: { $0.date == current?.date }) else { return }
            let next = direction == .increment ? at + 1 : at - 1
            if days.indices.contains(next) { picked = days[next].date }
        }
    }
}

/// Today's and the week's spend, tokens and calls as small tiles; today's
/// spend has a bar against Jarvis's daily background budget.
private struct CostTiles: View {
    let use: ClaudeUsage

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            tile("Today", ClaudeUsage.dollars(use.todayUSD), note: use.dailyUsd.map { "of \(ClaudeUsage.dollars($0)) budget" }, fill: use.dailyUsd.map { $0 > 0 ? use.todayUSD / $0 : 0 })
            tile("This week", ClaudeUsage.dollars(use.weekUSD), note: "\(ClaudeUsage.dollars(use.dailyAverageUSD)) a day", fill: nil)
            tile("Month at this pace", ClaudeUsage.dollars(use.monthPaceUSD), note: "the daily average × 30", fill: nil)
            if let busiest = use.busiestDay {
                tile("Busiest day", ClaudeUsage.dollars(busiest.usd ?? 0), note: Self.weekday(busiest.date), fill: nil)
            }
            if let tokens = use.todayTokens { tile("Tokens today", ClaudeUsage.tokenWords(tokens), note: use.weekTokens.map { ClaudeUsage.tokenWords($0) + " this week" }, fill: nil) }
            if let calls = use.todayCalls { tile("Calls today", "\(calls)", note: "\(use.today.count) kinds of work", fill: nil) }
        }
    }

    /// "Tuesday" from "2026-11-25".
    private static func weekday(_ date: String) -> String? {
        guard let day = ActivityDay.date(date) else { return nil }
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US")
        format.dateFormat = "EEEE"
        return format.string(from: day)
    }

    /// A tile: name, big number, a note and, for the budget, a thin bar.
    private func tile(_ title: String, _ value: String, note: String?, fill: Double?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(Theme.frostDim)
            Text(value).font(.system(size: 22, weight: .bold, design: .rounded)).monospacedDigit()
            if let fill {
                Capsule().fill(Color.white.opacity(0.1)).frame(height: 5)
                    .overlay(alignment: .leading) {
                        GeometryReader { geo in
                            Capsule().fill(fill > 1 ? Theme.rose : ClaudeView.claude).frame(width: geo.size.width * min(max(fill, 0), 1))
                        }
                    }
            }
            if let note { Text(note).font(.caption).foregroundStyle(Theme.frostDim).lineLimit(1) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.06)))
        .accessibilityElement(children: .combine)
    }
}

/// One kind of work: name, a short bar against the biggest, tokens and dollars.
private struct KindRow: View {
    let kind: ClaudeUsage.Kind
    let top: ClaudeUsage.Kind?
    let tokens: Bool
    /// Opened by a tap: a second line with calls, tokens and dollars.
    var open = false

    private var share: Double {
        if tokens { return Double(kind.tokens ?? 0) / Double(max(top?.tokens ?? 1, 1)) }
        return (kind.usd ?? 0) / max(top?.usd ?? 1, 1e-9)
    }

    private var words: String {
        var parts: [String] = []
        if tokens, let t = kind.tokens { parts.append(ClaudeUsage.tokenWords(t)) }
        if let usd = kind.usd, usd > 0 { parts.append(String(format: "$%.2f", usd)) }
        return parts.joined(separator: " · ")
    }

    /// "9 calls · 900K tokens · $0.00".
    private var details: String {
        var parts: [String] = []
        if let calls = kind.calls { parts.append("\(calls) call" + (calls == 1 ? "" : "s")) }
        if let calls = kind.calls, calls > 0, let usd = kind.usd, usd > 0 { parts.append(ClaudeUsage.dollars(usd / Double(calls)) + " a call") }
        if let t = kind.tokens { parts.append(ClaudeUsage.tokenWords(t) + " tokens") }
        parts.append(ClaudeUsage.dollars(kind.usd ?? 0))
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text(ClaudeUsage.kindName(kind.kind)).lineLimit(1)
                Spacer()
                Capsule().fill(Color.white.opacity(0.1)).frame(width: 60, height: 6)
                    .overlay(alignment: .leading) {
                        Capsule().fill(ClaudeView.claude).frame(width: 60 * min(max(share, 0), 1), height: 6)
                    }
                Text(words).font(.subheadline).foregroundStyle(Theme.frostDim).monospacedDigit()
            }
            if open {
                Text(details).font(.caption).foregroundStyle(Theme.frostDim).monospacedDigit()
                    .transition(.opacity)
            }
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// The thread states as one split bar with a legend.
private struct StateBar: View {
    let threads: [ClaudeThread]

    var body: some View {
        let states = ["working", "blocked", "review_ready", "done"]
        let counts = states.map { state in (state, threads.filter { $0.state == state }.count) }.filter { $0.1 > 0 }
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(counts, id: \.0) { state, count in
                        Rectangle().fill(ClaudeView.tint(state))
                            .frame(width: max(0, geo.size.width * CGFloat(count) / CGFloat(max(threads.count, 1)) - 2))
                    }
                }
            }
            .frame(height: 10)
            .clipShape(Capsule())
            HStack(spacing: 12) {
                ForEach(counts, id: \.0) { state, count in
                    HStack(spacing: 5) {
                        Circle().fill(ClaudeView.tint(state)).frame(width: 8, height: 8)
                        Text("\(threads.first { $0.state == state }?.stateWord ?? "") \(count)")
                    }
                    .font(.caption).foregroundStyle(Theme.frostDim)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// One of today's job rows: done or failed with its time, or next up.
struct ScheduleRow: Identifiable {
    let id: String
    let name: String
    let when: String
    let tint: Color
    let isNext: Bool
    let sortKey: Date

    /// Jobs that ran today or run later today, in time order; the first
    /// one still to come reads "Next · 6:00 PM".
    static func rows(_ jobs: [JobRecord], now: Date = Date()) -> [ScheduleRow] {
        let calendar = Calendar.current
        var rows: [ScheduleRow] = []
        for job in jobs {
            if let raw = job.lastRun, let at = ISODate.parse(raw), calendar.isDate(at, inSameDayAs: now) {
                let failed = job.status == "error"
                rows.append(ScheduleRow(id: job.id + "-last", name: job.name, when: (failed ? "Failed · " : "") + time(at), tint: failed ? Theme.rose : Theme.moss, isNext: false, sortKey: at))
            }
            if let raw = job.nextRun, let at = ISODate.parse(raw), at > now, calendar.isDate(at, inSameDayAs: now) {
                rows.append(ScheduleRow(id: job.id + "-next", name: job.name, when: time(at), tint: Theme.frostFaint, isNext: false, sortKey: at))
            }
        }
        rows.sort { $0.sortKey < $1.sortKey }
        if let first = rows.firstIndex(where: { $0.sortKey > now }) {
            let row = rows[first]
            rows[first] = ScheduleRow(id: row.id, name: row.name, when: "Next · " + row.when, tint: Theme.glacier, isNext: true, sortKey: row.sortKey)
        }
        return rows
    }

    /// "6:00 PM".
    private static func time(_ date: Date) -> String {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US")
        format.dateFormat = "h:mm a"
        return format.string(from: date)
    }
}
