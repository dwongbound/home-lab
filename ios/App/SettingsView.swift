// Settings: which address the app talks to, and whether it's reachable;
// Jarvis's voice and his memory (2026-11-26, moved from the web page).
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var checking = false
    @AppStorage(PhoneKioskMonitor.enabledKey) private var bedside = true
    @AppStorage(AppModel.idleKioskKey) private var idleKiosk = true
    @AppStorage(PushCenter.enabledKey) private var pushOn = true
    @AppStorage(Haptics.settingKey) private var haptics = true
    @AppStorage(SleepSync.enabledKey) private var sleepOn = true
    @ObservedObject private var push = PushCenter.shared
    @AppStorage(OrbTuning.dotsKey) private var dotsRiseMs: Double = OrbTuning.dotsDefault
    @AppStorage(OrbTuning.coreKey) private var coreRiseMs: Double = OrbTuning.coreDefault

    /// Connection section with a Check button; Close in the corner.
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Group {
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
                    }
                    .fullWidthSeparators()
                } header: {
                    Text("Jarvis")
                } footer: {
                    Text("Reached through Tailscale. Tailscale signs you in, so there's no password. Turn on VPN On Demand in the Tailscale app so it reconnects by itself.")
                }
                Section {
                    NavigationLink("Memory") { MemoryView() }
                    NavigationLink("Claude") { ClaudeView(today: app.today) }
                } footer: {
                    Text("What Jarvis remembers, as a web you can drag around. Claude: his plan usage, jobs and project threads.")
                }
                VoiceSection()
                if UIDevice.current.userInterfaceIdiom == .phone {
                    Section {
                        Group {
                            Toggle("Haptics", isOn: $haptics)
                        }
                        .fullWidthSeparators()
                    } footer: {
                        Text("Small taps as you switch pages, send, and when Jarvis answers or a call connects.")
                    }
                    if SleepSync.available {
                        Section {
                            Group {
                                Toggle("Sleep details", isOn: $sleepOn)
                            }
                            .fullWidthSeparators()
                        } footer: {
                            Text("Sends each night's sleep from Apple Health (stages, heart rate, breathing, oxygen, wrist temperature) to your own Jarvis, in the morning. Nothing is written to Health. To change what Jarvis may read, open the Health app, then Sharing, Apps, Jarvis.")
                        }
                    }
                    Section {
                        Group {
                            Toggle("Bedside display", isOn: $bedside)
                        }
                        .fullWidthSeparators()
                    } footer: {
                        Text("Turn the phone on its side while it's charging and Jarvis shows a big clock, the orb and what's next. Tap it for Close. Never shows money.")
                    }
                }
                Section {
                    Group {
                        Toggle("Notifications", isOn: $pushOn)
                            .onChange(of: pushOn) { _, on in PushCenter.shared.setEnabled(on) }
                        // Whether push is actually working, in words.
                        Text(push.status.words)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .fullWidthSeparators()
                } footer: {
                    Text("Jarvis's messages, approvals and alerts as banners, even when the app is closed. Approve from the lock screen needs the phone unlocked. At night a Focus such as Sleep can hold them in Notification Center; allow Jarvis in that Focus to see them.")
                }
                .task { await push.refreshStatus() }
                if UIDevice.current.userInterfaceIdiom == .pad {
                    Section {
                        Group {
                            Toggle("Kiosk when idle on charge", isOn: $idleKiosk)
                        }
                        .fullWidthSeparators()
                    } footer: {
                        Text("After five quiet minutes on Talk or Chat while the iPad is charging, it switches to the kiosk by itself.")
                    }
                }
                Section {
                    Group {
                        tuning("Dots (your voice)", value: $dotsRiseMs)
                        tuning("Inner orb (Jarvis)", value: $coreRiseMs)
                        Button("Reset to defaults") {
                            dotsRiseMs = OrbTuning.dotsDefault
                            coreRiseMs = OrbTuning.coreDefault
                        }
                    }
                    .fullWidthSeparators()
                } header: {
                    Text("Orb feel")
                } footer: {
                    Text("How fast the orb follows a voice. Lower is snappier and moves more with each syllable; higher is calmer and smoother. Changes show on the Talk orb straight away.")
                }
            }
            .jarvisRows()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                SheetClose { dismiss() }
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
    }
}
