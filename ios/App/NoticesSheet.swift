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
    /// The notice open to read in full.
    @State private var reading: Notice?

    var body: some View {
        NavigationStack {
            // Not a swiping pager any more: a notice row's sideways swipe is
            // its own (Dismiss, See in chat), so the pages change by the
            // switch at the top, or by a sideways swipe on the Running page
            // or an empty Notices page (Dylan, 2026-11-19).
            // Three pages (Dylan, 2026-11-21): notices, then what he kept
            // in the middle, then what's running: orange, yellow, blue.
            ZStack {
                if page == 0 {
                    noticesPage
                        .transition(.move(edge: .leading))
                } else if page == 1 {
                    keptPage
                        .transition(.opacity)
                } else {
                    runningPage
                        .transition(.move(edge: .trailing))
                        .simultaneousGesture(pageSwipe(to: 1, when: { $0 > 60 }))
                }
            }
            .animation(.snappy(duration: 0.3), value: page)
            // The lists start just under the switch, not a band below it.
            .contentMargins(.top, 6, for: .scrollContent)
            .listSectionSpacing(.compact)
            .onAppear {
                if app.notices.isEmpty && !running.isEmpty { page = 2 }
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-runningPage") { page = 2 }
                if ProcessInfo.processInfo.arguments.contains("-keptPage") { page = 1 }
                #endif
            }
            .background(Theme.sky.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // The pages as dots (Dylan, 2026-11-20): orange for notices,
                // blue for what's running, the orb's own colours. No Close:
                // swipe the drawer down or tap outside it.
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 4) {
                        pageDot(0, color: OrbView.noticeOrange(onLight: false), count: app.notices.count, name: "Notices")
                        pageDot(1, color: OrbView.keptYellow(onLight: false), count: app.keptNotices.count, name: "Kept")
                        pageDot(2, color: OrbView.taskBlue(onLight: false), count: running.count, name: "Running")
                    }
                    .padding(3)
                    .glassChip(Capsule())
                }
            }
        }
        .alert("Notice", isPresented: Binding(get: { app.noticeProblem != nil }, set: { if !$0 { app.noticeProblem = nil } })) {
            Button("Close", role: .cancel) {}
        } message: {
            Text(app.noticeProblem ?? "")
        }
        .sheet(item: $reading) { notice in
            NoticeDetail(notice: notice).environmentObject(app)
        }
        // Opens a little taller than half (about five cards on a 17 Pro).
        .presentationDetents([.fraction(0.66), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.ultraThinMaterial)
        .preferredColorScheme(.dark)
        .fontDesign(.rounded)
    }

    /// What Jarvis is working on.
    private var running: [RunningTask] {
        (app.today.snapshot?.jobs?.running ?? []).filter { !app.stoppedJobs.contains($0.id) }
    }
    /// Jobs with a stop on its way ("Stopping").
    @State private var stopping: Set<String> = []
    /// A stop that didn't go through.
    @State private var stopNote: String?

    /// What finished today (or, from an older Jarvis, in the last day).
    private var finished: [(id: String, name: String, word: String, at: Date?, model: String?, detail: String?)] {
        app.today.snapshot?.jobs?.finishedRows() ?? []
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
              Section {
                  Group {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        HStack(spacing: 12) {
                            if task.isQueued {
                                // Waiting its turn: a hollow, dimmer blue dot.
                                Circle().strokeBorder(OrbView.taskBlue(onLight: false).opacity(0.6), lineWidth: 2).frame(width: 14, height: 14)
                            } else {
                                ProgressView().tint(OrbView.taskBlue(onLight: false))
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    JobChip(model: task.model)
                                    Text(task.label).font(.body.weight(.semibold)).foregroundStyle(Theme.frost)
                                }
                                // Where it's at ("Running tests"), else its status.
                                Text(task.stepLine(now: context.date)).font(.subheadline).foregroundStyle(Theme.frostDim).lineLimit(1).truncationMode(.tail)
                            }
                            Spacer()
                            if stopping.contains(task.id) {
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.small)
                                    Text("Stopping").font(.caption).foregroundStyle(Theme.frostDim)
                                }
                            } else if task.isQueued {
                                Text("Queued").font(.caption).foregroundStyle(Theme.frostDim)
                            } else if let timer = Orbit.elapsed(since: task.startedAt, now: context.date) {
                                Text(timer).font(.caption.monospacedDigit()).foregroundStyle(OrbView.taskBlue(onLight: false))
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                    .listRowBackground(Color.white.opacity(0.06))
                    // All the way across stops it (Dylan, 2026-11-20); part way
                    // shows Stop. Only where Jarvis says it can be stopped.
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if task.canStop && !stopping.contains(task.id) {
                            Button("Stop", systemImage: "stop.fill", role: .destructive) {
                                haptic()
                                stopping.insert(task.id)
                                Task {
                                    stopNote = await app.stopJob(task)
                                    stopping.remove(task.id)
                                }
                            }
                        }
                    }
                  }
                  .fullWidthSeparators()
              }
            }
            if let stopNote {
                Text(stopNote).font(.footnote).foregroundStyle(Theme.frostDim)
                    .listRowBackground(Color.clear)
            }
            if !finished.isEmpty {
                Section("Recently finished") {
                    Group {
                        ForEach(finished, id: \.id) { entry in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(entry.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.frost).lineLimit(2)
                                    JobChip(model: entry.model)
                                    Spacer()
                                    Text([entry.word, entry.at?.formatted(date: .omitted, time: .shortened)].compactMap { $0 }.joined(separator: " · "))
                                        .font(.caption)
                                        .foregroundStyle(entry.word == "Failed" ? Theme.ember : Theme.frostDim)
                                }
                                if let detail = entry.detail, !detail.isEmpty {
                                    Text(detail).font(.caption).foregroundStyle(Theme.frostDim).lineLimit(2)
                                }
                            }
                            .accessibilityElement(children: .combine)
                            .listRowBackground(Color.white.opacity(0.04))
                        }
                    }
                    .fullWidthSeparators()
                }
            }
        }
        .jarvisRows()
        .scrollContentBackground(.hidden)
    }

    /// The middle page: everything he kept, notices and chat messages
    /// alike (keeping a message makes a kept notice for it), newest first.
    /// Tap one to read it whole; the swipe and its button say Dismiss
    /// (Dylan: kept items say Dismiss, never Unkeep), which lets it go.
    @ViewBuilder
    private var keptPage: some View {
        let kept = Notices.sorted(app.keptNotices)
        if kept.isEmpty {
            ContentUnavailableView("Nothing kept", systemImage: "bookmark", description: Text("Keep a notice or a message to find it here."))
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 30).onEnded { drag in
                    guard abs(drag.translation.width) > abs(drag.translation.height) else { return }
                    page = drag.translation.width < -60 ? 2 : drag.translation.width > 60 ? 0 : page
                })
        } else {
            List {
                ForEach(kept) { notice in
                    Section {
                        Group {
                            row(notice)
                                .listRowBackground(Color.white.opacity(0.06))
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(NoticeAction.unkeep.label, systemImage: "xmark") {
                                        haptic()
                                        Task { await app.letGo(notice) }
                                    }
                                    .tint(OrbView.keptYellow(onLight: false))
                                    if notice.turnId != nil {
                                        Button(NoticeAction.seeInChat.label, systemImage: "bubble.left") {
                                            Task { await app.openTurn(notice.turnId, clearingWhenFound: nil, about: notice) }
                                            dismiss()
                                        }
                                        .tint(Theme.glacier)
                                    }
                                }
                        }
                        .fullWidthSeparators()
                    }
                }
            }
            .jarvisRows()
            .scrollContentBackground(.hidden)
            .animation(.smooth, value: kept.map(\.id))
        }
    }

    /// The first page: the notices.
    @ViewBuilder
    private var noticesPage: some View {
        Group {
                if app.notices.isEmpty {
                    ContentUnavailableView("All caught up", systemImage: "checkmark.circle", description: Text("Nothing new from Jarvis."))
                        .contentShape(Rectangle())
                        .gesture(pageSwipe(to: 1, when: { $0 < -60 }))
                } else {
                    List {
                        // Each notice its own card (Dylan, 2026-11-20): a
                        // section per row, so swipes clip to its corners.
                        ForEach(app.notices) { notice in
                          Section {
                              Group {
                                row(notice)
                                    .listRowBackground(Color.white.opacity(0.06))
                                    // The usual Apple swipe: all the way dismisses;
                                    // part way shows Dismiss and See in chat.
                                    // A kept one offers Unkeep, never on a full
                                    // swipe; an approval waiting on him offers
                                    // nothing that could look like an answer.
                                    .swipeActions(edge: .trailing, allowsFullSwipe: !notice.kept && !notice.isApproval) {
                                        if notice.kept {
                                            Button(NoticeAction.unkeep.label, systemImage: "xmark") {
                                                haptic()
                                                Task { await app.letGo(notice) }
                                            }
                                            .tint(OrbView.keptYellow(onLight: false))
                                        } else if !notice.isApproval {
                                            Button(notice.clearLabel, systemImage: "xmark", role: .destructive) {
                                                haptic()
                                                Task { await app.clearNotices([notice.id]) }
                                            }
                                        }
                                        if notice.turnId != nil {
                                            Button(NoticeAction.seeInChat.label, systemImage: "bubble.left") {
                                                Task { await app.openTurn(notice.turnId, clearingWhenFound: !notice.kept && !notice.isApproval ? notice : nil, about: notice) }
                                                dismiss()
                                            }
                                            .tint(Theme.glacier)
                                        }
                                    }
                              }
                              .fullWidthSeparators()
                          }
                        }
                        Section {
                            Group {
                                Button("Clear all") { Task { await app.clearAllNotices() } }
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .foregroundStyle(Theme.glacier)
                            }
                            .fullWidthSeparators()
                        }
                        .listRowBackground(Color.clear)
                    }
                    .jarvisRows()
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
                // Opens the whole notice to read; reading clears nothing
                // (Dylan, 2026-11-20: long ones were cut off with no way to
                // see the rest). Its message and Dismiss are in there.
                reading = notice
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Circle().fill(notice.kept ? OrbView.keptYellow(onLight: false) : color(notice.kind)).frame(width: 10, height: 10)
                        .accessibilityLabel(Notices.kindWords(notice))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(notice.title).font(.body.weight(.semibold)).foregroundStyle(Theme.frost)
                        if !notice.body.isEmpty {
                            Text(notice.body).font(.subheadline).foregroundStyle(Theme.frostDim).lineLimit(3)
                            if NoticeFocus.isLong(notice.body) {
                                Text("More").font(.footnote.weight(.semibold)).foregroundStyle(Theme.glacier)
                            }
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
        .accessibilityElement(children: .contain)
    }

    /// One page's dot in the switch: lit and in the capsule when chosen.
    private func pageDot(_ which: Int, color: Color, count: Int, name: String) -> some View {
        let on = page == which
        return Button {
            page = which
        } label: {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 10, height: 10)
                    .shadow(color: on ? color.opacity(0.8) : .clear, radius: on ? 4 : 0)
                if count > 0 {
                    Text("\(count)").font(.footnote.weight(.semibold).monospacedDigit())
                }
            }
            .opacity(on ? 1 : 0.45)
            .padding(.horizontal, 14)
            .frame(minWidth: 56, minHeight: 38)
            .background(Capsule().fill(on ? Color.white.opacity(0.14) : .clear))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.frost)
        .frame(minHeight: 44)
        .accessibilityLabel("\(name), \(count)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// A sideways swipe that changes page, for the places a row doesn't own.
    private func pageSwipe(to target: Int, when: @escaping (CGFloat) -> Bool) -> some Gesture {
        DragGesture(minimumDistance: 30).onEnded { drag in
            guard abs(drag.translation.width) > abs(drag.translation.height), when(drag.translation.width) else { return }
            page = target
        }
    }

    private func haptic() {
        Haptics.play(.fullSwipe)
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
