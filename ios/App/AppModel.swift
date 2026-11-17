// The app's shell state: which server, which tab, whether the PC answered
// last time. Chat and Today keep their own models.
import Combine
import LocalAuthentication
import SwiftUI
import JarvisKit

/// The tabs along the bottom (a sidebar on iPad).
enum AppTab: Hashable, CaseIterable {
    case chat
    case talk
    case today

    /// The tab `step` places along (1 = right), stopping at the ends.
    func neighbour(_ step: Int) -> AppTab {
        let all = Self.allCases
        let index = all.firstIndex(of: self) ?? 0
        return all[min(max(index + step, 0), all.count - 1)]
    }
}

@MainActor
final class AppModel: ObservableObject {
    private static let serverKey = "jarvis.server"

    /// The home page's address. Saved, so a change in Settings sticks.
    @Published var server: String {
        didSet { UserDefaults.standard.set(server, forKey: Self.serverKey) }
    }
    /// Talk first: opening the app goes straight to the voice line (Dylan, 2026-11-17).
    @Published var tab: AppTab = .talk
    @Published var showSettings = false
    /// nil until the first request; then whether the PC answered.
    @Published var reachable: Bool?

    /// Money details stay hidden until Face ID (or the passcode) says it's
    /// Dylan, and hide again whenever the app goes to the background.
    @Published private(set) var moneyUnlocked = false

    let chat = ChatModel()
    let today = TodayModel()
    let talk = TalkModel()
    private var relay: AnyCancellable?

    /// Reads the saved address, or the one the app ships with.
    init() {
        server = UserDefaults.standard.string(forKey: Self.serverKey) ?? JarvisClient.defaultBase.absoluteString
        // The Chat tab's badge counts the chat's waiting approvals, so a
        // change in the chat redraws the tab bar too.
        relay = chat.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        // Mute and End on the Dynamic Island reach the call through here.
        TalkActivityBridge.handler = { [weak self] action in
            guard let self else { return }
            switch action {
            case .toggleMute: self.talk.toggleMute()
            case .end: self.talk.hangUp()
            }
        }
    }

    /// A client for the current address (falls back to the default if the
    /// typed one isn't a URL).
    var client: JarvisClient {
        let base = URL(string: server.trimmingCharacters(in: .whitespaces)) ?? JarvisClient.defaultBase
        return JarvisClient(base: base)
    }

    /// Notes whether the last call reached the PC, for the status line.
    func noteReach(_ error: Error?) {
        if let error = error as? JarvisError, error == .unreachable {
            reachable = false
        } else {
            reachable = true
        }
    }

    /// Start on an offer card: switch to Chat and send its text there.
    func start(_ offer: Offer) {
        tab = .chat
        Task { await chat.send(offer.startText, offerId: offer.id, app: self) }
    }

    /// "Show" on a hidden money card: Face ID, falling back to the passcode.
    func unlockMoney() async {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return }
        let ok = (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Show your money details")) ?? false
        moneyUnlocked = ok
    }

    /// Hides money again (the app went to the background).
    func lockMoney() {
        moneyUnlocked = false
    }
}
