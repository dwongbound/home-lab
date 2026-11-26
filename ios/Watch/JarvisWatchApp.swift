// Jarvis on Apple Watch (Dylan, 2026-11-26): three pages. Home is the
// phone's orb with its dots, the words under it, and Talk; holding the orb
// talks while the finger is down. Swipe right for Actions (things at home
// to switch), left for Info (diet, sleep, the PC). Tailscale doesn't run on
// the Watch, so everything goes through the iPhone app (WatchBridge),
// which must be nearby; the phone app doesn't need to be open.
import SwiftUI
import WatchConnectivity
import WatchKit
import WidgetKit
import JarvisKit

@main
struct JarvisWatchApp: App {
    @StateObject private var model = WatchModel()

    /// Three pages: Actions, Home (the orb and Talk), Info.
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
                // Complications open the app here: jarvis://ask (Talk), jarvis://notices.
                .onOpenURL { url in model.open(url) }
            #endif
        }
    }
}

@MainActor
final class WatchModel: NSObject, ObservableObject, WCSessionDelegate {
    @Published var problem: String?
    /// Notices, tasks, diet, sleep, the PC and the house, from the phone.
    @Published private(set) var board = WatchBoard()
    /// The notices list is open (a complication or the Info page opened it).
    @Published var showingNotices = false
    /// Which page is showing: 0 Actions, 1 Home, 2 Info.
    @Published var page = 1
    let talk = WatchTalk()

    /// Starts the session with the phone.
    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    /// Asks the phone for the latest board.
    func refresh() async {
        if case .board(let fresh) = await send(.board) { take(fresh) }
    }

    /// Clears a notice everywhere (through the phone).
    func clear(_ notice: WatchNotice) async {
        board.notices.removeAll { $0.id == notice.id }
        if case .problem(let words) = await send(.clear([notice.id])) { problem = words }
        await refresh()
    }

    /// Approve or Deny a notice's approval, then clear it.
    func answer(_ notice: WatchNotice, ok: Bool) async {
        guard let id = notice.approvalId else { return }
        if case .problem(let words) = await send(.answer(id: id, ok: ok)) { problem = words; return }
        WKInterfaceDevice.current().play(ok ? .success : .click)
        await clear(notice)
    }

    /// Flips a light, switch, fan or TV; shown flipped at once, put back if it fails.
    func flip(_ device: WatchDevice) async {
        guard let index = board.devices.firstIndex(of: device) else { return }
        board.devices[index].on.toggle()
        WKInterfaceDevice.current().play(.click)
        if case .problem(let words) = await send(.control(entity: device.id, command: device.command)) {
            problem = words
            if let again = board.devices.firstIndex(where: { $0.id == device.id }) { board.devices[again].on = device.on }
            WKInterfaceDevice.current().play(.failure)
        }
    }

    /// A complication's link: open the notices, or start Talk.
    func open(_ url: URL) {
        switch url.host {
        case "notices": showingNotices = true
        case "ask":
            page = 1
            Task { await talk.start() }
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

    /// Talk: Jarvis's events, or word that the phone's line closed.
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let text = message["talk"] as? String
        let closed = message["talkClosed"] != nil
        Task { @MainActor in
            if let text { self.talk.event(text) }
            if closed { self.talk.lineClosed() }
        }
    }

    /// Talk: a piece of Jarvis's voice.
    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        Task { @MainActor in self.talk.play(messageData) }
    }

    /// One request to the phone. Words the usual failures for a small screen.
    private func send(_ request: WatchRequest) async -> WatchReply {
        let session = WCSession.default
        guard session.activationState == .activated else {
            return .problem("Still connecting to your iPhone. Try again in a moment.")
        }
        guard session.isReachable else { return .problem("iPhone not reachable") }
        return await withCheckedContinuation { continuation in
            session.sendMessage(request.message, replyHandler: { message in
                continuation.resume(returning: WatchReply(message: message))
            }, errorHandler: { error in
                continuation.resume(returning: .problem(error.localizedDescription))
            })
        }
    }

    /// Once connected, fetch the board.
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in await self.refresh() }
    }
}

/// The three pages, Home in the middle.
struct WatchHome: View {
    @ObservedObject var model: WatchModel

    var body: some View {
        TabView(selection: $model.page) {
            ActionsPage(model: model).tag(0)
            TalkPage(model: model, talk: model.talk).tag(1)
            InfoPage(model: model).tag(2)
        }
        .tabViewStyle(.page)
        .task { await model.refresh() }
        .sheet(isPresented: $model.showingNotices) { NoticesList(model: model) }
    }
}

/// Home: the orb, what's happening, and Talk (Mute and End during a call).
struct TalkPage: View {
    @ObservedObject var model: WatchModel
    @ObservedObject var talk: WatchTalk

