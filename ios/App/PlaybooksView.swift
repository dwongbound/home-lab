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
    #if DEBUG
    static let demoBook = #"""
    {
     "book": {
      "playbooks": [
       {
        "id": "arrive-home",
        "name": "Arrive home",
        "enabled": true,
        "purpose": "",
        "whenToUse": "",
        "trigger": {
         "type": "arrive",
         "zone": "home",
         "minAway": 15
        },
        "inputs": [],
        "steps": [
         {
          "type": "app",
          "entity": "media_player.tv",
          "app": "Jarvis"
         }
        ],
        "decisions": [],
        "done": [],
        "edgeCases": [],
        "standard": "",
        "badVersion": "",
        "madeBy": "dylan"
       },
       {
        "id": "nightly",
        "name": "Nightly self-improvement",
        "enabled": true,
        "purpose": "",
        "whenToUse": "Every night after the day's talking is done.",
        "trigger": {
         "type": "time",
         "at": "03:30",
         "days": []
        },
        "inputs": [],
        "steps": [
         {
          "type": "job",
          "job": "nightly"
         }
        ],
        "decisions": [],
        "done": [
         "The day's flagged mistakes were reviewed",
         "The regression eval cases were run and scored",
         "Memory was tidied (new facts filed, duplicates merged)",
         "At most 3 improvement ideas were proposed, each waiting for his OK"
        ],
        "edgeCases": [
         "Self-change proposals still need his OK before anything changes",
         "Never reads data/memory.md and never pushes anything"
        ],
        "standard": "",
        "badVersion": "",
        "madeBy": "dylan"
       },
       {
        "id": "every-kind",
        "name": "Every kind",
        "enabled": true,
        "madeBy": "dylan",
        "purpose": "",
        "trigger": {
         "type": "manual"
        },
        "steps": [
         {
          "type": "device",
          "entity": "climate.bedroom",
          "command": "set_temperature",
          "value": 68
         },
         {
          "type": "scene",
          "entity": "scene.movie"
         },
         {
          "type": "app",
          "entity": "media_player.tv",
          "app": "Netflix"
         },
         {
          "type": "notify",
          "text": "Dinner is ready"
         },
         {
          "type": "think",
          "text": "Pick a playlist",
          "model": "auto",
          "confirm": false
         },
         {
          "type": "email",
          "to": "someone@example.com",
          "subject": "Hi",
          "body": "Hello",
          "confirm": true
         },
         {
          "type": "wait",
          "seconds": 90
         },
         {
          "type": "job",
          "job": "nightly"
         }
        ]
       }
      ],
      "options": {
       "devices": [
        {
         "entity": "light.desk",
         "name": "Desk lamp",
         "kind": "light",
         "commands": [
          "turn_on",
          "turn_off"
         ]
        },
        {
         "entity": "climate.bedroom",
         "name": "Thermostat",
         "kind": "climate",
         "commands": [
          "set_temperature",
          "set_hvac_mode",
          "turn_off"
         ]
        },
        {
         "entity": "media_player.tv",
         "name": "Living room TV",
         "kind": "media_player",
         "commands": [
          "turn_on",
          "turn_off",
          "volume_set",
          "select_source"
         ]
        }
       ],
       "scenes": [
        {
         "entity": "scene.movie",
         "name": "Movie"
        }
       ],
       "apps": [
        {
         "entity": "media_player.tv",
         "name": "Living room TV",
         "apps": [
          "Jarvis",
          "Netflix"
         ]
        }
       ],
       "zones": [
        "home"
       ],
       "jobs": [
        {
         "id": "nightly",
         "name": "The nightly self-improvement pass (memory, flagged mistakes, evals, tidy-up, ideas)"
        }
       ],
       "thinkers": [
        {
         "id": "worker",
         "name": "Ornith (simple, stays on the PC)"
        },
        {
         "id": "claude",
         "name": "Claude (judgment and writing)"
        }
       ],
       "stepTypes": [
        {
         "type": "device",
         "label": "Control a device",
         "short": "Device",
         "runs": "code",
         "summary": "{entity.name}: {command} {value}",
         "fields": [
          {
           "key": "entity",
           "label": "Device",
           "kind": "choice",
           "required": true,
           "choicesFrom": "devices"
          },
          {
           "key": "command",
           "label": "Do",
           "kind": "choice",
           "required": true,
           "choicesFrom": "devices",
           "dependsOn": "entity",
           "choicesKey": "commands"
          },
          {
           "key": "value",
           "label": "Value",
           "kind": "by_command",
           "required": false,
           "dependsOn": "command",
           "byCommand": {
            "turn_on": {
             "label": "Brightness %",
             "kind": "number",
             "required": false,
             "min": 1,
             "max": 100,
             "onlyDomains": [
              "light"
             ]
            },
            "volume_set": {
             "label": "Volume (0 to 1)",
             "kind": "number",
             "required": true,
             "min": 0,
             "max": 1,
             "step": 0.05
            },
            "select_source": {
             "label": "App or input",
             "kind": "choice",
             "required": true,
             "choicesFrom": "apps",
             "dependsOn": "entity",
             "choicesKey": "apps"
            },
            "set_temperature": {
             "label": "Temperature (°F)",
             "kind": "number",
             "required": true,
             "min": 45,
             "max": 90
            },
            "set_hvac_mode": {
             "label": "Mode",
             "kind": "choice",
             "required": true,
             "choices": [
              "off",
              "heat",
              "cool",
              "heat_cool",
              "auto"
             ]
            }
           }
          }
         ]
        },
        {
         "type": "scene",
         "label": "Run a scene",
         "short": "Scene",
         "runs": "code",
         "summary": "Scene: {entity.name}",
         "fields": [
          {
           "key": "entity",
           "label": "Scene",
           "kind": "choice",
           "required": true,
           "choicesFrom": "scenes"
          }
         ]
        },
        {
         "type": "app",
         "label": "Open an app on a TV",
         "short": "TV app",
         "runs": "code",
         "summary": "Open {app} on {entity.name}",
         "fields": [
          {
           "key": "entity",
           "label": "TV",
           "kind": "choice",
           "required": true,
           "choicesFrom": "apps"
          },
          {
           "key": "app",
           "label": "App",
           "kind": "choice",
           "required": true,
           "max": 80,
           "choicesFrom": "apps",
           "dependsOn": "entity",
           "choicesKey": "apps"
          }
         ]
        },
        {
         "type": "notify",
         "label": "Send me a notification",
         "short": "Notify me",
         "runs": "code",
         "summary": "Notify me: {text}",
         "fields": [
          {
           "key": "text",
           "label": "Message",
           "kind": "longtext",
           "required": true,
           "max": 2000,
           "placeholder": "What to tell me"
          }
         ]
        },
        {
         "type": "think",
         "label": "Have Jarvis work something out",
         "short": "Ask Jarvis",
         "runs": "thinking",
         "summary": "Jarvis: {text}",
         "fields": [
          {
           "key": "text",
           "label": "What Jarvis should do",
           "kind": "longtext",
           "required": true,
           "max": 2000,
           "placeholder": "Check tomorrow's weather and tell me if I need a jacket"
          },
          {
           "key": "model",
           "label": "Who does it",
           "kind": "choice",
           "required": false,
           "default": "claude",
           "choicesFrom": "thinkers"
          },
          {
           "key": "confirm",
           "label": "Ask me first",
           "kind": "bool",
           "required": false,
           "default": false
          }
         ]
        },
        {
         "type": "email",
         "label": "Send an email",
         "short": "Email",
         "runs": "code",
         "summary": "Email {to}: {subject}",
         "fields": [
          {
           "key": "to",
           "label": "To",
           "kind": "emails",
           "required": true,
           "maxItems": 10
          },
          {
           "key": "subject",
           "label": "Subject",
           "kind": "text",
           "required": true,
           "max": 200
          },
          {
           "key": "body",
           "label": "Message",
           "kind": "longtext",
           "required": true,
           "max": 5000
          },
          {
           "key": "confirm",
           "label": "Ask me first",
           "kind": "bool",
           "required": false,
           "default": false
          }
         ]
        },
        {
         "type": "wait",
         "label": "Wait",
         "short": "Wait",
         "runs": "code",
         "summary": "Wait {seconds} s",
         "fields": [
          {
           "key": "seconds",
           "label": "Seconds",
           "kind": "number",
           "required": true,
           "min": 1,
           "max": 600,
           "default": 60
          }
         ]
        },
        {
         "type": "job",
         "label": "Run one of Jarvis's jobs",
         "short": "Jarvis job",
         "runs": "code",
         "summary": "Run: {job.name}",
         "fields": [
          {
           "key": "job",
           "label": "Job",
           "kind": "choice",
           "required": true,
           "choicesFrom": "jobs"
          }
         ]
        }
       ]
      }
     }
    }
    """#
    #endif

    func load(client: JarvisClient) async {
        #if DEBUG
        // `-demoPlaybooks`: a fixture book, no Jarvis (layout checks).
        if ProcessInfo.processInfo.arguments.contains("-demoPlaybooks"),
           let list = Playbooks.list(from: Data(Self.demoBook.utf8)), let book = Playbooks.book(from: Data(Self.demoBook.utf8)) {
            state = .ready(list)
            options = book.options
            return
        }
        #endif
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
        Haptics.play(.run)
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
                Haptics.play(result.ok ? .runOK : .runFailed)
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
                SheetClose { dismiss() }
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
            if let at = args.firstIndex(of: "-editPlaybook"), at + 1 < args.count, let one = model.playbooks.first(where: { $0.id == args[at + 1] }) {
                editing = EditTarget(draft: one.draft)
            }
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
                        // Plain words first; Jarvis's own text folded under Details.
                        if let friendly = PlaybookTrouble.runWords(last.detail) {
                            Text(friendly).font(.caption).foregroundStyle(Theme.frost)
                            DisclosureGroup("Details") {
                                Text(last.detail).font(.caption2).foregroundStyle(Theme.frostDim).textSelection(.enabled)
                            }
                            .font(.caption)
                            .tint(Theme.frostDim)
                        } else {
                            Text(last.detail).font(.caption).foregroundStyle(Theme.frostDim).lineLimit(3)
                        }
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
                SheetClose { dismiss() }
            }
        }
        .presentationDetents([.medium])
        .preferredColorScheme(.dark)
    }
}
