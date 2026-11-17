// The Dynamic Island's mini orb can't animate continuously: iOS only
// animates between updates, and budgets how often an app may send them.
// So it moves in steps: at most one update a second, each turning the ring
// a beat and setting how swollen it is (0…3) from the voice that matters.
// Skips an update when nothing would change (paused, muted, quiet and not
// turning), and sends none at all with Reduce Motion on.
import Foundation

public struct IslandPose: Equatable, Sendable {
    /// How loud the voice is, 0 (quiet) … 3 (loud).
    public private(set) var pulse = 0
    /// Counts up with each update; the ring turns a step per beat.
    public private(set) var beat = 0
    private var last = Date.distantPast

    public init() {}

    /// One tick. `turning` is true while the call is live (listening,
    /// thinking, speaking, not muted). Returns true when the island should
    /// get an update with the new pulse and beat.
    public mutating func tick(level: Double, turning: Bool, now: Date, reduceMotion: Bool) -> Bool {
        guard !reduceMotion, now.timeIntervalSince(last) >= 1 else { return false }
        let step = turning ? min(3, max(0, Int(level * 4))) : 0
        guard turning || step != pulse else { return false }
        pulse = step
        beat += 1
        last = now
        return true
    }
}
