// Writing or changing a playbook in the app (Dylan, 2026-11-19: "there
// also isn't another button for me to add another routine"). The page's
// editor in a native form: name and on/off, what it's for, when it runs,
// up to 20 steps, the done checklist, and "More for Jarvis" folded away.
// What's missing is said in plain words before Save (JarvisKit
// PlaybookDraft.problem); every network wait is labelled and blocking.
import SwiftUI
import JarvisKit

struct PlaybookEditorView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State var draft: PlaybookDraft
    let options: PlaybookOptions
    /// Saved or deleted: the list reloads.
    let onDone: () -> Void

    @State private var busy: String?
    @State private var refusal: String?
    @State private var confirmingDelete = false
    @State private var moreOpen = false

    private var isNew: Bool { draft.id == nil }

    var body: some View {
        NavigationStack {
            ZStack {
                form
                if let busy {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    VStack(spacing: 14) {
                        ProgressView().controlSize(.large).tint(Theme.frost)
                        Text(busy).font(.headline).foregroundStyle(Theme.frost)
                    }
                    .padding(28)
                    .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.ultraThinMaterial))
                }
            }
            .navigationTitle(isNew ? "New playbook" : draft.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(draft.problem != nil || busy != nil)
                }
            }
            .alert("Jarvis didn't take that", isPresented: Binding(get: { refusal != nil }, set: { if !$0 { refusal = nil } })) {
                Button("Close", role: .cancel) {}
            } message: {
                Text(refusal ?? "")
            }
            .confirmationDialog("Delete \(draft.name)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { Task { await delete() } }
                Button("Close", role: .cancel) {}
            } message: {
                Text("It's gone for good, here and on the PC.")
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: The form

    private var form: some View {
        Form {
            if isNew {
                Section {
                    Button {
                        dismiss()
                        app.startChat(with: PlaybookWording.buildWithJarvis)
                    } label: {
                        Label("Build it with Jarvis", systemImage: "bubble.left.and.text.bubble.right")
                    }
                    .frame(minHeight: 44)
                } footer: {
                    Text("Opens Chat with a message ready to send: Jarvis asks you about it one question at a time.")
                }
            }
            Section {
                TextField("Name", text: $draft.name)
                Toggle("On", isOn: $draft.enabled).tint(Theme.glacier)
                TextField("What it's for", text: $draft.purpose, axis: .vertical)
            }
            triggerSection
            stepsSection
            listSection("Done when", hint: "What must be true for a run to count", items: $draft.done)
            Section {
                DisclosureGroup("More for Jarvis", isExpanded: $moreOpen) {
                    TextField("When to use it", text: $draft.whenToUse, axis: .vertical)
                    pairRows("Inputs", first: "What", second: "Where it lives", rows: $draft.inputs)
                    pairRows("Decisions", first: "If", second: "Then", rows: $draft.decisions)
                    stringRows("Edge cases", rows: $draft.edgeCases)
                    TextField("The standard it has to hit", text: $draft.standard, axis: .vertical)
                    TextField("What a bad version looks like", text: $draft.badVersion, axis: .vertical)
                }
            }
            if let problem = draft.problem {
                Section {
                    Label(problem, systemImage: "exclamationmark.circle").foregroundStyle(Theme.ember)
                }
            }
            if !isNew {
                Section {
                    Button("Delete playbook", role: .destructive) { confirmingDelete = true }
                        .frame(minHeight: 44)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.sky.ignoresSafeArea())
    }

    /// When it runs: the kind, then its time and days, or how long away.
    private var triggerSection: some View {
        Section("When it runs") {
            Picker("Runs", selection: Binding(get: { draft.trigger.type }, set: { draft.trigger = DraftTrigger.blank($0) })) {
                ForEach(PlaybookWording.triggers, id: \.type) { Text($0.label).tag($0.type) }
            }
            if draft.trigger.type == "time" {
                DatePicker("Time", selection: timeBinding, displayedComponents: .hourAndMinute)
                HStack(spacing: 6) {
                    ForEach(PlaybookWording.days, id: \.id) { day in
                        let on = draft.trigger.days.contains(day.id)
                        Button(day.label) {
                            if on { draft.trigger.days.removeAll { $0 == day.id } } else { draft.trigger.days.append(day.id) }
                        }
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(RoundedRectangle(cornerRadius: 10).fill(on ? Theme.glacier.opacity(0.3) : Color.white.opacity(0.06)))
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                Text(draft.trigger.days.isEmpty ? "Every day" : Playbooks.daysLabel(draft.trigger.days).capitalized)
                    .font(.caption).foregroundStyle(Theme.frostDim)
            }
            if draft.trigger.type == "arrive" {
                Stepper("After \(draft.trigger.minAway) min away", value: $draft.trigger.minAway, in: 0...1440, step: 5)
            }
        }
    }

    /// "08:30" as a date for the time picker, and back.
    private var timeBinding: Binding<Date> {
        Binding(get: {
            let bits = draft.trigger.at.split(separator: ":").compactMap { Int($0) }
            return Calendar.current.date(bySettingHour: bits.first ?? 8, minute: bits.count > 1 ? bits[1] : 0, second: 0, of: Date()) ?? Date()
        }, set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            draft.trigger.at = String(format: "%02d:%02d", parts.hour ?? 8, parts.minute ?? 0)
        })
    }

    /// The steps in order, each with its own fields; add, delete, reorder.
    private var stepsSection: some View {
        Section {
            ForEach(Array(draft.steps.enumerated()), id: \.offset) { index, _ in
                StepEditor(step: $draft.steps[index], number: index + 1, options: options)
            }
            .onDelete { draft.steps.remove(atOffsets: $0) }
            .onMove { draft.steps.move(fromOffsets: $0, toOffset: $1) }
            if draft.steps.count < PlaybookDraft.maxSteps {
                Menu {
                    ForEach(PlaybookWording.steps, id: \.type) { choice in
                        Button(choice.label) { draft.steps.append(DraftStep.blank(choice.type, options: options)) }
                    }
                } label: {
                    Label("Add a step", systemImage: "plus.circle")
                }
                .frame(minHeight: 44)
            }
        } header: {
            HStack {
                Text("Steps")
                Spacer()
                if draft.steps.count > 1 { EditButton().font(.caption) }
            }
        }
    }

    /// A list of lines: one field each, add and delete.
    private func listSection(_ title: String, hint: String, items: Binding<[String]>) -> some View {
        Section {
            stringRows(nil, rows: items)
        } header: {
            Text(title)
        } footer: {
            Text(hint)
        }
    }

    @ViewBuilder
    private func stringRows(_ title: String?, rows: Binding<[String]>) -> some View {
        if let title { Text(title).font(.subheadline.weight(.semibold)) }
        ForEach(Array(rows.wrappedValue.enumerated()), id: \.offset) { index, _ in
            HStack {
                TextField("Line \(index + 1)", text: rows[index], axis: .vertical)
                Button { rows.wrappedValue.remove(at: index) } label: {
                    Image(systemName: "minus.circle.fill").foregroundStyle(Theme.rose)
                }
                .buttonStyle(.plain)
                .frame(width: 44, height: 44)
                .accessibilityLabel("Remove line \(index + 1)")
            }
        }
        if rows.wrappedValue.count < 10 {
            Button { rows.wrappedValue.append("") } label: { Label("Add a line", systemImage: "plus") }
                .frame(minHeight: 44)
        }
    }

    @ViewBuilder
    private func pairRows(_ title: String, first: String, second: String, rows: Binding<[PlaybookDraft.Pair]>) -> some View {
        Text(title).font(.subheadline.weight(.semibold))
        ForEach(Array(rows.wrappedValue.enumerated()), id: \.offset) { index, _ in
            HStack {
                VStack {
                    TextField(first, text: rows[index].first)
                    TextField(second, text: rows[index].second)
                }
                Button { rows.wrappedValue.remove(at: index) } label: {
                    Image(systemName: "minus.circle.fill").foregroundStyle(Theme.rose)
                }
                .buttonStyle(.plain)
                .frame(width: 44, height: 44)
                .accessibilityLabel("Remove \(title.lowercased()) \(index + 1)")
            }
        }
        if rows.wrappedValue.count < 10 {
            Button { rows.wrappedValue.append(.init("", "")) } label: { Label("Add", systemImage: "plus") }
                .frame(minHeight: 44)
        }
    }

    // MARK: Saving

    /// Saves it whole, as the page does; Jarvis's refusal is shown as said.
    private func save() async {
        busy = "Saving \(draft.name)…"
        defer { busy = nil }
        do {
            let result = try await app.client.savePlaybook(draft)
            if result.ok {
                onDone()
                dismiss()
            } else {
                refusal = PlaybookTrouble.saveWords(result.detail, hasSteps: !draft.steps.isEmpty)
            }
        } catch {
            refusal = error.localizedDescription
        }
    }

    /// Deletes it, after "Delete … ?".
    private func delete() async {
        guard let id = draft.id else { return }
        busy = "Deleting \(draft.name)…"
        defer { busy = nil }
        do {
            let result = try await app.client.deletePlaybook(id: id)
            if result.ok {
                onDone()
                dismiss()
            } else {
                refusal = result.detail.isEmpty ? "Jarvis didn't delete it." : result.detail
            }
        } catch {
            refusal = error.localizedDescription
        }
    }
}

/// One step's fields: its kind and number, then what that kind needs.
private struct StepEditor: View {
    @Binding var step: DraftStep
    let number: Int
    let options: PlaybookOptions

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(number). \(PlaybookWording.steps.first { $0.type == step.type }?.label ?? step.type)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.frostDim)
            fields
            if let problem = step.problem {
                Text(problem.prefix(1).uppercased() + problem.dropFirst()).font(.caption).foregroundStyle(Theme.ember)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var fields: some View {
        switch step {
        case .device(let entity, let command, let value):
            let device = options.devices.first { $0.entity == entity }
            Picker("Device", selection: Binding(get: { entity }, set: { new in
                let commands = options.devices.first { $0.entity == new }?.commands ?? []
                step = .device(entity: new, command: commands.contains(command) ? command : (commands.first ?? command), value: value)
            })) {
                if device == nil { Text(entity.isEmpty ? "Pick a device" : entity).tag(entity) }
                ForEach(options.devices) { Text($0.name).tag($0.entity) }
            }
            Picker("Do", selection: Binding(get: { command }, set: { step = .device(entity: entity, command: $0, value: value) })) {
                let commands = device?.commands ?? [command]
                ForEach(commands.contains(command) ? commands : [command] + commands, id: \.self) { Text(PlaybookWording.commandLabel($0)).tag($0) }
            }
            if PlaybookWording.commandTakesValue(command) {
                TextField(PlaybookWording.commandTakesWords(command) ? "Value" : "Number", text: Binding(get: { value }, set: { step = .device(entity: entity, command: command, value: $0) }))
                    .keyboardType(PlaybookWording.commandTakesWords(command) ? .default : .decimalPad)
            }
        case .scene(let entity):
            Picker("Scene", selection: Binding(get: { entity }, set: { step = .scene(entity: $0) })) {
                if !options.scenes.contains(where: { $0.entity == entity }) { Text(entity.isEmpty ? "Pick a scene" : entity).tag(entity) }
                ForEach(options.scenes) { Text($0.name).tag($0.entity) }
            }
        case .app(let entity, let app):
            let screen = options.apps.first { $0.entity == entity }
            Picker("TV", selection: Binding(get: { entity }, set: { new in
                let apps = options.apps.first { $0.entity == new }?.apps ?? []
                step = .app(entity: new, app: apps.contains(app) ? app : (apps.first ?? ""))
            })) {
                if screen == nil { Text(entity.isEmpty ? "Pick a TV" : entity).tag(entity) }
                ForEach(options.apps) { Text($0.name).tag($0.entity) }
            }
            Picker("App", selection: Binding(get: { app }, set: { step = .app(entity: entity, app: $0) })) {
                let apps = screen?.apps ?? []
                if !apps.contains(app) { Text(app.isEmpty ? "Pick an app" : app).tag(app) }
                ForEach(apps, id: \.self) { Text($0).tag($0) }
            }
        case .notify(let text):
            TextField("What it should say", text: Binding(get: { text }, set: { step = .notify(text: $0) }), axis: .vertical)
        case .think(let text, let model):
            TextField("What Jarvis should do", text: Binding(get: { text }, set: { step = .think(text: $0, model: model) }), axis: .vertical)
            Picker("Who", selection: Binding(get: { model }, set: { step = .think(text: text, model: $0) })) {
                ForEach(PlaybookWording.thinkers, id: \.model) { Text($0.label).tag($0.model) }
            }
        case .email(let to, let subject, let body, let confirm):
            TextField("To (commas between addresses)", text: Binding(get: { to }, set: { step = .email(to: $0, subject: subject, body: body, confirm: confirm) }))
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
            TextField("Subject", text: Binding(get: { subject }, set: { step = .email(to: to, subject: $0, body: body, confirm: confirm) }))
            TextField("Message", text: Binding(get: { body }, set: { step = .email(to: to, subject: subject, body: $0, confirm: confirm) }), axis: .vertical)
            Toggle("Ask me before sending", isOn: Binding(get: { confirm }, set: { step = .email(to: to, subject: subject, body: body, confirm: $0) }))
                .tint(Theme.glacier)
        case .wait(let seconds):
            Stepper(seconds % 60 == 0 ? "Wait \(seconds / 60) min" : "Wait \(seconds) s", value: Binding(get: { seconds }, set: { step = .wait(seconds: $0) }), in: 5...600, step: 5)
        }
    }
}
