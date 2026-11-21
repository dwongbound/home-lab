// What the iPhone app taps under the finger, and when (Dylan, 2026-11-20:
// "incorporate vibrations more in the app to make it more immersive ie when
// switching tabs and wherever else it would be cool").
//
// Apple's restrained style: short and crisp, each one tied to something he
// did or something that finished, never decoration. Every moment is named
// here with its feel, so the whole language is tuned in one place; the app
// plays them through a UIKit sink (App/Haptics.swift). Pure, so the rules
// are unit tested with a recording sink.
import Foundation

/// How a moment feels: UIKit's generators, by name.
public enum HapticFeel: String, Sendable, Equatable {
    case selection, light, medium, soft, rigid, success, warning, error
}

/// The moments that tap.
public enum HapticMoment: String, Sendable, CaseIterable {
    /// A tab chosen in the bar, or a page swipe that commits to the next tab.
    case tab
    /// He sends a message.
    case send
    /// Jarvis's reply starts arriving.
    case replyStarts
    /// The jump-to-newest arrow.
    case jump
    /// A Talk call starts, or he wakes a paused one.
    case callStarts
    /// A call ends or pauses.
    case callEnds
    /// Jarvis heard him and starts thinking (the page's two-note "got it").
    case thinking
    /// Mute or unmute in a call.
    case mute
    /// Approve, Deny, and a new approval card turning up.
    case approve, deny, approvalArrives
    /// A row swiped all the way across (dismiss, unkeep, stop).
    case fullSwipe
    /// A stop request answered.
    case stopped, stopFailed
    /// Keep or unkeep a message; an orbiting dot opened.
    case keep, orbitTap
    /// Run now on a playbook, and how the run went.
    case run, runOK, runFailed
    /// Something failed that he needs to notice.
    case failure

    public var feel: HapticFeel {
        switch self {
        case .tab, .mute, .keep, .orbitTap: return .selection
        case .send, .jump, .run, .callEnds, .fullSwipe: return .light
        case .callStarts: return .medium
        case .replyStarts, .thinking: return .soft
        case .deny: return .rigid
        case .approve, .stopped, .runOK: return .success
        case .approvalArrives: return .warning
        case .stopFailed, .runFailed, .failure: return .error
        }
    }
}

/// Where the feels go: UIKit on the phone, a recorder in the tests.
@MainActor
public protocol HapticSink: AnyObject {
    func play(_ feel: HapticFeel)
}

/// Decides whether a moment plays: never with the Settings switch off,
/// never while the app is in the background, and a failure once per
/// failure, not again for each quiet retry until it has recovered.
@MainActor
public final class HapticGate {
    private let sink: HapticSink
    private let enabled: () -> Bool
    private let active: () -> Bool
    /// Failures already felt, by what failed ("reach", "send"…).
    private var felt: Set<String> = []

    public init(sink: HapticSink, enabled: @escaping () -> Bool, active: @escaping () -> Bool = { true }) {
        self.sink = sink
        self.enabled = enabled
        self.active = active
    }

    /// Plays a moment, if haptics are on and the app is in front.
    public func play(_ moment: HapticMoment) {
        guard enabled(), active() else { return }
        sink.play(moment.feel)
    }

    /// Something failed: felt the first time, quiet while it keeps failing.
    public func failed(_ what: String) {
        guard !felt.contains(what) else { return }
        felt.insert(what)
        play(.failure)
    }

    /// It works again: the next failure is felt.
    public func recovered(_ what: String) {
        felt.remove(what)
    }
}

/// The page swipe's one tick: when he lets go and the pager decides where
/// it lands. A swipe that springs back to the page it started on is no
/// change, so it doesn't tick.
public enum PageCommit {
    /// The page a horizontal offset rests on.
    public static func page(offsetX: Double, width: Double) -> Int {
        guard width > 0 else { return 0 }
        return Int((offsetX / width).rounded())
    }

    /// True when the landing page differs from the page the swipe began on.
    public static func changes(fromX: Double, toX: Double, width: Double) -> Bool {
        page(offsetX: fromX, width: width) != page(offsetX: toX, width: width)
    }
}
