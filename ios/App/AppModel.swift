// The app's shell state: which server, which tab, whether the PC answered
// last time. Chat and Today keep their own models.
import Combine
import SwiftUI
import JarvisKit

/// The tabs along the bottom (a sidebar on iPad).
enum AppTab: Hashable {
    case chat
    case talk
    case today
}

@MainActor
final class AppModel: ObservableObject {
    private static let serverKey = "jarvis.server"

    /// The home page's address. Saved, so a change in Settings sticks.
    @Published var server: String {
        didSet { UserDefaults.standard.set(server, forKey: Self.serverKey) }
    }
    @Published var tab: AppTab = .chat
    @Published var showSettings = false
    /// nil until the first request; then whether the PC answered.
    @Published var reachable: Bool?

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
}
