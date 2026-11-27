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
    /// The reading each gauge's line is showing, by gauge.
    @State private var picked: [String: Int] = [:]

    var body: some View {
        let snapshot = today.snapshot ?? fallback
        VStack(spacing: 14) {
            SystemCheckedLabel(generatedAt: snapshot.generatedAt, scale: 1.15)
                .frame(maxWidth: .infinity, alignment: .trailing)
            ForEach(snapshot.systemGauges) { gauge in
                section(gauge, snapshot: snapshot)
            }
            if let model = snapshot.localModel {
                LocalModelRow(model: model, today: today)
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
            // Tap or press and slide to read a reading (Dylan, 2026-11-27).
            let pick = Binding<Int?>(get: { picked[gauge.id] }, set: { picked[gauge.id] = $0 })
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    if let index = picked[gauge.id], let words = gauge.historyText(index) {
                        Text(words).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(SystemStyle.tint(gauge.kind))
                        Spacer()
                        Text(gauge.historyAge(index)).font(.caption).foregroundStyle(Theme.frostDim)
                    } else {
                        Text("Tap or slide along the line to read it").font(.caption).foregroundStyle(Theme.frostFaint)
                    }
                }
                .frame(height: 20)
                Sparkline(values: gauge.history, tint: SystemStyle.tint(gauge.kind), scale: 1.2, picked: picked[gauge.id])
                    .frame(height: 54)
                    .background(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) }
                    .chartScrub(count: gauge.history.count, picked: pick)
            }
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

/// Jarvis's local model: how much of the graphics card it holds, and Load
/// or Unload after a confirm (the web page's model card, 2026-11-26).
private struct LocalModelRow: View {
    let model: LocalModel
    @ObservedObject var today: TodayModel
    @EnvironmentObject private var app: AppModel
    @State private var asking = false
    @State private var busy = false
    @State private var problem: String?

    var body: some View {
        HStack(spacing: 12) {
            SystemRingFill(fraction: model.loaded ? min(1, (model.vramGb ?? 0) / 12) : 0)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("Local model").font(.headline).foregroundStyle(Theme.frost)
                Text(model.loaded ? "\(model.name) · \(SystemGauge.number(model.vramGb ?? 0)) GB" : "\(model.name) · unloaded")
                    .font(.caption).foregroundStyle(Theme.frostDim)
                if let problem { Text(problem).font(.caption).foregroundStyle(Theme.rose) }
            }
            Spacer()
            if busy {
                ProgressView().accessibilityLabel(model.loaded ? "Unloading" : "Loading")
            } else {
                Button(model.loaded ? "Unload" : "Load") { asking = true }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
            }
        }
        .padding(16)
        .glassPanel()
        .confirmationDialog(model.loaded ? "Unload the local model?" : "Load the local model?", isPresented: $asking, titleVisibility: .visible) {
            Button(model.loaded ? "Unload" : "Load") { Task { await run() } }
        } message: {
            Text(model.loaded ? "Frees its graphics memory. Jarvis loads it again when he needs it." : "Takes up to a minute and uses about 6 GB of graphics memory.")
        }
    }

    /// Runs it, then refreshes so the ring shows the result.
    private func run() async {
        busy = true
        problem = nil
        do {
            _ = try await app.client.setLocalModel(loaded: !model.loaded)
            Haptics.play(.runOK)
        } catch {
            problem = error.localizedDescription
            Haptics.play(.runFailed)
        }
        await today.load(app: app)
        busy = false
    }
}

/// A plain ring filled to `fraction`, in the graphics card's colour.
private struct SystemRingFill: View {
    let fraction: Double

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.10), lineWidth: 6)
            Circle().trim(from: 0, to: fraction)
                .stroke(SystemStyle.tint(.gpu), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}