    var body: some View {
        VStack(spacing: 6) {
            OrbView(state: mood, size: 92, orbit: model.board.orbit, tappable: false, dim: talk.phase == .off ? 0.8 : 1)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                // Hold to talk; a quick swipe still turns the page.
                .onLongPressGesture(minimumDuration: 0.25, maximumDistance: 30) {
                    WKInterfaceDevice.current().play(.start)
                    talk.hold()
                } onPressingChanged: { pressing in
                    if !pressing { talk.release() }
                }
            Text(talk.status)
                .font(.footnote)
                .foregroundStyle(talk.problem == nil ? Theme.frostDim : Theme.rose)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            if talk.phase == .off {
                Button("Talk") { Task { await talk.start() } }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.glacier)
                    .foregroundStyle(Theme.basalt)
            } else {
                HStack {
                    Button(talk.muted ? "Unmute" : "Mute") { talk.toggleMute() }
                    Button("End") { talk.hangUp() }.tint(Theme.rose)
                }
            }
        }
    }

    /// The orb's look for where the call is.
    private var mood: OrbView.Mood {
        switch talk.phase {
        case .off: return .listening
        case .calling: return .thinking
        case .on:
            if talk.working != nil { return .working }
            switch talk.state {
            case .speaking: return .speaking
            case .thinking: return .thinking
            case .listening, .dozing: return .listening
            }
        }
    }
}

/// Actions: things at home to switch, and the car once Jarvis can reach it.
struct ActionsPage: View {
    @ObservedObject var model: WatchModel

    var body: some View {
        List {
            ForEach(model.board.devices) { device in
                Button { Task { await model.flip(device) } } label: {
                    HStack {
                        Image(systemName: Self.symbol(device.kind)).foregroundStyle(device.on ? Theme.ember : Theme.frostFaint)
                        Text(device.name).lineLimit(1)
                        Spacer()
                        Text(device.on ? "On" : "Off").font(.footnote).foregroundStyle(Theme.frostDim)
                    }
                }
            }
            if model.board.devices.isEmpty {
                Text("Nothing at home to switch yet").foregroundStyle(Theme.frostDim)
            }
            HStack {
                Image(systemName: "car.fill").foregroundStyle(Theme.frostFaint)
                Text("Car: not connected yet").foregroundStyle(Theme.frostDim)
            }
            if let problem = model.problem {
                Text(problem).font(.footnote).foregroundStyle(Theme.rose)
            }
        }
    }

    static func symbol(_ kind: String) -> String {
        switch kind {
        case "light": return "lightbulb.fill"
        case "fan": return "fan.fill"
        case "media": return "tv.fill"
        default: return "power"
        }
    }
}

/// Info: diet, sleep and the PC as rings and bars; a tap opens the details.
struct InfoPage: View {
    @ObservedObject var model: WatchModel
    @State private var open: Detail?

    enum Detail: String, Identifiable { case diet, sleep, pc; var id: String { rawValue } }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Button { open = .diet } label: { DietRings(food: food, size: 62) }
                    Button { open = .sleep } label: { SleepRing(score: model.board.sleepScore, size: 62) }
                }
                .buttonStyle(.plain)
                Button { open = .pc } label: { PCBars(bars: model.board.pc) }
                    .buttonStyle(.plain)
                if !model.board.notices.isEmpty || !model.board.tasks.isEmpty {
                    Button { model.showingNotices = true } label: {
                        HStack(spacing: 6) {
                            Circle().fill(OrbView.noticeOrange(onLight: false)).frame(width: 8, height: 8)
                            Text("\(model.board.notices.count)")
                            Circle().fill(OrbView.taskBlue(onLight: false)).frame(width: 8, height: 8)
                            Text("\(model.board.tasks.count)")
                        }
                        .font(.footnote.weight(.semibold))
                    }
                }
            }
        }
        .sheet(item: $open) { detail in
            NavigationStack {
                ScrollView { details(detail) }
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button { open = nil } label: { Image(systemName: "xmark") }
                                .accessibilityLabel("Close")
                        }
                    }
            }
        }
    }

    /// Today's numbers only; yesterday's ring would mislead.
    private var food: Nutrition? { model.board.nutrition.flatMap { $0.isToday() ? $0 : nil } }

    @ViewBuilder
    private func details(_ detail: Detail) -> some View {
        switch detail {
        case .diet:
            VStack(alignment: .leading, spacing: 6) {
                DietRings(food: food, size: 90).frame(maxWidth: .infinity)
                if let food {
                    Text("\(food.leftWords) · \(food.ofGoalWords)").font(.footnote)
                    macro("Protein", food.protein, food.proteinGoal, Theme.glacier)
                    macro("Fat", food.fat, food.fatGoal, Theme.ember)
                    macro("Carbs", food.carbs, food.carbsGoal, Theme.moss)
                }
            }
        case .sleep:
            VStack(spacing: 6) {
                SleepRing(score: model.board.sleepScore, size: 90)
                if let minutes = model.board.sleepMinutes {
                    Text("\(Int(minutes) / 60)h \(Int(minutes) % 60)m asleep").font(.footnote)
                }
                // The week, oldest on the left.
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(Array(model.board.sleepTrend.reversed().enumerated()), id: \.offset) { _, score in
                        Capsule().fill(SleepRing.color(score)).frame(width: 10, height: max(4, CGFloat(score) * 0.5))
                    }
                }
                .frame(height: 50, alignment: .bottom)
            }
        case .pc:
            VStack(alignment: .leading, spacing: 8) {
                ForEach(model.board.pc, id: \.name) { bar in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(bar.name).font(.footnote)
                        Bar(fraction: bar.usedGb / max(bar.totalGb, 0.1))
                        Text("\(Int(bar.usedGb.rounded())) of \(Int(bar.totalGb.rounded())) GB").font(.caption2).foregroundStyle(Theme.frostDim)
                    }
                }
            }
        }
    }

    /// One macro as a bar with its grams.
    @ViewBuilder
    private func macro(_ name: String, _ value: Double?, _ goal: Double?, _ color: Color) -> some View {
        if let value, let goal, goal > 0 {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(name) \(Int(value.rounded())) of \(Int(goal.rounded())) g").font(.caption2)
                Bar(fraction: value / goal, color: color)
            }
        }
    }
}

