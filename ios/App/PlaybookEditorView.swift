// Writing or changing a playbook in the app. Reworked (Dylan, 2026-11-19:
// "can we make this edit / create playbook page more smooth and intuitive?
// way too hard to understand right now") to follow the page's editor
// (src/components/PlaybookEditor.tsx): a new playbook starts with
// "Describe it, and Jarvis fills in the rest" (op "draft", nothing saved),
// then three plain questions, 1 when does it run, 2 what happens, 3 how
// Jarvis knows it worked, with "More for Jarvis" folded at the bottom.
// Steps are added from a row of buttons and fold to one sentence each.
// What's missing is said in plain words (PlaybookDraft.problem); every
// network wait is labelled and blocking.
import SwiftUI
import JarvisKit

struct PlaybookEditorView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State var draft: PlaybookDraft
    let options: PlaybookOptions
    /// Saved or deleted: the list reloads.
    let onDone: () -> Void

    init(draft: PlaybookDraft, options: PlaybookOptions, onDone: @escaping () -> Void) {
        _draft = State(initialValue: draft)
        _steps = State(initialValue: draft.steps.map { EditableStep(step: $0) })
        self.options = options
        self.onDone = onDone
    }

    /// The steps with a lasting id each, so rows animate and keep their
    /// open or folded state while being moved.
    @State private var steps: [EditableStep]
    /// The one step row that's open for editing.
    @State private var openStep: UUID?
    @State private var reordering = false

    @State private var busy: String?
    @State private var refusal: String?
    @State private var confirmingDelete = false
    @State private var moreOpen = false
    /// Simulator checks only: a section to scroll to.
    @State private var scrollTarget: String?

    // "Describe it".
    @State private var wish = ""
    @State private var describeOpen = false
    @State private var draftNote: String?
    @State private var draftFailed = false
    @State private var assumed: [String] = []
    @FocusState private var wishFocused: Bool

    private var isNew: Bool { draft.id == nil }

    /// The playbook as it stands, with the steps in their current order.
    private var current: PlaybookDraft {
        var out = draft
        out.steps = steps.map(\.step)
        return out
    }

    /// Animates a change unless Reduce Motion is on.
    private func animate(_ change: () -> Void) {
        if reduceMotion { change() } else { withAnimation(.snappy(duration: 0.28), change) }
    }

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
                    .accessibilityElement(children: .combine)
                }
            }
            .navigationTitle(isNew ? "New playbook" : "Edit playbook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.disabled(busy != nil)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .fontWeight(.semibold)
                        .disabled(current.problem != nil || busy != nil)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { hideKeyboard() }
                }
            }
            .interactiveDismissDisabled(busy != nil)
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
            .task { await debugStart() }
        }
        .preferredColorScheme(.dark)
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    // MARK: The form

    private var form: some View {
        ScrollViewReader { proxy in
        Form {
            if isNew { describeSection }
            Section {
                TextField("Name, like Bedtime", text: $draft.name)
                    .font(.headline)
                    .frame(minHeight: 44)
                Toggle("On", isOn: $draft.enabled).tint(Theme.glacier).frame(minHeight: 44)
                TextField("What it's for (optional)", text: $draft.purpose, axis: .vertical)
                    .frame(minHeight: 44)
            }
            if !isNew {
                Section {
                    DisclosureGroup("Rewrite it from a description", isExpanded: $describeOpen) {
                        describeFields
                    }
                    .frame(minHeight: 44)
                }
            }
            triggerSection
            stepsSection.id("steps")
            checksSection.id("checks")
            Section {
                DisclosureGroup(isExpanded: $moreOpen) {
                    TextField("When he should use it without being told", text: $draft.whenToUse, axis: .vertical)
                    pairRows("What it needs, and where it lives", first: "What", second: "Where it lives", rows: $draft.inputs)
                    pairRows("Rules for decisions", first: "If", second: "Then", rows: $draft.decisions)
                    stringRows("What's gone wrong before", rows: $draft.edgeCases)
                    TextField("The standard it has to hit", text: $draft.standard, axis: .vertical)
                    TextField("What a bad version looks like", text: $draft.badVersion, axis: .vertical)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("More for Jarvis")
                        Text("Optional, for jobs that need judgment").font(.caption).foregroundStyle(Theme.frostDim)
                    }
                    .frame(minHeight: 44)
                }
            }
            if let problem = current.problem {
                Section {
                    Label(problem, systemImage: "exclamationmark.circle").foregroundStyle(Theme.ember)
                } footer: {
                    Text("Save works once this is sorted.")
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
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.sky.ignoresSafeArea())
        .environment(\.editMode, .constant(reordering ? .active : .inactive))
        .onChange(of: scrollTarget) { _, target in
            if let target { proxy.scrollTo(target, anchor: .top) }
        }
        }
    }

    // MARK: Describe it

    /// A new playbook's first box: a sentence or two, and Jarvis fills the form in.
    private var describeSection: some View {
        Section {
            describeFields
        } header: {
            Text("Describe it, and Jarvis fills in the rest")
        }
    }

    @ViewBuilder
    private var describeFields: some View {
        TextField("At 11 on weeknights, turn off the lights and tell me tomorrow's first meeting", text: $wish, axis: .vertical)
            .lineLimit(3...6)
            .focused($wishFocused)
            .onChange(of: wish) { _, new in
                if new.count > PlaybookDraftAnswer.maxText { wish = String(new.prefix(PlaybookDraftAnswer.maxText)) }
            }
        Button {
            Task { await writeDraft() }
        } label: {
            Label("Write it for me", systemImage: "sparkles")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.glacier)
        .disabled(busy != nil)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .listRowSeparator(.hidden)
        if let draftNote {
            Label(draftNote, systemImage: draftFailed ? "exclamationmark.circle" : "checkmark.circle")
                .font(.subheadline)
                .foregroundStyle(draftFailed ? Theme.ember : Theme.frost)
        } else if isNew {
            Text("Or fill it in yourself below.").font(.subheadline).foregroundStyle(Theme.frostDim)
        }
        if !assumed.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("What Jarvis assumed").font(.caption.weight(.semibold)).foregroundStyle(Theme.frostDim)
                ForEach(assumed, id: \.self) { line in
                    Label(line, systemImage: "lightbulb").font(.subheadline)
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
        }
    }

    /// Has Jarvis fill the form in from the description; nothing is saved.
    private func writeDraft() async {
        let words = wish.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else {
            draftFailed = true
            draftNote = "Say what it should do first."
            return
        }
        hideKeyboard()
        busy = "Jarvis is writing it…"
        defer { busy = nil }
        do {
            switch try await app.client.draftPlaybook(text: words) {
            case .drafted(var written, let guesses):
                // Rewriting a saved one keeps it the same playbook.
                written.id = draft.id
                animate {
                    draft = written
                    steps = written.steps.map { EditableStep(step: $0) }
                    openStep = nil
                    assumed = guesses
                    draftFailed = false
                    draftNote = "Jarvis filled it in below. Check it over, change anything, then Save."
                }
            case .refused(let why):
                draftFailed = true
                draftNote = why
            }
        } catch {
            draftFailed = true
            draftNote = "Couldn't reach Jarvis. Check the connection and try again."
        }
    }

    // MARK: 1. When does it run?

    private var triggerSection: some View {
        Section {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                ForEach(PlaybookWording.triggerTiles, id: \.type) { tile in
                    let on = draft.trigger.type == tile.type
                    Button {
                        animate { if !on { draft.trigger = DraftTrigger.blank(tile.type) } }
                    } label: {
                        Label(tile.short, systemImage: tile.icon)
                            .font(.subheadline.weight(on ? .semibold : .regular))
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .padding(.horizontal, 10)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(on ? Theme.glacier.opacity(0.32) : Color.white.opacity(0.06)))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(on ? Theme.glacier : .clear, lineWidth: 1))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.vertical, 4)
            if draft.trigger.type == "time" {
                DatePicker("Time", selection: timeBinding, displayedComponents: .hourAndMinute)
                    .frame(minHeight: 44)
                VStack(alignment: .leading, spacing: 8) {
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
                    Text(draft.trigger.days.isEmpty ? "Every day. Tap days to pick only some." : Playbooks.daysLabel(draft.trigger.days).capitalized)
                        .font(.caption).foregroundStyle(Theme.frostDim)
                }
                .padding(.vertical, 4)
            }
            if draft.trigger.type == "arrive" {
                Stepper(draft.trigger.minAway == 0 ? "Every time I get home" : "Only after \(draft.trigger.minAway) min away", value: $draft.trigger.minAway, in: 0...1440, step: 5)
                    .frame(minHeight: 44)
            }
        } header: {
            Text("1. When does it run?")
        } footer: {
            Text(Playbooks.triggerLine(draft.trigger.plain) + ".")
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

    // MARK: 2. What happens?

    private var stepsSection: some View {
        Section {
            if steps.isEmpty {
                Text("Nothing yet. Tap a button below to add the first step; they run top to bottom.")
                    .font(.subheadline).foregroundStyle(Theme.frostDim)
            }
            ForEach($steps) { $item in
                StepRow(item: $item, number: (steps.firstIndex { $0.id == item.id } ?? 0) + 1, options: options,
                        open: openStep == item.id && !reordering) {
                    animate { openStep = openStep == item.id ? nil : item.id }
                }
            }
            .onDelete { offsets in animate { steps.remove(atOffsets: offsets) } }
            .onMove { from, to in animate { steps.move(fromOffsets: from, toOffset: to) } }
            if !reordering {
                addStepButtons
            }
        } header: {
            HStack {
                Text("2. What happens?")
                Spacer()
                if steps.count > 1 {
                    Button(reordering ? "Done" : "Reorder") { animate { reordering.toggle() } }
                        .font(.caption.weight(.semibold))
                        .textCase(nil)
                        .frame(minHeight: 44)
                }
            }
        } footer: {
            Text(steps.count >= PlaybookDraft.maxSteps
                 ? "That's the most: a playbook can have up to \(PlaybookDraft.maxSteps) steps."
                 : "Tap a step to change it. Swipe left to delete; Reorder to move one.")
        }
    }

    /// The "Add a step" row: one tap adds that kind at the end, opened.
    private var addStepButtons: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
            ForEach(PlaybookWording.stepButtons, id: \.type) { choice in
                Button {
                    let added = EditableStep(step: DraftStep.blank(choice.type, options: options))
                    animate {
                        steps.append(added)
                        openStep = added.id
                    }
                } label: {
                    Label(choice.short, systemImage: choice.icon)
                        .font(.subheadline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.07)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add a step: \(choice.short)")
            }
        }
        .disabled(steps.count >= PlaybookDraft.maxSteps)
        .opacity(steps.count >= PlaybookDraft.maxSteps ? 0.4 : 1)
        .padding(.vertical, 4)
        .moveDisabled(true)
        .deleteDisabled(true)
    }

    // MARK: 3. How does Jarvis know it worked?

    private var checksSection: some View {
        Section {
            stringRows(nil, rows: $draft.done, placeholder: "Every light is off", add: "Add a check")
        } header: {
            Text("3. How does Jarvis know it worked? (Optional)")
        } footer: {
            Text("He checks each of these after every run, and tells you if one didn't hold.")
        }
    }

    @ViewBuilder
    private func stringRows(_ title: String?, rows: Binding<[String]>, placeholder: String? = nil, add: String = "Add a line") -> some View {
        if let title { Text(title).font(.subheadline.weight(.semibold)) }
        ForEach(Array(rows.wrappedValue.enumerated()), id: \.offset) { index, _ in
            HStack {
                TextField(placeholder ?? "Line \(index + 1)", text: rows[index], axis: .vertical)
                Button { animate { _ = rows.wrappedValue.remove(at: index) } } label: {
                    Image(systemName: "minus.circle.fill").foregroundStyle(Theme.rose)
                }
                .buttonStyle(.plain)
                .frame(width: 44, height: 44)
                .accessibilityLabel("Remove line \(index + 1)")
            }
        }
        if rows.wrappedValue.count < 10 {
            Button { animate { rows.wrappedValue.append("") } } label: { Label(add, systemImage: "plus") }
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
                Button { animate { _ = rows.wrappedValue.remove(at: index) } } label: {
                    Image(systemName: "minus.circle.fill").foregroundStyle(Theme.rose)
                }
                .buttonStyle(.plain)
                .frame(width: 44, height: 44)
                .accessibilityLabel("Remove \(title.lowercased()) \(index + 1)")
            }
        }
        if rows.wrappedValue.count < 10 {
            Button { animate { rows.wrappedValue.append(.init("", "")) } } label: { Label("Add", systemImage: "plus") }
                .frame(minHeight: 44)
        }
    }

    // MARK: Saving

    /// Saves it whole, as the page does; Jarvis's refusal is shown as said.
    private func save() async {
        let playbook = current
        busy = "Saving \(playbook.name)…"
        defer { busy = nil }
        do {
            let result = try await app.client.savePlaybook(playbook)
            if result.ok {
                onDone()
                dismiss()
            } else {
                refusal = PlaybookTrouble.saveWords(result.detail, hasSteps: !playbook.steps.isEmpty)
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

    /// Simulator checks: `-draftText "…"` fills the box and asks Jarvis for
    /// a draft (saves nothing); `-openFirstStep` opens step 1; `-describeOnly`
    /// leaves the box filled without asking.
    private func debugStart() async {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-draftText"), i + 1 < args.count {
            wish = args[i + 1]
            if !args.contains("-describeOnly") { await writeDraft() }
        }
        if args.contains("-openFirstStep") { openStep = steps.first?.id }
        if args.contains("-reorderSteps") { reordering = true }
        if let i = args.firstIndex(of: "-scrollEditor"), i + 1 < args.count {
            try? await Task.sleep(for: .seconds(0.5))
            scrollTarget = args[i + 1]
        }
        #endif
    }
}

/// A step with an id that lasts while it's moved about.
struct EditableStep: Identifiable, Equatable {
    let id = UUID()
    var step: DraftStep
}

/// One step: folded, a numbered sentence with its kind's icon; open, its fields.
private struct StepRow: View {
    @Binding var item: EditableStep
    let number: Int
    let options: PlaybookOptions
    let open: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: toggle) {
                HStack(spacing: 12) {
                    Text("\(number)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Theme.glacier.opacity(0.28)))
                    Image(systemName: PlaybookWording.stepIcon(item.step.type))
                        .frame(width: 22)
                        .foregroundStyle(Theme.frostDim)
                    Text(item.step.sentence(options))
                        .foregroundStyle(item.step.problem == nil ? Theme.frost : Theme.ember)
                        .lineLimit(open ? 3 : 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.frostDim)
                        .rotationEffect(.degrees(open ? 90 : 0))
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Step \(number): \(item.step.sentence(options))")
            .accessibilityHint(open ? "Folds it" : "Opens it to change")
            if open {
                StepEditor(step: $item.step, number: number, options: options)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
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
            Text(PlaybookWording.steps.first { $0.type == step.type }?.label ?? step.type)
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
