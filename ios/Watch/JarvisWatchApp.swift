// Jarvis on Apple Watch: ask him something by voice, see his answer, and
// tap Approve or Deny when he needs an OK. Tailscale doesn't run on the
// Watch, so every request goes through the iPhone app (WatchBridge), which
// must be nearby; the phone app doesn't need to be open.
import SwiftUI
import WatchConnectivity
import WatchKit
import WidgetKit
import JarvisKit

@main
struct JarvisWatchApp: App {
    @StateObject private var model = WatchModel()

    /// One screen: the orb, Ask, the last answer, and anything waiting on an OK.
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-complicationGallery") {
                ComplicationGallery()
            } else {
                WatchHome(model: model)
                    .tint(Theme.glacier)
                    .onOpenURL { url in model.open(url) }
            }
            #else
            WatchHome(model: model)
                .tint(Theme.glacier)
                // Complications open the app here: jarvis://ask, jarvis://notices.
                .onOpenURL { url in model.open(url) }
            #endif
        }
    }
}

@MainActor
final class WatchModel: NSObject, ObservableObject, WCSessionDelegate {
    enum Phase: Equatable {
        case idle
        case asking
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var question = ""
    @Published private(set) var answer = ""
    @Published private(set) var model: String?
    @Published private(set) var approvals: [Approval] = []
    @Published var problem: String?
    /// Notices (orange) and tasks Jarvis is chasing (blue), from the phone.
    @Published private(set) var board = WatchBoard()
    /// True when the phone couldn't be reached on the last try.
    @Published private(set) var unreachable = false
    /// The notices list is open (a complication or the button opened it).
    @Published var showingNotices = false
    /// Set by the Ask Jarvis complication: the Ask button glows to say "tap me".
    @Published var askNudge = false

    /// Starts the session with the phone.
    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    /// Sends what Dylan dictated to Jarvis (through the phone) and shows the answer.
    func ask(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, phase == .idle else { return }
        question = trimmed
        answer = ""
        model = nil
        problem = nil
        phase = .asking
        let reply = await send(.ask(trimmed))
        phase = .idle
        switch reply {
        case .answer(let text, let who):
            answer = text
            model = who
            WKInterfaceDevice.current().play(.success)
        case .problem(let words):
            problem = words
            WKInterfaceDevice.current().play(.failure)
        default:
            break
        }
        await refreshApprovals()
    }

    /// Fetches what's waiting on an OK, and the board.
    func refreshApprovals() async {
        if case .approvals(let list) = await send(.approvals) {
            approvals = list
        }
        if case .board(let fresh) = await send(.board) {
            take(fresh)
        }
    }

    /// Clears a notice everywhere (through the phone).
    func clear(_ notice: WatchNotice) async {
        board.notices.removeAll { $0.id == notice.id }
        if case .problem(let words) = await send(.clear([notice.id])) { problem = words }
        await refreshApprovals()
    }

    /// Approve or Deny a notice's approval, then clear it.
    func answer(_ notice: WatchNotice, ok: Bool) async {
        guard let id = notice.approvalId else { return }
        if case .problem(let words) = await send(.answer(id: id, ok: ok)) { problem = words; return }
        WKInterfaceDevice.current().play(ok ? .success : .click)
        await clear(notice)
    }

    /// A complication's link: open the notices, or nudge Ask.
    func open(_ url: URL) {
        switch url.host {
        case "notices": showingNotices = true
        case "ask": askNudge = true
        default: break
        }
    }

    /// New board from the phone: show it and refresh the complications.
    private func take(_ fresh: WatchBoard) {
        board = fresh
        ComplicationStore.save(ComplicationData(board: fresh))
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// The phone's latest board, sent in the background after each snapshot.
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let raw = applicationContext["board"] as? [String: Any] else { return }
        let fresh = WatchBoard(message: raw)
        Task { @MainActor in self.take(fresh) }
    }

    /// A complication update the phone pushed with priority.
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let raw = userInfo["complication"] as? [String: Any], let data = ComplicationData(dictionary: raw) else { return }
        ComplicationStore.save(data)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Approve or Deny on a card; the card goes once the phone confirms.
    func answer(_ approval: Approval, ok: Bool) async {
        switch await send(.answer(id: approval.id, ok: ok)) {
        case .done:
            approvals.removeAll { $0.id == approval.id }
            WKInterfaceDevice.current().play(ok ? .success : .click)
        case .problem(let words):
            problem = words
        default:
            break
        }
    }

