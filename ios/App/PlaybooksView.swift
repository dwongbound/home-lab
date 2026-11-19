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
    /// What steps can use (devices, scenes, TVs), for the editor.
    @Published private(set) var options = PlaybookOptions()
    /// How the last Run now went, for the result panel.
    @Published var runResult: RunOutcome?

    /// A finished Run now, as the result panel shows it.
    struct RunOutcome: Identifiable {
        let id = UUID()
        let name: String
        let ok: Bool
        /// The plain words: the friendly version when we know the failure.
        let words: String
        /// "Not done: …" lines from the checklist.
        let notDone: [String]
        /// Jarvis's own text, under Details.
        let raw: String
    }
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
            if let book = try await client.playbookBook() {
                state = .ready(book.playbooks)
                options = book.options
            } else {
                state = .unreachable
            }
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
                // Still going after 50 s: not a failure.
                runResult = RunOutcome(name: playbook.name, ok: true, words: "Still running. Its result will show on the playbook when it's done.", notDone: [], raw: "")
            } else {
                let friendly = PlaybookTrouble.runWords(result.detail)
                let words = friendly ?? (result.detail.isEmpty ? (result.ok ? "Done." : "It didn't finish.") : result.detail)
                runResult = RunOutcome(name: playbook.name, ok: result.ok, words: words, notDone: Playbooks.notDone(result.checks), raw: friendly == nil ? "" : result.detail)
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
    /// The playbook open in the editor (a new one has no id).
    @State private var editing: EditTarget?

    /// A sheet item for the editor.
    struct EditTarget: Identifiable {
        let id = UUID()
        let draft: PlaybookDraft
    }

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
                ToolbarItem(placement: .primaryAction) {
                    Button { editing = EditTarget(draft: PlaybookDraft()) } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New playbook")
                }
            }
            .sheet(item: $editing) { target in
                PlaybookEditorView(draft: target.draft, options: model.options) {
                    Task { await model.load(client: app.client) }
                }
                .environmentObject(app)
            }
            .sheet(item: $model.runResult) { outcome in
                RunResultView(outcome: outcome)
            }
            .alert("Playbook", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
                Button("Close", role: .cancel) {}
            } message: {
                Text(model.message ?? "")
            }
        }
        .preferredColorScheme(.dark)
        .fontDesign(.rounded)
        .task {
            await model.load(client: app.client)
            #if DEBUG
            // `-editFirstPlaybook` / `-newPlaybook` open the editor (simulator checks).
            let args = ProcessInfo.processInfo.arguments
            try? await Task.sleep(for: .seconds(1.5))
            if args.contains("-editFirstPlaybook"), let first = model.playbooks.first { editing = EditTarget(draft: first.draft) }
            if args.contains("-newPlaybook") { editing = EditTarget(draft: PlaybookDraft()) }
            #endif
        }
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
            Button {
                editing = EditTarget(draft: PlaybookDraft())
            } label: {
                Label("New playbook", systemImage: "plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.bordered)
            .tint(Theme.glacier)
            .padding(.top, 4)
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
                // Tap Edit to change any part of it.
                Button("Edit") { editing = EditTarget(draft: playbook.draft) }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
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

/// How a Run now went, in a fixed-size panel with Close: plain words first,
/// the "Not done" lines, and Jarvis's own text under Details.
private struct RunResultView: View {
    let outcome: PlaybooksModel.RunOutcome
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Label(outcome.ok ? "It ran" : "It didn't finish", systemImage: outcome.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundStyle(outcome.ok ? Theme.moss : Theme.ember)
                    Text(outcome.words).foregroundStyle(Theme.frost)
                    ForEach(outcome.notDone, id: \.self) { line in
                        Text(line).font(.subheadline).foregroundStyle(Theme.ember)
                    }
                    if !outcome.raw.isEmpty {
                        DisclosureGroup("Details") {
                            Text(outcome.raw).font(.caption.monospaced()).foregroundStyle(Theme.frostDim).textSelection(.enabled)
                        }
                        .tint(Theme.frostDim)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.sky.ignoresSafeArea())
            .navigationTitle(outcome.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
        .presentationDetents([.medium])
        .preferredColorScheme(.dark)
    }
}
