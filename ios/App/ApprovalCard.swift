// The amber "Needs your OK" card, and the "That was wrong" sheet.
import SwiftUI
import JarvisKit

/// Jarvis asking before he does something. Approve/Deny until answered,
/// then how it ended (here, out loud, or timed out).
struct ApprovalCard: View {
    let approval: Approval
    let outcome: String?
    let onAnswer: (Bool) -> Void

    /// Label, what he wants to do, then the buttons or the outcome.
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Needs your OK")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(Theme.ember)
            Text(ApprovalWording.toolLabel(approval.tool))
                .font(.headline)
            Text(ApprovalWording.readableSummary(approval.summary))
                .foregroundStyle(Theme.frost.opacity(0.8))
            if let outcome {
                Text(outcome)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(outcomeColor(outcome))
            } else {
                HStack(spacing: 10) {
                    Button { onAnswer(false) } label: {
                        Text("Deny").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.frost)
                    Button { onAnswer(true) } label: {
                        Text("Approve").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.ember)
                    .foregroundStyle(Theme.basalt)
                }
                .font(.body.weight(.semibold))
            }
        }
        .padding(14)
        .glassPanel(tint: Theme.ember)
    }

    /// Green for a yes, amber for held, rose for everything else.
    private func outcomeColor(_ text: String) -> Color {
        if text.hasPrefix("Approved") { return Theme.moss }
        if text.hasPrefix("Holding") { return Theme.ember }
        return Theme.rose
    }
}

/// A settled approval in the conversation: one quiet line ("Approved:
/// Write notes.md", "Timed out: …"), coloured by how it ended.
struct ApprovalLine: View {
    let text: String

    /// A small icon and the line, in the outcome's colour.
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.footnote.weight(.semibold))
            Text(text)
                .font(.footnote)
                .lineLimit(2)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(color.opacity(0.10)))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// A tick, a cross, a clock or a pause.
    private var symbol: String {
        if text.hasPrefix("Approved") { return "checkmark.circle.fill" }
        if text.hasPrefix("Timed out") { return "clock.badge.xmark" }
        if text.hasPrefix("Holding") { return "pause.circle.fill" }
        return "xmark.circle.fill"
    }

    /// Green for a yes, amber for held, quiet for a timeout, rose for no.
    private var color: Color {
        if text.hasPrefix("Approved") { return Theme.moss }
        if text.hasPrefix("Holding") { return Theme.ember }
        if text.hasPrefix("Timed out") { return Theme.frostDim }
        return Theme.rose
    }
}

/// "That was wrong": what Dylan wanted instead. Jarvis turns these into a
/// fix and an eval case overnight.
struct WrongSheet: View {
    let item: ChatItem
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @State private var sending = false

    /// The reply being flagged, a note box, Send and Close.
    var body: some View {
        NavigationStack {
            Form {
                Section("He said") {
                    Text(item.text).foregroundStyle(Theme.frostDim).lineLimit(6)
                }
                Section("What should he have said?") {
                    TextField("A few words is plenty", text: $note, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            .navigationTitle("That was wrong")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if sending {
                        ProgressView().accessibilityLabel("Sending")
                    } else {
                        Button("Send") { send() }
                            .disabled(note.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// Sends the flag and closes once the PC has it.
    private func send() {
        sending = true
        Task {
            let sent = await app.chat.flagWrong(item, note: note, app: app)
            sending = false
            if sent { dismiss() }
        }
    }
}
