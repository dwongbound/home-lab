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
    /// The whole message from its chat turn: the notice itself carries at
    /// most 300 characters of title and of body (the page server's cap), so
    /// a long one stopped mid-word (Dylan, 2026-11-20). Nil until it's read,
    /// or when the turn can't be found: then the notice's own text shows.
    @State private var full: NoticeFullText?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(full?.title ?? notice.title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.frost)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("noticeTitle")
                    if !(full?.body ?? notice.body).isEmpty {
                        // The same light markdown as the message in Chat.
                        Text(MarkdownCache.shared.attributed(full?.body ?? notice.body))
                            .font(.body)
                            .foregroundStyle(Theme.frost)
                            // Long-press to copy; text selection would make
                            // its links untappable.
                            .contextMenu {
                                Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = full?.body ?? notice.body }
                            }
                    }
                    Text(meta)
                        .font(.footnote)
                        .foregroundStyle(Theme.frostDim)
                    if notice.turnId != nil, notice.source == "push" {
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
                SheetClose { dismiss() }
            }
            .safeAreaInset(edge: .bottom) { actions }
            .task { await loadFull() }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
        .fontDesign(.rounded)
    }

    /// Reads the message's chat turn (a read-only history GET) and keeps its
    /// whole text when it's longer than what the notice carries.
    private func loadFull() async {
        guard let turnId = notice.turnId, notice.source != "push" else { return }
        let text: String?
        if let held = app.chat.items.first(where: { $0.turnId == turnId }) {
            text = held.text
        } else {
            text = (try? await app.client.history(.around(turnId, limit: 3)))?.turns.first { $0.id == turnId }?.text
        }
        guard let text, let whole = NoticeFullText.from(turn: text, title: notice.title, body: notice.body) else { return }
        var quiet = Transaction()
        quiet.disablesAnimations = true
        withTransaction(quiet) { full = whole }
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
        // A kept one: one Dismiss, which lets it go (no Keep beside it).
        let keptDismiss = notice.kept && !notice.isApproval
        // Chat can open any message it can find, loaded or not.
        let open = notice.turnId != nil && notice.source != "push"
        let report = notice.reportId
        if canDismiss || keptDismiss || open || report != nil {
            HStack(spacing: 10) {
                if keptDismiss {
                    button("Dismiss", main: !open && report == nil) {
                        dismiss()
                        Task { await app.letGo(notice) }
                    }
                }
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
                        // Opening it in Chat dismisses it too (Dylan,
                        // 2026-11-20), once Chat has found the message.
                        let clears = !notice.isApproval && !notice.kept && notice.source != "push"
                        Task { await app.openTurn(notice.turnId, clearingWhenFound: clears ? notice : nil, about: notice) }
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
