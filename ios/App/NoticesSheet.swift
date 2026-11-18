// The notices sheet (Dylan, 2026-11-18: the "pips on the orb" design).
// Pull down on the status row, or tap a pip circling the orb, and this
// glass sheet drops in: one list, newest first. A row that needs Dylan
// carries Approve and Deny; any other swipes away; "Clear all" at the
// bottom. Tapping a row opens Chat, where Jarvis said it. Clearing goes to
// the page server, so it clears on every device. No money, ever.
import SwiftUI
import JarvisKit

struct NoticesSheet: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if app.notices.isEmpty {
                    ContentUnavailableView("All caught up", systemImage: "checkmark.circle", description: Text("Nothing new from Jarvis."))
                } else {
                    List {
                        ForEach(app.notices) { notice in
                            row(notice)
                                .listRowBackground(Color.white.opacity(0.06))
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    if !notice.isApproval {
                                        Button("Clear", role: .destructive) { Task { await app.clearNotices([notice.id]) } }
                                    }
                                }
                        }
                        Section {
                            Button("Clear all") { Task { await app.clearAllNotices() } }
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .foregroundStyle(Theme.glacier)
                        }
                        .listRowBackground(Color.clear)
                    }
                    .scrollContentBackground(.hidden)
                    .animation(.smooth, value: app.notices.map(\.id))
                }
            }
            .background(Theme.sky.ignoresSafeArea())
            .navigationTitle("Notices")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.ultraThinMaterial)
        .preferredColorScheme(.dark)
        .fontDesign(.rounded)
    }

    /// One notice: its pip colour, icon, title, a line of body, and when.
    /// A need row with an approval carries Approve and Deny.
    private func row(_ notice: Notice) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                app.tab = .chat
                dismiss()
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Circle().fill(color(notice.kind)).frame(width: 10, height: 10)
                    Image(systemName: Notices.symbol(notice.source))
                        .foregroundStyle(color(notice.kind))
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(notice.title).font(.body.weight(.semibold)).foregroundStyle(Theme.frost)
                        if !notice.body.isEmpty {
                            Text(notice.body).font(.subheadline).foregroundStyle(Theme.frostDim).lineLimit(2)
                        }
                    }
                    Spacer(minLength: 8)
                    Text(Notices.when(notice.created)).font(.caption).foregroundStyle(Theme.frostFaint)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if let approvalId = notice.approvalId {
                HStack(spacing: 12) {
                    Button("Deny") { Task { await answer(approvalId, notice: notice, ok: false) } }
                        .buttonStyle(.bordered)
                        .frame(minHeight: 44)
                    Button("Approve") { Task { await answer(approvalId, notice: notice, ok: true) } }
                        .buttonStyle(.borderedProminent)
                        .frame(minHeight: 44)
                }
                .padding(.leading, 46)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
    }

    /// Answers the approval, then clears its notice everywhere.
    private func answer(_ approvalId: String, notice: Notice, ok: Bool) async {
        do {
            try await app.client.answer(approval: approvalId, ok: ok)
            await app.clearNotices([notice.id])
        } catch {
            app.noteReach(error)
        }
    }

    /// The pip colours: orange needs you, blue heads-up, dim white FYI.
    private func color(_ kind: NoticeKind) -> Color {
        switch kind {
        case .need: return Color(red: 1.0, green: 0.54, blue: 0.24)
        case .heads: return Color(red: 0.44, green: 0.72, blue: 1.0)
        case .fyi: return Theme.frostDim
        }
    }
}
