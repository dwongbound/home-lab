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

    /// Which page: the notices, or what's running (swipe across, or tap
    /// the switch at the top).
    @State private var page = 0

    var body: some View {
        NavigationStack {
            TabView(selection: $page) {
                noticesPage.tag(0)
                runningPage.tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .onAppear {
                if app.notices.isEmpty && !running.isEmpty { page = 1 }
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-runningPage") { page = 1 }
                #endif
            }
            .background(Theme.sky.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Show", selection: $page) {
                        Text("Notices").tag(0)
                        Text(running.isEmpty ? "Running" : "Running (\(running.count))").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 260)
                }
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

    /// What Jarvis is working on.
    private var running: [RunningTask] {
        app.today.snapshot?.jobs?.running ?? []
    }

    /// Jobs that finished in the last day.
    private var finished: [(job: JobRecord, word: String, at: Date)] {
        app.today.snapshot?.jobs?.recentlyFinished() ?? []
    }

    /// The second page: each running or queued job with its status and a
    /// ticking timer, newest first; then what finished recently.
    private var runningPage: some View {
        List {
            if running.isEmpty {
                Text("Nothing running right now.")
                    .foregroundStyle(Theme.frostDim)
                    .listRowBackground(Color.white.opacity(0.06))
            }
            ForEach(running.reversed()) { task in
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    HStack(spacing: 12) {
                        if task.state == "queued" {
                            Image(systemName: "clock").foregroundStyle(Theme.frostDim)
                        } else {
                            ProgressView().tint(OrbView.taskBlue(onLight: false))
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                JobChip(model: task.model)
                                Text(task.label).font(.body.weight(.semibold)).foregroundStyle(Theme.frost)
                            }
                            // Where it's at ("Running tests"), else its status.
                            Text(task.stageLine(now: context.date)).font(.subheadline).foregroundStyle(Theme.frostDim).lineLimit(1).truncationMode(.tail)
                        }
                        Spacer()
                        if let timer = Orbit.elapsed(since: task.startedAt, now: context.date), task.state != "queued" {
                            Text(timer).font(.caption.monospacedDigit()).foregroundStyle(OrbView.taskBlue(onLight: false))
                        }
                    }
                    .frame(minHeight: 44)
                    .accessibilityElement(children: .combine)
                }
                .listRowBackground(Color.white.opacity(0.06))
            }
            if !finished.isEmpty {
                Section("Recently finished") {
                    ForEach(finished, id: \.job.id) { entry in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(entry.job.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.frost)
                                JobChip(model: entry.job.model)
                                Spacer()
                                Text("\(entry.word) · \(entry.at.formatted(date: .omitted, time: .shortened))")
                                    .font(.caption)
                                    .foregroundStyle(entry.word == "Failed" ? Theme.ember : Theme.frostDim)
                            }
                            if let result = entry.job.lastResult, !result.isEmpty {
                                Text(result).font(.caption).foregroundStyle(Theme.frostDim).lineLimit(2)
                            }
                        }
                        .frame(minHeight: 44)
                        .accessibilityElement(children: .combine)
                        .listRowBackground(Color.white.opacity(0.04))
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    /// The first page: the notices.
    @ViewBuilder
    private var noticesPage: some View {
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
                                        Button(notice.clearLabel, role: .destructive) { Task { await app.clearNotices([notice.id]) } }
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
        }

    /// One notice: its dot (orange unread, yellow kept), title, a line of
    /// body, and when. No icon beside the dot (Dylan, 2026-11-19: "we don't
    /// need both … get rid of the bell"); VoiceOver still says the kind.
    /// A need row with an approval carries Approve and Deny.
    private func row(_ notice: Notice) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                // Opening it reads it (cleared everywhere), unless it needs
                // an answer, and opens Chat at the full message.
                if let reportId = notice.reportId {
                    // "Report ready": the report itself, in the app's reader.
                    Task { await app.openReport(id: reportId, clearing: notice) }
                    return
                }
                if notice.turnId != nil {
                    Task { await app.openTurn(notice.turnId, clearing: Orbit.readOnView(notice) ? notice : nil) }
                } else {
                    Task { await app.readNotice(notice) }
                    app.tab = .chat
                }
                dismiss()
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Circle().fill(notice.kept ? OrbView.keptYellow(onLight: false) : color(notice.kind)).frame(width: 10, height: 10)
                        .accessibilityLabel(Notices.kindWords(notice))
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
        await app.answerNotice(notice, ok: ok)
    }

    /// Notices are orange (Dylan, 2026-11-18); one that needs him brightest.
    private func color(_ kind: NoticeKind) -> Color {
        OrbView.noticeOrange(onLight: false).opacity(kind == .need ? 1 : kind == .heads ? 0.85 : 0.7)
    }
}
