// The Sleep screen, opened from Home's Sleep card like Diet (Dylan,
// 2026-11-20/21). Loads the last 14 nights when it opens (GET
// /api/jarvis/health/sleep?days=14), no pull to refresh. At the top, the
// week: seven nights as score rings, the averages and the week against
// 7.5 hours a night; swipe the row for the week before. Below, the night
// chosen (the latest recorded one at first): tap a ring, or swipe the page
// sideways, to move.
import SwiftUI
import JarvisKit

struct SleepDetailView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var nights: [SleepDay]?
    @State private var failed = false
    /// The night shown below the row (nil: the latest recorded one).
    @State private var chosen: String?
    /// Which week the row shows: 0 the latest, 1 the one before.
    @State private var page = 0

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.sky.ignoresSafeArea()
                VStack(spacing: 0) {
                    // The week stays at the top while the night scrolls below
                    // (Dylan, 2026-11-21, like Diet's week row).
                    if let nights { weekHeader(nights) }
                    List {
                        content
                    }
                    .jarvisRows()
                    .scrollContentBackground(.hidden)
                    // A sideways swipe moves a night, the row following.
                    .simultaneousGesture(DragGesture(minimumDistance: 24).onEnded { drag in
                        guard let step = DaySwipe.step(width: drag.translation.width, height: drag.translation.height) else { return }
                        move(by: step)
                    })
                }
            }
            .navigationTitle("Sleep")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                SheetClose { dismiss() }
            }
        }
        .task { await load() }
    }

    private var today: String { SleepNights.key(Date()) }

    /// The night the week row ends on, for the page in view.
    private func weekEnd(_ nights: [SleepDay]) -> String {
        var end = SleepWeek.endNight(today: today, nights: nights)
        for _ in 0..<(page * 7) { end = SleepCard.dayBefore(end) ?? end }
        return end
    }

    /// The night shown below: the chosen one, else the latest recorded.
    private func shownKey(_ nights: [SleepDay]) -> String {
        chosen ?? nights.first?.night ?? SleepWeek.endNight(today: today, nights: nights)
    }

    private func weekHeader(_ nights: [SleepDay]) -> some View {
        let week = SleepWeek(nights: nights, endNight: weekEnd(nights))
        let shown = shownKey(nights)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                if let asleep = week.averageAsleep {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(asleep).font(.title3.weight(.bold)).monospacedDigit().foregroundStyle(Theme.frost)
                        Text(week.recordedCount < 7 ? "avg asleep, \(week.recordedCount) nights" : "avg asleep").font(.caption).foregroundStyle(Theme.frostDim)
                    }
                }
                if let score = week.averageScore {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(score)").font(.title3.weight(.bold)).monospacedDigit().foregroundStyle(Theme.frost)
                        Text("avg score").font(.caption).foregroundStyle(Theme.frostDim)
                    }
                }
                Spacer()
                if let battery = week.battery {
                    // The week against 7.5 hours a night, over the nights recorded.
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(battery).font(.subheadline.weight(.semibold))
                            .foregroundStyle((week.balanceMinutes ?? 0) < -15 ? Theme.ember : SleepStyle.band("great"))
                        Text("vs 7h 30m a night").font(.caption).foregroundStyle(Theme.frostDim)
                    }
                }
            }
            HStack(spacing: 4) {
                ForEach(week.nights) { night in
                    Button {
                        Haptics.play(.tab)
                        withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { chosen = night.night }
                    } label: {
                        VStack(spacing: 6) {
                            Text(night.weekday).font(.caption2.weight(.semibold))
                                .foregroundStyle(night.night == shown ? Theme.frost : Theme.frostDim)
                            ZStack {
                                Circle().stroke(Color.white.opacity(night.recorded ? 0.14 : 0.07), lineWidth: 3)
                                if let ring = night.ring {
                                    Circle().trim(from: 0, to: ring)
                                        .stroke(SleepStyle.band(night.band), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                        .rotationEffect(.degrees(-90))
                                }
                                Text(night.dayNumber).font(.caption.weight(night.night == shown ? .bold : .medium))
                                    .foregroundStyle(night.recorded ? Theme.frost : Theme.frostFaint)
                            }
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(night.night == shown ? Color.white.opacity(0.10) : .clear))
                        }
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!night.recorded)
                    .accessibilityLabel("\(SleepCard.dayTitle(night.night))" + (night.score.map { ", score \($0)" } ?? (night.recorded ? "" : ", no record")))
                    .accessibilityAddTraits(night.night == shown ? .isSelected : [])
                }
            }
            // Swiping the row moves a week.
            .gesture(DragGesture(minimumDistance: 30).onEnded { drag in
                guard abs(drag.translation.width) > abs(drag.translation.height) else { return }
                if drag.translation.width > 0, page == 0, nights.count > 7 { withAnimation(.smooth) { page = 1 } }
                if drag.translation.width < 0, page > 0 { withAnimation(.smooth) { page = 0 } }
            })
        }
        .padding(14)
        .glassPanel()
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    /// One night on, or back, among the recorded ones; the row's week follows.
    private func move(by step: Int) {
        guard let nights else { return }
        let keys = nights.map(\.night).sorted()
        let current = shownKey(nights)
        guard let index = keys.firstIndex(of: current) else { return }
        let next = index + step
        guard keys.indices.contains(next) else { return }
        Haptics.play(.tab)
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
            chosen = keys[next]
            // The week holding it.
            let end = SleepWeek.endNight(today: today, nights: nights)
            let firstOfLatest = (0..<6).reduce(end) { k, _ in SleepCard.dayBefore(k) ?? k }
            page = keys[next] < firstOfLatest ? 1 : 0
        }
    }

    @ViewBuilder
    private var content: some View {
        if let nights {
            if let night = nights.first(where: { $0.night == shownKey(nights) }) {
                let card = SleepCard(summary: SleepSummary(last: night, trend: []), fallbackAsleepMinutes: nil, today: today)
                Section {
                    VStack(alignment: .leading, spacing: 16) {
                        SleepHeadline(card: card)
                        if !card.stages.isEmpty { SleepStageBar(shares: card.stages) }
                        SleepTimeline(stages: night.stages)
                        if !card.parts.isEmpty { SleepPartBars(parts: card.parts) }
                        if let interruptions = night.interruptions {
                            Label(interruptions == 1 ? "Woke once" : "Woke \(interruptions) times", systemImage: "moon.zzz.fill")
                                .font(.subheadline)
                                .foregroundStyle(Theme.frostDim)
                        }
                        if !card.vitals.isEmpty { SleepVitalTiles(vitals: card.vitals, columns: sizeClass == .regular ? 3 : 2) }
                    }
                    .padding(.vertical, 8)
                    .listRowBackground(Color.white.opacity(0.07))
                    .id(night.night)
                } header: {
                    // "Last night", or "Thursday night": the night, not the morning after.
                    Text(card.whenWords ?? SleepCard.dayTitle(night.night)).textCase(nil)
                }
            } else {
                Text("No sleep recorded yet.").foregroundStyle(Theme.frostDim).listRowBackground(Color.clear)
            }
        } else if failed {
            Text("Couldn't reach Jarvis for your sleep.")
                .foregroundStyle(Theme.frostDim)
                .listRowBackground(Color.clear)
        } else {
            HStack(spacing: 10) {
                ProgressView()
                Text("Loading your sleep").foregroundStyle(Theme.frostDim)
            }
            .listRowBackground(Color.clear)
        }
    }

    private func load() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-demoSnapshot") {
            nights = DemoSleep.nights(now: DemoSnapshot.now)
            return
        }
        #endif
        do {
            if let got = try await app.client.sleepNights(days: 14) {
                nights = got
            } else {
                failed = true
            }
        } catch {
            failed = true
        }
    }
}

