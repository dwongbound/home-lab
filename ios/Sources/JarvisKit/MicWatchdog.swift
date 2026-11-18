// Notices when the Talk line's microphone has quietly died (Dylan,
// 2026-11-18: from 10:54 to 11:02 the line was open but the app sent no
// audio at all, so "that will be all" never reached Jarvis). The audio
// thread reports each buffer here; a timer asks `check` every second. Pure
// logic, so it's tested on any Mac; TalkLine does the restarting.
//
// Dead means: no buffers for a few seconds, or only exact digital zeros
// for a few seconds (a real microphone is never perfectly silent, voice
// processing or not). Mute isn't dead (the tap still runs; the app sends
// zeros on purpose), and neither is dozing, but a stopped tap is dead in
// both, since "Hey Jarvis" needs the microphone too.
import Foundation

public struct MicWatchdog: Equatable, Sendable {
    /// What the line should do now.
    public enum Verdict: Equatable, Sendable {
        case fine
        /// Tear the engine down and start it again.
        case restart
        /// Tried and it didn't come back: say so on screen.
        case giveUp
    }

    /// Seconds with no buffers, or only zeros, before it counts as dead.
    public static let deadAfter: TimeInterval = 4
    /// Restarts tried before giving up.
    public static let maxTries = 2
    /// Seconds a restart is given to bring buffers back before the next one.
    public static let settleTime: TimeInterval = 3

    /// The last buffer of any kind.
    public private(set) var lastBuffer: Date
    /// The last buffer with any sound in it (not all exact zeros).
    public private(set) var lastSound: Date
    /// Restarts tried since the microphone last worked.
    public private(set) var tries = 0
    /// When the last restart was tried.
    public private(set) var restartedAt: Date?
    /// Paused on purpose (an audio interruption is under way): no verdicts.
    public var held = false

    /// Starts the clock when the line opens.
    public init(now: Date = Date()) {
        lastBuffer = now
        lastSound = now
    }

    /// One buffer from the tap. `silent` is true when every sample is exactly zero.
    public mutating func heard(silent: Bool, at now: Date = Date()) {
        lastBuffer = now
        if !silent {
            lastSound = now
            tries = 0
            restartedAt = nil
        }
    }

    /// True when every sample is exactly zero (digital silence, not a quiet room).
    public static func isDigitalSilence(_ samples: UnsafeBufferPointer<Float>) -> Bool {
        for sample in samples where sample != 0 { return false }
        return true
    }

    /// Whether the microphone looks dead right now.
    public func isDead(now: Date = Date()) -> Bool {
        now.timeIntervalSince(lastBuffer) >= Self.deadAfter || now.timeIntervalSince(lastSound) >= Self.deadAfter
    }

    /// What to do. A restart is given `settleTime` to work before another.
    public func check(now: Date = Date()) -> Verdict {
        guard !held, isDead(now: now) else { return .fine }
        if let restartedAt, now.timeIntervalSince(restartedAt) < Self.settleTime { return .fine }
        return tries >= Self.maxTries ? .giveUp : .restart
    }

    /// A restart is being tried.
    public mutating func restarting(at now: Date = Date()) {
        tries += 1
        restartedAt = now
    }

    /// Start again from scratch (Dylan tapped "restart", or the line reopened).
    public mutating func reset(now: Date = Date()) {
        self = MicWatchdog(now: now)
    }
}
