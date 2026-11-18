// The iPhone's half of the Watch app. Tailscale doesn't run on Apple Watch,
// so the Watch sends each ask here over WatchConnectivity; the phone asks
// Jarvis over Tailscale and replies (JarvisKit/WatchRelay.swift).
// iOS wakes the app in the background for a Watch message, so the app
// doesn't need to be open.
import Foundation
import WatchConnectivity
import JarvisKit

final class WatchBridge: NSObject, WCSessionDelegate {
    static let shared = WatchBridge()

    /// Starts listening for the Watch (does nothing on an iPad, which has none).
    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// The client for the address saved in Settings (read fresh each time,
    /// since this can run with no screen up).
    private var client: JarvisClient {
        let saved = UserDefaults.standard.string(forKey: "jarvis.server") ?? ""
        let base = URL(string: saved.trimmingCharacters(in: .whitespaces)) ?? JarvisClient.defaultBase
        if base.host == nil { return JarvisClient() }
        return JarvisClient(base: base)
    }

    /// One request from the Watch: ask the PC, send back what it said.
    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        guard let request = WatchRequest(message: message) else {
            replyHandler(WatchReply.problem("The Watch asked for something this iPhone app doesn’t know. Update both.").message)
            return
        }
        let client = self.client
        Task {
            let reply = await client.handle(request)
            replyHandler(reply.message)
        }
    }

    /// Hands the Watch its board and complication data after each snapshot,
    /// in the background where iOS allows (the latest one wins). No money:
    /// the board carries notices, tasks and what's next only.
    func push(_ snapshot: Snapshot?) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        let board = WatchBoard(snapshot: snapshot)
        let data = ComplicationData(board: board)
        let context: [String: Any] = ["board": board.message, "complication": data.dictionary]
        try? session.updateApplicationContext(context)
        // A complication on the face gets a little budget for prompt updates.
        if session.isComplicationEnabled, session.remainingComplicationUserInfoTransfers > 0 {
            session.transferCurrentComplicationUserInfo(["complication": data.dictionary])
        }
    }

    /// Required; nothing to do once the session is up.
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    /// Required on iOS; nothing to keep between Watches.
    func sessionDidBecomeInactive(_ session: WCSession) {}

    /// A different Watch was paired: listen on the new session.
    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }
}
