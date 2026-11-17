// The Apple TV's background as a sun lamp (Dylan, 2026-11-17): it follows
// the real sunrise and sunset. Near-black at night (it's a bedroom TV),
// warming from deep red through amber to gold from half an hour before
// sunrise to bright daylight just after it, bright all day, then amber and
// fading to dark over about 45 minutes around sunset. Continuous: every
// value is a pure function of the clock, so it never jumps. The same four
// phases as the page's painted sky (src/lib/sky.ts), timed by the sun.
import Foundation

/// How the lamp looks at one moment.
public struct SunLampState: Equatable, Sendable {
    public enum Phase: String, Sendable { case night, dawn, day, dusk }
    public let phase: Phase
    /// 0 = night (near-black) … 1 = full daylight.
    public let brightness: Double
    /// 0 = neutral … 1 = deepest red/amber.
    public let warmth: Double

    public init(phase: Phase, brightness: Double, warmth: Double) {
        self.phase = phase
        self.brightness = brightness
        self.warmth = warmth
    }
}

public enum SunLamp {
    /// Minutes before sunrise the dawn starts, and after it, full day.
    public static let dawnLead: Double = 30, dawnTail: Double = 20
    /// Minutes before sunset the dusk starts, and after it, full night.
    public static let duskLead: Double = 15, duskTail: Double = 30
    /// How bright the night is: dim enough not to light the room.
    public static let nightBrightness: Double = 0.03

    /// The lamp at `now`, from the sunrise and sunset (any day: each is moved
    /// to its nearest occurrence to `now`).
    public static func state(now: Date, sunrise: Date, sunset: Date) -> SunLampState {
        let rise = nearest(sunrise, to: now), set = nearest(sunset, to: now)
        let minutes = { (date: Date) in now.timeIntervalSince(date) / 60 }
        let sinceRise = minutes(rise), sinceSet = minutes(set)

        if sinceRise >= -dawnLead && sinceRise <= dawnTail {
            let p = smooth((sinceRise + dawnLead) / (dawnLead + dawnTail))
            return SunLampState(phase: .dawn, brightness: nightBrightness + (1 - nightBrightness) * p, warmth: 1 - p)
        }
        if sinceSet >= -duskLead && sinceSet <= duskTail {
            let p = smooth((sinceSet + duskLead) / (duskLead + duskTail))
            // Warms to amber early, then fades with the light.
            return SunLampState(phase: .dusk, brightness: 1 - (1 - nightBrightness) * p, warmth: min(1, p * 1.8) * (1 - p * 0.3))
        }
        // Between the two: day if the last event was sunrise, else night.
        let lastRise = sinceRise > 0 ? sinceRise : sinceRise + 1440
        let lastSet = sinceSet > 0 ? sinceSet : sinceSet + 1440
        return lastRise < lastSet
            ? SunLampState(phase: .day, brightness: 1, warmth: 0)
            : SunLampState(phase: .night, brightness: nightBrightness, warmth: 0)
    }

    /// A rough sunrise and sunset for West Los Angeles on `date`'s day, for
    /// when the snapshot has none (NOAA's simple solar formula, ±5 min).
    public static func estimate(for date: Date, latitude: Double = 34.05, longitude: Double = -118.44) -> (sunrise: Date, sunset: Date) {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let day = Double(utc.ordinality(of: .day, in: .year, for: date) ?? 1)
        let gamma = 2 * Double.pi / 365 * (day - 1)
        let eqTime = 229.18 * (0.000075 + 0.001868 * cos(gamma) - 0.032077 * sin(gamma) - 0.014615 * cos(2 * gamma) - 0.040849 * sin(2 * gamma))
        let decl = 0.006918 - 0.399912 * cos(gamma) + 0.070257 * sin(gamma) - 0.006758 * cos(2 * gamma) + 0.000907 * sin(2 * gamma) - 0.002697 * cos(3 * gamma) + 0.00148 * sin(3 * gamma)
        let lat = latitude * .pi / 180
        let ha = acos(cos(90.833 * .pi / 180) / (cos(lat) * cos(decl)) - tan(lat) * tan(decl)) * 180 / .pi
        let midnight = utc.startOfDay(for: date)
        let riseMinutes = 720 - 4 * (longitude + ha) - eqTime
        let setMinutes = 720 - 4 * (longitude - ha) - eqTime
        return (midnight.addingTimeInterval(riseMinutes * 60), midnight.addingTimeInterval(setMinutes * 60))
    }

    /// `event` moved by whole days to the one nearest `now`.
    static func nearest(_ event: Date, to now: Date) -> Date {
        let days = (now.timeIntervalSince(event) / 86_400).rounded()
        return event.addingTimeInterval(days * 86_400)
    }

    /// Smoothstep: eases in and out, so the light never lurches.
    static func smooth(_ x: Double) -> Double {
        let t = min(max(x, 0), 1)
        return t * t * (3 - 2 * t)
    }
}