/// The night as a timeline: a lane per stage (Awake on top, Deep at the
/// bottom, like Health), each stretch where it fell, with bed and wake
/// times under it. Says so plainly when the night's detail is gone.
struct SleepTimeline: View {
    let stages: [SleepDay.Stage]
    private let lanes = ["awake", "rem", "core", "deep"]
    private let laneNames = ["Awake", "REM", "Core", "Deep"]

    var body: some View {
        if let first = stages.first?.start, let last = stages.map(\.end).max(), last > first {
            let span = last.timeIntervalSince(first)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(laneNames, id: \.self) { name in
                            Text(name).font(.caption2).foregroundStyle(Theme.frostDim).frame(height: 18, alignment: .leading)
                        }
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .topLeading) {
                            ForEach(0..<lanes.count, id: \.self) { lane in
                                Rectangle().fill(Color.white.opacity(0.04))
                                    .frame(height: 14)
                                    .offset(y: CGFloat(lane) * 18 + 2)
                            }
                            ForEach(Array(stages.enumerated()), id: \.offset) { _, stage in
                                let lane = lanes.firstIndex(of: stage.stage == "unspecified" ? "core" : stage.stage) ?? 2
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(SleepStyle.color(stage.stage))
                                    .frame(width: max(2, geo.size.width * stage.end.timeIntervalSince(stage.start) / span), height: 14)
                                    .offset(x: geo.size.width * stage.start.timeIntervalSince(first) / span, y: CGFloat(lane) * 18 + 2)
                            }
                        }
                    }
                    .frame(height: 72)
                }
                HStack {
                    Text(SleepCard.clock(first))
                    Spacer()
                    Text(SleepCard.clock(last))
                }
                .font(.caption2)
                .foregroundStyle(Theme.frostFaint)
                .padding(.leading, 44)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Sleep stages from \(SleepCard.clock(first)) to \(SleepCard.clock(last))")
        } else {
            Text("No stage timeline for this night.")
                .font(.footnote)
                .foregroundStyle(Theme.frostDim)
        }
    }
}
