// Long text on the Apple TV (Dylan, 2026-11-18: "if there's a long message
// that doesn't fit in a section and it's maxed out on the screen, it should
// scroll slowly inside the panel"). Only text that overflows its panel
// moves: a pause at the top, a calm reading-pace scroll, a pause at the
// bottom, a quick ease back up, again. A rotating card stays up until it
// has scrolled through once.
import Foundation

public enum AutoScroll {
    /// Seconds held at the top before scrolling, and at the bottom after.
    public static let holdTop: Double = 3
    public static let holdBottom: Double = 3
    /// Reading pace, points per second.
    public static let speed: Double = 24
    /// Seconds to ease back to the top.
    public static let back: Double = 0.8

    /// One full cycle for `overflow` points of hidden text (0 = no scroll).
    public static func cycleSeconds(overflow: Double) -> Double {
        guard overflow > 0.5 else { return 0 }
        return holdTop + overflow / speed + holdBottom + back
    }

    /// How far up the text has moved at `t` seconds since the card appeared.
    public static func offset(at t: Double, overflow: Double) -> Double {
        let cycle = cycleSeconds(overflow: overflow)
        guard cycle > 0 else { return 0 }
        let x = t.truncatingRemainder(dividingBy: cycle)
        let scroll = overflow / speed
        if x < holdTop { return 0 }
        if x < holdTop + scroll { return (x - holdTop) * speed }
        if x < holdTop + scroll + holdBottom { return overflow }
        let p = min(1, (x - holdTop - scroll - holdBottom) / back)
        return overflow * (1 - p * p * (3 - 2 * p))
    }

    /// How long a rotating card stays up: its turn, or long enough to scroll
    /// through once (up to the bottom pause), whichever is longer.
    public static func cardSeconds(turn: Double, overflow: Double) -> Double {
        let cycle = cycleSeconds(overflow: overflow)
        return max(turn, cycle > 0 ? cycle - back : 0)
    }
}
