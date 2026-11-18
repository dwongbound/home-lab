// Settings: which address the app talks to, and whether it's reachable.
// Voice, Memory and notifications arrive with later milestones.
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var checking = false
    @AppStorage(PhoneKioskMonitor.enabledKey) private var bedside = true
    @AppStorage(AppModel.idleKioskKey) private var idleKiosk = true
    @AppStorage(OrbTuning.dotsKey) private var dotsRiseMs: Double = OrbTuning.dotsDefault
    @AppStorage(OrbTuning.coreKey) private var coreRiseMs: Double = OrbTuning.coreDefault

    /// Connection section with a Check button; Close in the corner.
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://jarvis.snakebird-ph.ts.net", text: $app.server)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    HStack {
                        Text(statusWords).foregroundStyle(statusColor)
                        Spacer()
                        if checking {
                            ProgressView().accessibilityLabel("Checking")
                        } else {
                            Button("Check") { check() }
                        }
                    }
                    .frame(minHeight: 44)
                } header: {
                    Text("Jarvis")
                } footer: {
                    Text("Reached through Tailscale. Tailscale signs you in, so there's no password. Turn on VPN On Demand in the Tailscale app so it reconnects by itself.")
                }
                if UIDevice.current.userInterfaceIdiom == .phone {
                    Section {
                        Toggle("Bedside display", isOn: $bedside)
                            .frame(minHeight: 44)
                    } footer: {
                        Text("Turn the phone on its side while it's charging and Jarvis shows a big clock, the orb and what's next. Tap it for Close. Never shows money.")
                    }
                }
                if UIDevice.current.userInterfaceIdiom == .pad {
                    Section {
                        Toggle("Kiosk when idle on charge", isOn: $idleKiosk)
                            .frame(minHeight: 44)
                    } footer: {
                        Text("After five quiet minutes on Talk or Chat while the iPad is charging, it switches to the kiosk by itself.")
                    }
                }
                Section {
                    tuning("Dots (your voice)", value: $dotsRiseMs)
                    tuning("Inner orb (Jarvis)", value: $coreRiseMs)
                    Button("Reset to defaults") {
                        dotsRiseMs = OrbTuning.dotsDefault
                        coreRiseMs = OrbTuning.coreDefault
                    }
                } header: {
                    Text("Orb feel")
                } footer: {
                    Text("How fast the orb follows a voice. Lower is snappier and moves more with each syllable; higher is calmer and smoother. Changes show on the Talk orb straight away.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    /// Connected, can't reach, or not tried yet.
    private var statusWords: String {
        switch app.reachable {
        case .some(true): return "Connected"
        case .some(false): return "Can’t reach Jarvis"
        case .none: return "Not checked yet"
        }
    }

    /// Green, rose or quiet, to match the words.
    private var statusColor: Color {
        switch app.reachable {
        case .some(true): return Theme.moss
        case .some(false): return Theme.rose
        case .none: return Theme.frostDim
        }
    }

    /// Asks the PC for a snapshot to see if it answers.
    private func check() {
        checking = true
        Task {
            do {
                _ = try await app.client.snapshot()
                app.noteReach(nil)
            } catch {
                app.noteReach(error)
            }
            checking = false
        }
    }

    /// One smoothing slider: 20 ms (snappy) to 250 ms (calm), with the value shown.
    private func tuning(_ title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value.wrappedValue)) ms")
                    .monospacedDigit()
                    .foregroundStyle(Theme.frostDim)
            }
            Slider(value: value, in: 20...250, step: 5) {
                Text(title)
            } minimumValueLabel: {
                Text("Snappy").font(.caption2)
            } maximumValueLabel: {
                Text("Calm").font(.caption2)
            }
        }
        .padding(.vertical, 4)
    }
}
