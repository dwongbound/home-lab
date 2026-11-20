// A notice read in full (Dylan, 2026-11-20: "there should be a way for me
// to see long notifications in the notification center"): title, the whole
// body in the same markdown as chat, where it came from and when;
// selectable, scrollable. Reading it changes nothing; only Dismiss clears.
import SwiftUI
import JarvisKit

struct NoticeDetail: View {
    let notice: Notice
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(notice.title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.frost)
                        .textSelection(.enabled)
                    if !notice.body.isEmpty {
                        Text(MarkdownCache.shared.attributed(notice.body))
                            .font(.body)
                            .foregroundStyle(Theme.frost)
                            .textSelection(.enabled)
                    }
                    Text(meta)
                        .font(.footnote)
                        .foregroundStyle(Theme.frostDim)
                    if notice.turnId != nil, notice.source == "push" || !inChat {
                        Text("This message isn't in your chat history any more, so here it is in full.")
                            .font(.footnote)
                            .foregroundStyle(Theme.frostFaint)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.sky.ignoresSafeArea())
            .navigationTitle(Notices.kindWords(notice))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) { actions }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
        .fontDesign(.rounded)
    }

    /// Where it came from and when.
    private var meta: String {
        let when = Notices.when(notice.created)
        let from = notice.source == "push" ? "" : notice.source.capitalized
        return [from, when].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// Whether its message is in the chat as loaded.
    private var inChat: Bool {
        notice.turnId.map { id in app.chat.items.contains { $0.turnId == id } } ?? false
    }

    /// The acts that apply, a word or two each; the main one on the right.
    @ViewBuilder
    private var actions: some View {
        let canDismiss = !notice.isApproval && !notice.kept && notice.source != "push"
        let open = inChat
        let report = notice.reportId
        if canDismiss || open || report != nil {
            HStack(spacing: 10) {
                if canDismiss {
                    button("Keep", main: false) {
                        dismiss()
                        Task { await app.keep(notice) }
                    }
                    button(notice.clearLabel, main: !open && report == nil) {
                        dismiss()
                        Task { await app.clearNotices([notice.id]) }
                    }
                }
                if let report {
                    button("Open report", main: true) {
                        dismiss()
                        Task { await app.openReport(id: report) }
                    }
                } else if open {
                    button("Open chat", main: true) {
                        dismiss()
                        Task { await app.openTurn(notice.turnId, about: notice) }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
    }

    private func button(_ title: String, main: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(main ? Theme.basalt : Theme.frost)
                .background(Capsule().fill(main ? Theme.glacier : Color.white.opacity(0.10)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
