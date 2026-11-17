// The Talk call's Live Activity, shared by the app (which starts, updates
// and ends it) and the widget extension (which draws it in the Dynamic
// Island and on the Lock Screen). Mute and End on the expanded island are
// App Intents that run in the app, where the call lives.
import ActivityKit
import AppIntents
import Foundation

/// What the island shows about a Talk call.
struct TalkActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// "listening", "thinking", "working" (a slow lookup), "speaking".
        var state: String
        var muted: Bool
        /// How loud the voice is right now, 0 (quiet) … 3 (loud): the mini
        /// orb swells with it. Sent at most about once a second, since iOS
        /// limits how often an app may update the island.
        var pulse: Int = 0
        /// Counts up with each update, so the orb's ring of dots turns a
        /// little every time and iOS animates the step.
        var beat: Int = 0

        /// "Listening", "Thinking", "Speaking", or "Muted".
        var words: String {
            if muted && state == "listening" { return "Muted" }
            return state.prefix(1).uppercased() + state.dropFirst()
        }
    }
}

/// The two buttons on the expanded island, as one message to the call.
enum TalkActivityAction {
    case toggleMute
    case end
}

/// Where the intents reach the call. The app sets `handler` at launch; in
/// the widget extension it stays nil (the intents run in the app).
@MainActor
enum TalkActivityBridge {
    static var handler: ((TalkActivityAction) -> Void)?
}

/// Mute or unmute the call from the Dynamic Island.
struct ToggleTalkMuteIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Mute or unmute Jarvis"

    @MainActor
    func perform() async throws -> some IntentResult {
        TalkActivityBridge.handler?(.toggleMute)
        return .result()
    }
}

/// Hang up the call from the Dynamic Island.
struct EndTalkIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "End the call with Jarvis"

    @MainActor
    func perform() async throws -> some IntentResult {
        TalkActivityBridge.handler?(.end)
        return .result()
    }
}
