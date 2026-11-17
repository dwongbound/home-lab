// Settings: which address the app talks to, and whether it's reachable.
// Voice, Memory and notifications arrive with later milestones.
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var checking = false

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
}
