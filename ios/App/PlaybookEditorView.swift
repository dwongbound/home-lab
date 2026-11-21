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
                // Save stays top right, where Apple puts it; the x takes the left.
                ToolbarItem(placement: .topBarLeading) {
                    SheetCloseButton { dismiss() }.disabled(busy != nil)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .fontWeight(.semibold)
                        .disabled(current.problem(options) != nil || busy != nil)
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
                Group {
                    TextField("Name, like Bedtime", text: $draft.name)
                        .font(.headline)
                    Toggle("On", isOn: $draft.enabled).tint(Theme.glacier)
                    TextField("What it's for (optional)", text: $draft.purpose, axis: .vertical)
                }
                .fullWidthSeparators()
            }
            if !isNew {
                Section {
                    Group {
                        DisclosureGroup("Rewrite it from a description", isExpanded: $describeOpen) {
                            describeFields
                        }
                    }
                    .fullWidthSeparators()
                }
            }
            triggerSection
            stepsSection.id("steps")
            checksSection.id("checks")
            Section {
                Group {
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
                    }
                }
                .fullWidthSeparators()
            }
            if let problem = current.problem(options) {
                Section {
                    Group {
                        Label(problem, systemImage: "exclamationmark.circle").foregroundStyle(Theme.ember)
                    }
                    .fullWidthSeparators()
                } footer: {
                    Text("Save works once this is sorted.")
                }
            }
            if !isNew {
                Section {
                    Group {
                        Button("Delete playbook", role: .destructive) { confirmingDelete = true }
                    }
                    .fullWidthSeparators()
                }
            }
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .jarvisRows()
        #if DEBUG
        // `-openFirstStep`: the first step unfolded (layout checks).
        .onAppear {
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-openFirstStep") { openStep = steps.first?.id }
            // `-openStep <n>`: that step unfolded (1-based).
            if let at = args.firstIndex(of: "-openStep"), at + 1 < args.count, let n = Int(args[at + 1]), n >= 1, n <= steps.count {
                openStep = steps[n - 1].id
                let target = steps[n - 1].id
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { proxy.scrollTo(target, anchor: .top) }
            }
        }
        #endif
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
            Group {
                describeFields
            }
            .fullWidthSeparators()
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
            Group {
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
    
                if draft.trigger.type == "time" {
                    DatePicker("Time", selection: timeBinding, displayedComponents: .hourAndMinute)
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
        
                }
                if draft.trigger.type == "arrive" {
                    Stepper(draft.trigger.minAway == 0 ? "Every time I get home" : "Only after \(draft.trigger.minAway) min away", value: $draft.trigger.minAway, in: 0...1440, step: 5)
                }
            }
            .fullWidthSeparators()
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
            Group {
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
            }
            .fullWidthSeparators()
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
            // The kinds Jarvis describes (the built-in eight on an older Jarvis).
            ForEach(options.stepChoices) { choice in
                Button {
                    let added = EditableStep(step: DraftStep.blank(choice.type, options: options))
                    animate {
                        steps.append(added)
                        openStep = added.id
                    }
                } label: {
                    Label(choice.short, systemImage: PlaybookWording.stepIcon(choice.type))
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

        .moveDisabled(true)
        .deleteDisabled(true)
    }

    // MARK: 3. How does Jarvis know it worked?

    private var checksSection: some View {
        Section {
            Group {
                stringRows(nil, rows: $draft.done, placeholder: "Every light is off", add: "Add a check")
            }
            .fullWidthSeparators()
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
                        .foregroundStyle(item.step.problem(options) == nil ? Theme.frost : Theme.ember)
                        .lineLimit(open ? 3 : 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.frostDim)
                        .rotationEffect(.degrees(open ? 90 : 0))
                }
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
            Text(options.stepLabel(step))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.frostDim)
            fields
            if let problem = step.problem(options) {
                Text(problem.prefix(1).uppercased() + problem.dropFirst()).font(.caption).foregroundStyle(Theme.ember)
            }
        }
    }

    /// One box per field of the step's kind, as Jarvis describes it (Dylan,
    /// 2026-11-20: new kinds need no code). A kind he didn't describe is kept
    /// and saved back as it came, never edited here.
    @ViewBuilder
    private var fields: some View {
        if let described = options.stepType(of: step) {
            ForEach(described.fields, id: \.key) { field in
                if let rule = options.activeRule(field, step) {
                    StepFieldBox(key: field.key, rule: rule, step: $step, options: options)
                }
            }
        } else {
            Text("This kind of step can only be changed on the home page.")
                .font(.footnote)
                .foregroundStyle(Theme.frostDim)
        }
    }
}

/// One field of a step, drawn by its kind: words, long words, a number, a
/// switch, a pick (with "Jarvis picks" when it isn't required) or emails.
private struct StepFieldBox: View {
    let key: String
    let rule: StepFieldRule
    @Binding var step: DraftStep
    let options: PlaybookOptions

    private func set(_ value: StepValue?) { step = step.with(key, value, options: options) }

    var body: some View {
        switch rule.kind {
        case "bool":
            Toggle(rule.label, isOn: Binding(get: { step[key]?.bool ?? false }, set: { set(.bool($0)) }))
                .tint(Theme.glacier)
        case "number":
            HStack {
                Text(rule.label)
                Spacer(minLength: 12)
                TextField(rule.placeholder ?? "Number", value: Binding(get: { step[key]?.number }, set: { set($0.map(StepValue.number)) }), format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 120)
            }
        case "choice":
            let choices = options.choices(for: rule, step)
            let current = step[key]?.text ?? ""
            Picker(rule.label, selection: Binding(get: { current }, set: { set(.text($0)) })) {
                if !rule.required { Text("Jarvis picks").tag(StepTypes.auto) }
                if !choices.contains(where: { $0.id == current }) && !(current == StepTypes.auto && !rule.required) {
                    Text(current.isEmpty ? "Pick one" : StepTypes.plainWords(current)).tag(current)
                }
                ForEach(choices) { Text($0.name).tag($0.id) }
            }
        case "emails":
            TextField(rule.placeholder ?? "\(rule.label) (commas between addresses)", text: Binding(get: { step[key]?.text ?? "" }, set: { set(.text($0)) }))
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
        case "longtext":
            TextField(rule.placeholder ?? rule.label, text: Binding(get: { step[key]?.text ?? "" }, set: { set(.text($0)) }), axis: .vertical)
        default:
            TextField(rule.placeholder ?? rule.label, text: Binding(get: { step[key]?.text ?? "" }, set: { set(.text($0)) }))
        }
    }
}