    /// One request to the phone. Words the usual failures for a small screen.
    private func send(_ request: WatchRequest) async -> WatchReply {
        let session = WCSession.default
        guard session.activationState == .activated else {
            return .problem("Still connecting to your iPhone. Try again in a moment.")
        }
        guard session.isReachable else {
            unreachable = true
            return .problem("iPhone not reachable")
        }
        unreachable = false
        return await withCheckedContinuation { continuation in
            session.sendMessage(request.message, replyHandler: { message in
                continuation.resume(returning: WatchReply(message: message))
            }, errorHandler: { error in
                continuation.resume(returning: .problem(error.localizedDescription))
            })
        }
    }

    /// Once connected, look for approvals.
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in await self.refreshApprovals() }
    }
}

struct WatchHome: View {
    @ObservedObject var model: WatchModel

    /// Scrolls: orb and Ask on top, then the answer, then approvals.
    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                OrbView(state: model.phase == .asking ? .thinking : .listening, size: 70)
                    .opacity(model.phase == .asking ? 1 : 0.8)
                if model.phase == .asking {
                    Text("Asking your iPhone…").font(.footnote).foregroundStyle(Theme.frostDim)
                } else {
                    // Tapping offers dictation first, so it's one tap and talk.
                    TextFieldLink(prompt: Text("Ask Jarvis")) {
                        Label("Ask", systemImage: "mic.fill")
                            .frame(maxWidth: .infinity)
                    } onSubmit: { text in
                        Task { await model.ask(text) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.glacier)
                    .foregroundStyle(Theme.basalt)
                    .shadow(color: model.askNudge ? Theme.glacier.opacity(0.8) : .clear, radius: 8)
                }
                if !model.board.notices.isEmpty || !model.board.tasks.isEmpty {
                    // The dots, as on the phone: orange need you, blue running.
                    Button { model.showingNotices = true } label: {
                        HStack(spacing: 6) {
                            if !model.board.notices.isEmpty {
                                Circle().fill(OrbView.noticeOrange(onLight: false)).frame(width: 8, height: 8)
                                Text("\(model.board.notices.count)")
                            }
                            if !model.board.tasks.isEmpty {
                                Circle().fill(OrbView.taskBlue(onLight: false)).frame(width: 8, height: 8)
                                Text("\(model.board.tasks.count)")
                            }
                            Text("Needs you").foregroundStyle(Theme.frostDim)
                        }
                        .font(.footnote.weight(.semibold))
                    }
                }
                // Today's calories, a small line when Jarvis has them.
                if let food = model.board.nutrition, food.isToday() {
                    Label("\(food.leftWords) · \(food.ofGoalWords)", systemImage: "fork.knife")
                        .font(.caption2)
                        .foregroundStyle(Theme.frostDim)
                }
                if let problem = model.problem {
                    Text(problem).font(.footnote).foregroundStyle(Theme.rose).multilineTextAlignment(.center)
                    if model.unreachable {
                        Button("Try again") {
                            model.problem = nil
                            Task {
                                if !model.question.isEmpty && model.answer.isEmpty { await model.ask(model.question) } else { await model.refreshApprovals() }
                            }
                        }
                    }
                }
                if !model.question.isEmpty {
                    Text(model.question).font(.footnote).foregroundStyle(Theme.frostDim).frame(maxWidth: .infinity, alignment: .leading)
                }
                if !model.answer.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        if let who = model.model {
                            Text(ModelWording.label(who))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(ModelWording.isClaude(who) ? Theme.ember : Theme.glacier)
                        }
                        Text(model.answer)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(model.approvals) { approval in
                    approvalCard(approval)
                }
            }
        }
        .task { await model.refreshApprovals() }
        .sheet(isPresented: $model.showingNotices) {
            NoticesList(model: model)
        }
    }

    /// "Needs your OK", what he wants, Deny and Approve.
    private func approvalCard(_ approval: Approval) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Needs your OK").font(.caption2.weight(.semibold)).foregroundStyle(Theme.ember)
            Text(ApprovalWording.toolLabel(approval.tool)).font(.headline)
            Text(ApprovalWording.readableSummary(approval.summary)).font(.footnote).foregroundStyle(Theme.frostDim)
            HStack {
                Button("Deny") { Task { await model.answer(approval, ok: false) } }
                Button("Approve") { Task { await model.answer(approval, ok: true) } }
                    .tint(Theme.ember)
            }
        }
        .padding(10)
        .glassPanel(tint: Theme.ember)
    }
}