/// A ring filled to `fraction`.
struct Ring: View {
    var fraction: Double
    var color: Color
    var width: CGFloat

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.22), lineWidth: width)
            Circle().trim(from: 0, to: min(1, max(0, fraction)))
                .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

/// Calories outside, protein inside, as on the phone's Diet screen.
struct DietRings: View {
    var food: Nutrition?
    var size: CGFloat

    var body: some View {
        let width = size * 0.11
        ZStack {
            Ring(fraction: food?.fraction ?? 0, color: (food?.left ?? 0) < 0 ? Theme.ember : Theme.moss, width: width)
            Ring(fraction: protein, color: Theme.glacier, width: width).padding(width * 1.3)
            Text(food.map { "\(Int($0.left.rounded()))" } ?? "–").font(.system(size: size * 0.2, weight: .semibold).monospacedDigit())
        }
        .frame(width: size, height: size)
    }

    private var protein: Double {
        guard let food, let p = food.protein, let goal = food.proteinGoal, goal > 0 else { return 0 }
        return p / goal
    }
}

/// Last night's score as a ring, coloured by how good it was.
struct SleepRing: View {
    var score: Int?
    var size: CGFloat

    var body: some View {
        ZStack {
            Ring(fraction: Double(score ?? 0) / 100, color: Self.color(score ?? 0), width: size * 0.11)
            Image(systemName: "moon.fill").font(.system(size: size * 0.14)).foregroundStyle(Theme.frostDim).offset(y: -size * 0.17)
            Text(score.map(String.init) ?? "–").font(.system(size: size * 0.22, weight: .semibold).monospacedDigit()).offset(y: size * 0.06)
        }
        .frame(width: size, height: size)
    }

    /// Jarvis's bands: great 85+, good 70+, fair 50+, poor.
    static func color(_ score: Int) -> Color {
        if score >= 85 { return Theme.moss }
        if score >= 70 { return Theme.glacier }
        if score >= 50 { return Theme.ember }
        return Theme.rose
    }
}

/// The PC's memory, graphics card and disks as three thin bars.
struct PCBars: View {
    var bars: [WatchBar]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("PC", systemImage: "desktopcomputer").font(.caption2).foregroundStyle(Theme.frostDim)
            ForEach(bars.prefix(3), id: \.name) { bar in
                Bar(fraction: bar.usedGb / max(bar.totalGb, 0.1))
            }
            if bars.isEmpty { Text("No reading").font(.caption2).foregroundStyle(Theme.frostFaint) }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.08)))
    }
}

/// One horizontal bar; past 90% it turns orange.
struct Bar: View {
    var fraction: Double
    var color: Color = Theme.glacier

    var body: some View {
        GeometryReader { box in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.12))
                Capsule().fill(fraction > 0.9 ? Theme.ember : color).frame(width: box.size.width * min(1, max(0, fraction)))
            }
        }
        .frame(height: 6)
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
                        // No browser on the Watch: the report is read on the iPhone.
                        if notice.isReport {
                            Text(Reports.elsewhere).font(.caption2).foregroundStyle(Theme.frostDim)
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
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

