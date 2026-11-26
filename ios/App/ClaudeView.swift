// Claude (Dylan 2026-11-26, mockup approved): Jarvis's plan usage as two
// rings with reset times, tokens this week as bars and by kind of work;
// what's running and today's jobs; the Claude project threads. All read
// from the snapshot the app already loads, so it adds no requests.
import SwiftUI
import JarvisKit

struct ClaudeView: View {
    @ObservedObject var today: TodayModel
    @State private var tab = 0

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
            Section {
                WeekBars(days: use.days, tokens: use.hasTokens)
                    .frame(height: 90)
                    .padding(.vertical, 6)
                ForEach(use.kindsByUse) { kind in
                    KindRow(kind: kind, top: use.kindsByUse.first, tokens: use.hasTokens)
                }
                .fullWidthSeparators()
            } header: {
                Text(use.hasTokens ? "Tokens this week" : "Spend this week")
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

/// One plan limit as a ring with its percent, name and reset time.
private struct LimitRing: View {
    let limit: ClaudeUsage.Limit
    let tint: Color

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.1), lineWidth: 11)
                Circle()
                    .trim(from: 0, to: CGFloat(min(max(limit.usedPct, 0), 100)) / 100)
                    .stroke(tint, style: StrokeStyle(lineWidth: 11, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(limit.usedPct)%").font(.title3.weight(.semibold)).monospacedDigit()
                    Text(ClaudeUsage.limitName(limit.name)).font(.caption2).foregroundStyle(Theme.frostDim)
                }
            }
            .frame(width: 100, height: 100)
            if let reset = ClaudeUsage.resetWords(limit.resetsAt) {
                Text(reset).font(.caption).foregroundStyle(Theme.frostDim)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Seven bars, today solid and the rest faded; tokens, or dollars without them.
private struct WeekBars: View {
    let days: [ClaudeUsage.Day]
    let tokens: Bool

    private func value(_ day: ClaudeUsage.Day) -> Double {
        tokens ? Double(day.tokens ?? 0) : (day.usd ?? 0)
    }

    var body: some View {
        let top = max(days.map(value).max() ?? 0, 1e-9)
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                VStack(spacing: 4) {
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(ClaudeView.claude.opacity(index == days.count - 1 ? 1 : 0.5))
                        .frame(height: max(2, 64 * value(day) / top))
                    Text(ClaudeUsage.dayLetter(day.date)).font(.caption2).foregroundStyle(Theme.frostFaint)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tokens ? "Tokens each day this week" : "Spend each day this week")
    }
}

/// One kind of work: name, a short bar against the biggest, tokens and dollars.
private struct KindRow: View {
    let kind: ClaudeUsage.Kind
    let top: ClaudeUsage.Kind?
    let tokens: Bool

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

    var body: some View {
        HStack(spacing: 10) {
            Text(ClaudeUsage.kindName(kind.kind)).lineLimit(1)
            Spacer()
            Capsule().fill(Color.white.opacity(0.1)).frame(width: 60, height: 6)
                .overlay(alignment: .leading) {
                    Capsule().fill(ClaudeView.claude).frame(width: 60 * min(max(share, 0), 1), height: 6)
                }
            Text(words).font(.subheadline).foregroundStyle(Theme.frostDim).monospacedDigit()
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
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
