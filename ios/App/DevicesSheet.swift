// The Home drawer (Dylan, 2026-11-19: "when i click home it should show a
// drawer of all my devices in a scrollable list … i cant see the full
// name"). Every device in the snapshot already on hand, grouped, each name
// in full; sensor readings in a quiet section at the end. Read-only, as the
// Home card is: nothing here controls a device.
import SwiftUI
import JarvisKit

struct DevicesSheet: View {
    let home: Home
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(DeviceGroups.groups(home.devices), id: \.title) { group in
                    Section(group.title) {
                        ForEach(group.devices) { device in
                            DeviceRow(device: device)
                                .equatable()
                                .listRowBackground(Color.white.opacity(0.06))
                        }
                    }
                }
                if let readings = home.readings, !readings.isEmpty {
                    Section("Readings") {
                        ForEach(readings) { reading in
                            HStack {
                                Text(reading.name).fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 12)
                                Text(reading.value + (reading.unit.map { " \($0)" } ?? ""))
                                    .foregroundStyle(Theme.frostDim)
                                    .monospacedDigit()
                            }
                            .frame(minHeight: 44)
                            .listRowBackground(Color.white.opacity(0.06))
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.sky.ignoresSafeArea())
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.ultraThinMaterial)
        .preferredColorScheme(.dark)
        .fontDesign(.rounded)
    }
}

/// One device: its symbol, the whole name (wrapping, never cut), its state.
private struct DeviceRow: View, Equatable {
    let device: Device

    static func == (a: DeviceRow, b: DeviceRow) -> Bool {
        a.device.id == b.device.id && a.device.name == b.device.name && a.device.state == b.device.state
            && a.device.detail == b.device.detail && a.device.current == b.device.current && a.device.target == b.device.target
            && a.device.brightness == b.device.brightness && a.device.available == b.device.available
    }

    var body: some View {
        let on = device.isOn
        HStack(spacing: 12) {
            Image(systemName: TodayWording.deviceSymbol(device))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(on ? Theme.ember : Theme.frostFaint)
                .frame(width: 32, height: 32)
                .background(Circle().fill(on ? Theme.ember.opacity(0.18) : Color.white.opacity(0.06)))
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.body.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(device.isAvailable ? TodayWording.deviceState(device) : "Not responding")
                    .font(.subheadline)
                    .foregroundStyle(Theme.frostDim)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}
