// Home's System panel and its drawer (Dylan, 2026-11-21: "is the gpu usage
// information live on my homescreen? can we add the same for RAM? and when
// clicking that panel we see the breakdowns for each device? also add disk
// storage"). The panel: a ring per gauge (GPU, memory, disk, CPU), each
// split into its holders' colours when Jarvis names them, with the last
// few minutes as a sparkline. A tap opens the drawer: one section per
// gauge with its numbers, its history and, when the server sends one, who
// holds what. It reads the live snapshot, so both move with each refresh.
import SwiftUI
import JarvisKit

struct SystemPanel: View {
    let snapshot: Snapshot
    @State private var open = false

    var body: some View {
        Button {
            Haptics.play(.tab)
            open = true
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "desktopcomputer").font(.footnote.weight(.semibold)).foregroundStyle(Theme.glacier)
                    Text("System").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.frost)
                    Spacer()
                    // When the PC was read (Dylan, 2026-11-21: "so i know").
                    SystemCheckedLabel(generatedAt: snapshot.generatedAt)
                    Text("›").font(.caption).foregroundStyle(Theme.frostDim)
                }
                SystemGaugeRow(snapshot: snapshot, ringSize: snapshot.systemGauges.count > 3 ? 58 : 66)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassPanel()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the breakdown")
        .sheet(isPresented: $open) { SystemDrawer() }
        #if DEBUG
        .onAppear { if ProcessInfo.processInfo.arguments.contains("-openSystem") { open = true } }
        #endif
    }
}

/// The drawer: GPU, memory, disks, then the processor.
struct SystemDrawer: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.sky.ignoresSafeArea()
                ScrollView {
                    if let snapshot = app.today.snapshot {
                        SystemDrawerBody(today: app.today, fallback: snapshot)
                    }
                }
            }
            .navigationTitle("System")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { SheetClose { dismiss() } }
        }
        .presentationDetents([.large])
    }
}

/// Observes the snapshot so the drawer moves with each refresh.
private struct SystemDrawerBody: View {
    @ObservedObject var today: TodayModel
    let fallback: Snapshot

    var body: some View {
        let snapshot = today.snapshot ?? fallback
        VStack(spacing: 14) {
            SystemCheckedLabel(generatedAt: snapshot.generatedAt, scale: 1.15)
                .frame(maxWidth: .infinity, alignment: .trailing)
            ForEach(snapshot.systemGauges) { gauge in
                section(gauge, snapshot: snapshot)
            }
            Text("The lines are the last \(historyCount(snapshot)) readings, a few minutes' worth.")
                .font(.caption).foregroundStyle(Theme.frostFaint)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
        }
        .padding(16)
    }

    private func historyCount(_ snapshot: Snapshot) -> Int {
        snapshot.systemGauges.map(\.history.count).max() ?? 0
    }

    @ViewBuilder
    private func section(_ gauge: SystemGauge, snapshot: Snapshot) -> some View {
        let breakdown = snapshot.breakdown(for: gauge.kind)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: gauge.symbol).foregroundStyle(SystemStyle.tint(gauge.kind))
                Text(gauge.kind == .gpu ? "Graphics card" : gauge.kind == .disk ? "Disk" : gauge.kind == .ram ? "Memory" : "Processor")
                    .font(.headline).foregroundStyle(Theme.frost)
                Spacer()
                if gauge.kind == .ram, let scope = snapshot.ram?.scopeWords {
                    Text(scope).font(.caption.weight(.medium)).foregroundStyle(Theme.frostDim)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                }
            }
            HStack(alignment: .center, spacing: 16) {
                SystemRing(gauge: gauge, breakdown: breakdown, scale: 1.3, size: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(gauge.amountText).font(.title3.weight(.semibold)).monospacedDigit().foregroundStyle(Theme.frost)
                    if let free = gauge.freeText {
                        Text(free).font(.subheadline).foregroundStyle(Theme.frostDim)
                    }
                    if gauge.kind == .gpu, let busy = snapshot.gpuShare?.utilization {
                        busyBar(busy)
                    }
                }
                Spacer(minLength: 0)
            }
            Sparkline(values: gauge.history, tint: SystemStyle.tint(gauge.kind), scale: 1.2)
                .frame(height: 54)
                .background(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) }
            if gauge.kind == .disk, !snapshot.diskBreakdowns.isEmpty {
                ForEach(snapshot.diskBreakdowns) { disk in
                    breakdownBlock(disk, heading: disk.headline)
                }
            } else if let breakdown {
                breakdownBlock(breakdown, heading: gauge.kind == .gpu ? "Who's using it" : "What's using it")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel()
    }

    private func breakdownBlock(_ breakdown: SystemBreakdown, heading: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(heading).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.frost)
                if let note = breakdown.note, breakdown.id != "ram", breakdown.id != "gpu" {
                    Text(note).font(.caption).foregroundStyle(Theme.frostFaint)
                }
            }
            SystemBreakdownBar(breakdown: breakdown)
            if let grows = breakdown.growsToGb {
                Text("Grows as it fills, up to \(SystemGauge.number(grows)) GB").font(.caption).foregroundStyle(Theme.frostFaint)
            }
        }
        .padding(.top, 4)
    }

    /// How busy the card is, as a short bar.
    private func busyBar(_ busy: Double) -> some View {
        HStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.10))
                    Capsule().fill(SystemStyle.tint(.gpu)).frame(width: geo.size.width * CGFloat(busy / 100))
                }
            }
            .frame(width: 90, height: 6)
            Text("\(Int(busy.rounded()))% busy").font(.caption).monospacedDigit().foregroundStyle(Theme.frostDim)
        }
        .accessibilityElement(children: .combine)
    }
}