/// The notices (orange) and tasks Jarvis is chasing (blue), newest first.
/// A notice that needs an answer has Approve and Deny; any other clears
/// with a tap, everywhere.
struct NoticesList: View {
    @ObservedObject var model: WatchModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if model.board.notices.isEmpty && model.board.tasks.isEmpty {
                    Text("All caught up.").foregroundStyle(Theme.frostDim)
                }
                ForEach(model.board.notices) { notice in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Circle().fill(OrbView.noticeOrange(onLight: false)).frame(width: 8, height: 8)
                            Text(notice.title).font(.footnote.weight(.semibold)).lineLimit(3)
                        }
                        if !notice.body.isEmpty {
                            Text(notice.body).font(.caption2).foregroundStyle(Theme.frostDim).lineLimit(3)
                        }
                        if notice.approvalId != nil {
                            HStack {
                                Button("Deny") { Task { await model.answer(notice, ok: false) } }
                                Button("Approve") { Task { await model.answer(notice, ok: true) } }
                                    .tint(Theme.ember)
                            }
                        } else {
                            Button(notice.source == "reminder" ? "Got it" : "Clear") { Task { await model.clear(notice) } }
                                .font(.footnote)
                        }
                    }
                }
                ForEach(Array(model.board.tasks.enumerated()), id: \.offset) { _, task in
                    HStack(spacing: 6) {
                        Circle().fill(OrbView.taskBlue(onLight: false)).frame(width: 8, height: 8)
                        VStack(alignment: .leading) {
                            Text(task.label).font(.footnote).lineLimit(2)
                            TimelineView(.periodic(from: .now, by: 1)) { tick in
                                Text(Orbit.elapsed(since: task.startedAt, now: tick.date) ?? "Running")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(Theme.frostDim)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Needs you")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

#if DEBUG
/// Each complication at its size, with sample data (`-complicationGallery`),
/// for screenshots without a real watch face.
struct ComplicationGallery: View {
    private let entry = JarvisEntry(date: Date(), data: ComplicationData(needCount: 2, runningCount: 1, nextTitle: "Volleyball at the Y", nextAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(42 * 60)), nutrition: ComplicationGallery.sampleFood, updated: Date()))

    /// Today's sample calories (Pacific date, so it counts as today).
    static var sampleFood: Nutrition {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let p = c.dateComponents([.year, .month, .day], from: Date())
        return Nutrition(date: String(format: "%04d-%02d-%02d", p.year!, p.month!, p.day!), eaten: 1180, goal: 1750, left: 570, protein: 96, proteinGoal: 140)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    ZStack { Circle().fill(.white.opacity(0.12)); OrbGlyph() }.frame(width: 50, height: 50)
                    ZStack { Circle().fill(.white.opacity(0.12)); NeedsView(entry: entry, family: .accessoryCircular) }.frame(width: 50, height: 50)
                }
                NeedsView(entry: entry, family: .accessoryRectangular)
                    .padding(8).frame(height: 70).background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.12)))
                NextView(entry: entry, family: .accessoryRectangular)
                    .padding(8).frame(height: 70).background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.12)))
                HStack(spacing: 12) {
                    CaloriesView(entry: entry, family: .accessoryCircular).frame(width: 50, height: 50)
                    CaloriesView(entry: entry, family: .accessoryRectangular)
                        .padding(6).frame(height: 70).background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.12)))
                }
                NeedsView(entry: entry, family: .accessoryInline).font(.footnote)
                CaloriesView(entry: entry, family: .accessoryInline).font(.footnote)
                NextView(entry: entry, family: .accessoryInline).font(.footnote)
            }
        }
    }
}
#endif

