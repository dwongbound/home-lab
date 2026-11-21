// The Sleep screen, opened from Home's Sleep card like Diet (Dylan,
// 2026-11-20: "get better sleep info"). Loads the last 14 nights when it
// opens (GET /api/jarvis/health/sleep?days=14), no pull to refresh: the
// chosen night on top (score, time asleep, stages as a timeline, the
// score's parts, vitals), then the nights as a list of 44 pt rows. A tap on
// a night shows it on top.
import SwiftUI
import JarvisKit

struct SleepDetailView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var nights: [SleepDay]?
    @State private var failed = false
    @State private var chosen: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.sky.ignoresSafeArea()
                List {
                    content
                }
                .jarvisRows()
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Sleep")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if let nights {
            if let night = shownNight(nights) {
                let card = SleepCard(summary: SleepSummary(last: night, trend: []), fallbackAsleepMinutes: nil, today: night.night)
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
                } header: {
                    Text(SleepCard.dayTitle(night.night)).textCase(nil)
                }
            }
            Section {
                Group {
                    if nights.isEmpty {
                        Text("No nights yet.").foregroundStyle(Theme.frostDim)
                    }
                    ForEach(nights) { night in
                        Button { chosen = night.night } label: { row(night) }
                            .listRowBackground(Color.white.opacity(night.night == shownNight(nights)?.night ? 0.12 : 0.07))
                    }
                }
                .fullWidthSeparators()
            } header: {
                Text("Last 14 nights").textCase(nil)
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

    /// One night in the list: the day, time asleep, and the score with its band colour.
    private func row(_ night: SleepDay) -> some View {
        HStack {
            Text(SleepCard.dayTitle(night.night)).foregroundStyle(Theme.frost)
            Spacer()
            if let asleep = night.minutes?.asleep {
                Text(SleepCard.hours(asleep)).monospacedDigit().foregroundStyle(Theme.frostDim)
            }
            if let score = night.score {
                Text("\(score)")
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(SleepStyle.band(night.scoreBand))
                    .frame(minWidth: 32, alignment: .trailing)
            }
        }
        .frame(minHeight: Rows.minHeight)
        .contentShape(Rectangle())
    }

    private func shownNight(_ nights: [SleepDay]) -> SleepDay? {
        nights.first { $0.night == chosen } ?? nights.first
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
