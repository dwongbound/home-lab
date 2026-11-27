// The Home drawer (Dylan, 2026-11-19: "when i click home it should show a
// drawer of all my devices in a scrollable list … i cant see the full
// name"). Every device in the snapshot already on hand, grouped, each name
// in full; sensor readings in a quiet section at the end. Since
// 2026-11-20 a grid, two to a row on the iPhone (more on the iPad), clearer
// than the card: whole names, the state in words, lit when on. Since
// 2026-11-26 a tap switches a light, switch, fan or TV (the web page's
// controls moving into the app).
import SwiftUI
import JarvisKit

struct DevicesSheet: View {
    @ObservedObject var today: TodayModel
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    /// The device being switched (a spinner on its tile) and the last failure.
    @State private var busy: String?
    @State private var problem: String?

    /// The latest snapshot's home, so a switch shows once the refresh lands.
    private var home: Home? { today.snapshot?.home }

    /// Two tiles a row on an iPhone, more as the iPad's width allows.
    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 12, alignment: .top)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22, pinnedViews: []) {
                    if let problem {
                        Text(problem).font(.footnote).foregroundStyle(Theme.rose)
                    }
                    ForEach(DeviceGroups.groups(home?.devices ?? []), id: \.title) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(group.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.frostDim)
                                .accessibilityAddTraits(.isHeader)
                            // Tiles in a row share its height (the tile fills it).
                            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                                ForEach(group.devices) { device in
                                    if let command = Self.command(device) {
                                        Button { Task { await flip(device, command) } } label: {
                                            DeviceTile(device: device, full: true)
                                                .overlay(alignment: .topTrailing) {
                                                    if busy == device.id { ProgressView().padding(6) }
                                                }
                                        }
                                        .buttonStyle(.plain)
                                        .disabled(busy != nil)
                                    } else {
                                        DeviceTile(device: device, full: true)
                                    }
                                }
                            }
                        }
                    }
                    if let readings = home?.readings, !readings.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Readings")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.frostDim)
                                .accessibilityAddTraits(.isHeader)
                            VStack(spacing: 0) {
                                ForEach(readings) { reading in
                                    HStack {
                                        Text(reading.name).fixedSize(horizontal: false, vertical: true)
                                        Spacer(minLength: 12)
                                        Text(reading.value + (reading.unit.map { " \($0)" } ?? ""))
                                            .foregroundStyle(Theme.frostDim)
                                            .monospacedDigit()
                                    }
                                    .frame(minHeight: 44)
                                    .padding(.horizontal, 14)
                                    if reading.id != readings.last?.id { Divider().overlay(Theme.glassEdge) }
                                }
                            }
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.04)))
                        }
                    }
                }
                .padding(16)
            }
            .background(Theme.sky.ignoresSafeArea())
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                SheetClose { dismiss() }
            }
        }
        // Full height (Dylan, 2026-11-20: "default open a full drawer, not half").
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.ultraThinMaterial)
        .preferredColorScheme(.dark)
        .fontDesign(.rounded)
    }

    /// The command a tap sends, or nil for things a tap can't switch
    /// (thermostats, locks, covers: same set as the Watch).
    static func command(_ device: Device) -> String? {
        guard device.isAvailable else { return nil }
        switch device.kind {
        case "light", "switch", "fan": return "toggle"
        case "media": return "power"
        default: return nil
        }
    }

    /// Switches it at home, then refreshes so the tile shows the new state.
    private func flip(_ device: Device, _ command: String) async {
        busy = device.id
        problem = nil
        do {
            try await app.client.homeControl(entity: device.id, command: command)
            Haptics.play(.runOK)
        } catch {
            problem = error.localizedDescription
            Haptics.play(.runFailed)
        }
        await today.load(app: app)
        busy = nil
    }
}
