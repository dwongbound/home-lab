// Jarvis's playbooks, opened from the Playbooks tile on Home (Dylan,
// 2026-11-19). One row each: its name, when it runs in plain words, an on
// or off switch, how its last run went ("Not done: …" for checks that
// didn't hold) and Run now. No editor here: editing is on the home page.
// Wording and data in JarvisKit's Playbooks.
import SwiftUI
import JarvisKit

@MainActor
final class PlaybooksModel: ObservableObject {
    enum State: Equatable {
        case loading
        case ready([Playbook])
        case unreachable
        case failed(String)
    }

    @Published private(set) var state: State = .loading
    /// What a switch or a run is waiting on ("Running Bedtime…"), shown as a
    /// labelled, blocking wait.
    @Published private(set) var busy: String?
    /// The last run's answer, or a refusal, for the screen.
    @Published var message: String?

    /// The playbooks shown right now.
    var playbooks: [Playbook] {
        if case .ready(let list) = state { return list }
        return []
    }

    /// Fetches the playbooks.
    func load(client: JarvisClient) async {
        do {
            if let list = try await client.playbooks() { state = .ready(list) } else { state = .unreachable }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Switches one on or off (saves it whole with only that changed).
    func set(_ playbook: Playbook, enabled: Bool, client: JarvisClient) async {
        busy = enabled ? "Turning \(playbook.name) on…" : "Turning \(playbook.name) off…"
        defer { busy = nil }
        do {
            let result = try await client.setPlaybook(playbook, enabled: enabled)
            if !result.ok { message = result.detail.isEmpty ? "Jarvis didn't save that." : result.detail }
        } catch {
            message = error.localizedDescription
        }
        await load(client: client)
    }

    /// Runs one now and says how it went.
    func run(_ playbook: Playbook, client: JarvisClient) async {
        busy = "Running \(playbook.name)…"
        defer { busy = nil }
        do {
            let result = try await client.runPlaybook(id: playbook.id)
            if result.detail == "running" {
                message = "\(playbook.name) is still running. Its result will show here when it's done."
            } else {
                let lines = [result.detail] + Playbooks.notDone(result.checks)
                message = lines.filter { !$0.isEmpty }.joined(separator: "\n")
                if message?.isEmpty ?? true { message = result.ok ? "\(playbook.name) ran." : "\(playbook.name) didn't finish." }
            }
        } catch {
            message = error.localizedDescription
        }
        await load(client: client)
    }
}

struct PlaybooksView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = PlaybooksModel()

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.sky.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        content
                    }
                    .padding(16)
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                }
                .refreshable { await model.load(client: app.client) }
                if let busy = model.busy {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    VStack(spacing: 14) {
                        ProgressView().controlSize(.large).tint(Theme.frost)
                        Text(busy).font(.headline).foregroundStyle(Theme.frost)
                    }
                    .padding(28)
                    .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.ultraThinMaterial))
                }
            }
            .navigationTitle("Playbooks")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .alert("Playbook", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
                Button("Close", role: .cancel) {}
            } message: {
                Text(model.message ?? "")
            }
        }
        .preferredColorScheme(.dark)
        .fontDesign(.rounded)
        .task { await model.load(client: app.client) }
    }

    /// The list, or a wait, or a problem.
    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            HStack(spacing: 10) {
                ProgressView().tint(Theme.frost)
                Text("Loading playbooks…").foregroundStyle(Theme.frostDim)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 60)
        case .unreachable:
            note("Jarvis can’t be reached, so his playbooks can’t be shown right now.")
        case .failed(let words):
            note(words)
        case .ready(let list):
            if list.isEmpty { note("No playbooks yet. Make one on the home page, or ask Jarvis.") }
            ForEach(list) { playbook in
                row(playbook)
            }
            Text("To change what a playbook does, edit it on the home page.")
                .font(.caption)
                .foregroundStyle(Theme.frostDim)
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
        }
    }

    /// A plain message.
    private func note(_ words: String) -> some View {
        Text(words)
            .multilineTextAlignment(.center)
            .foregroundStyle(Theme.frost)
            .frame(maxWidth: .infinity)
            .padding(24)
            .glassPanel()
    }

    /// One playbook: name and switch, when it runs, its last run, Run now.
    private func row(_ playbook: Playbook) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(get: { playbook.enabled }, set: { on in Task { await model.set(playbook, enabled: on, client: app.client) } })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(playbook.name).font(.headline).foregroundStyle(Theme.frost)
                    Text(Playbooks.triggerLine(playbook.trigger)).font(.subheadline).foregroundStyle(Theme.frostDim)
                }
            }
            .tint(Theme.glacier)
            .frame(minHeight: 44)
            if !playbook.purpose.isEmpty {
                Text(playbook.purpose).font(.caption).foregroundStyle(Theme.frostDim)
            }
            if let last = playbook.lastRun {
                VStack(alignment: .leading, spacing: 2) {
                    Label(last.ok ? "Last run went fine" : "Last run had problems", systemImage: last.ok ? "checkmark.circle" : "exclamationmark.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(last.ok ? Theme.moss : Theme.ember)
                    if !last.detail.isEmpty {
                        Text(last.detail).font(.caption).foregroundStyle(Theme.frostDim)
                    }
                    ForEach(Playbooks.notDone(last.checks), id: \.self) { line in
                        Text(line).font(.caption).foregroundStyle(Theme.ember)
                    }
                }
            }
            HStack {
                Spacer()
                Button("Run now") { Task { await model.run(playbook, client: app.client) } }
                    .buttonStyle(.bordered)
                    .tint(Theme.glacier)
                    .frame(minHeight: 44)
            }
        }
        .padding(14)
        .glassPanel()
    }
}
