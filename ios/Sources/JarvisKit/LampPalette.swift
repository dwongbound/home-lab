// The Apple TV's colours, measured (Dylan, 2026-11-17: "the contrast isn't
// too great during the day … the background and text are both white").
// Every colour the always-on screen draws is worked out here from the sun
// lamp, and checked with the WCAG contrast formula against the actual sky
// and panel behind it, so the screen reads from across the bedroom at every
// moment of the day, mid-sunrise included. The targets:
//   7:1   text that carries information (clock, headline, panel rows)
//   4.5:1 dim secondary text (date, captions, the greeting's body)
//   3:1   icons, page dots and panel edges
// Opaque colours throughout: text dimmed with opacity can't be measured.
import Foundation

/// A colour as sRGB components, 0…1.
public struct RGB: Equatable, Sendable {
    public let r: Double, g: Double, b: Double

    public init(_ r: Double, _ g: Double, _ b: Double) {
        self.r = r; self.g = g; self.b = b
    }

    /// WCAG relative luminance (0 black … 1 white).
    public var luminance: Double {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    /// Part way to `other`: 0 is self, 1 is other.
    public func mixed(with other: RGB, _ t: Double) -> RGB {
        RGB(r + (other.r - r) * t, g + (other.g - g) * t, b + (other.b - b) * t)
    }

    /// The WCAG contrast ratio between two colours (1 … 21).
    public func contrast(with other: RGB) -> Double {
        let a = luminance, b = other.luminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// The lowest contrast against any of `backgrounds`.
    public func worstContrast(against backgrounds: [RGB]) -> Double {
        backgrounds.map(contrast(with:)).min() ?? 21
    }

    public static let white = RGB(1, 1, 1)
    public static let black = RGB(0, 0, 0)
}

/// Every colour of the TV's always-on screen at one moment.
public struct LampPalette: Equatable, Sendable {
    /// The sky gradient's two ends.
    public let skyTop: RGB, skyBottom: RGB
    /// The panels' surface and their edge.
    public let panel: RGB, panelEdge: RGB
    /// Primary text, dim text, the blue for times, and icons.
    public let ink: RGB, inkDim: RGB, accent: RGB
    /// Warm icons (the sun, Jarvis's offers) and alerts.
    public let warm: RGB
    /// Problems (Jarvis can't be reached).
    public let alert: RGB
    /// The inactive page dot.
    public let dot: RGB
    /// True when the ink is dark (the sky is bright).
    public let darkInk: Bool

    /// The minimum ratios, as above.
    public static let textTarget = 7.0, dimTarget = 4.5, markTarget = 3.0

    /// Everything text can sit on: both ends of the sky and the panel.
    public var backgrounds: [RGB] { [skyTop, skyBottom, panel] }

    // The two inks. Near-black warm ink by day (not pure black, which
    // vibrates on a bright screen); Jarvis's frost white by night.
    static let dayInk = RGB(0.10, 0.09, 0.08)
    static let nightInk = RGB(0xf2 / 255.0, 0xef / 255.0, 0xe9 / 255.0)
    // Full-strength accents for each polarity.
    static let dayAccent = RGB(0.05, 0.25, 0.47), nightAccent = RGB(0x8e / 255.0, 0xc5 / 255.0, 0xea / 255.0)
    static let dayWarm = RGB(0.55, 0.30, 0.02), nightWarm = RGB(0xe8 / 255.0, 0xb0 / 255.0, 0x6a / 255.0)
    static let dayAlert = RGB(0.62, 0.10, 0.16), nightAlert = RGB(0xf0 / 255.0, 0x91 / 255.0, 0x9a / 255.0)

    /// The margin over each target. Measured on real screenshots, small
    /// text's anti-aliased strokes never reach their full colour and come in
    /// about half a point under the maths, so every colour aims a point high.
    static let margin = 1.0

    /// The palette for the lamp right now.
    public static func at(_ lamp: SunLampState) -> LampPalette {
        var top = sky(lamp, top: true), bottom = sky(lamp, top: false)
        let dark = prefersDarkInk(top: top, bottom: bottom)

        // Mid-sunrise and mid-sunset the sky passes through a middle grey
        // amber where neither ink reaches its target. Through that stretch
        // the sky is nudged away from the ink until every full-strength
        // colour does: lighter behind dark ink, darker behind light ink.
        // Small, and only for those minutes.
        let full = dark
            ? (ink: dayInk, accent: dayAccent, warm: dayWarm, alert: dayAlert)
            : (ink: nightInk, accent: nightAccent, warm: nightWarm, alert: nightAlert)
        let away = dark ? RGB.white : RGB.black
        func passes(_ sky: [RGB]) -> Bool {
            full.ink.worstContrast(against: sky) >= textTarget + margin + 0.5
                && full.accent.worstContrast(against: sky) >= textTarget + margin + 0.5
                && full.alert.worstContrast(against: sky) >= dimTarget + margin + 0.5
                && full.warm.worstContrast(against: sky) >= markTarget + margin + 0.5
        }
        var nudge = 0.0
        while !passes([top, bottom, surface(dark, top, bottom)]), nudge < 1 {
            nudge += 0.02
            top = sky(lamp, top: true).mixed(with: away, nudge)
            bottom = sky(lamp, top: false).mixed(with: away, nudge)
        }

        // Panels: a real surface by day (near-white, so rows sit on paper,
        // not on more sky); a faint lift by night, like the glass.
        let lighter = top.luminance > bottom.luminance ? top : bottom
        let darker = top.luminance > bottom.luminance ? bottom : top
        let panel = surface(dark, top, bottom)
        let behind = [top, bottom, panel]
        let skyOnly = [top, bottom]

        // The weakest colour toward `goal` that still meets `target`: it
        // starts from the sky's own colour and moves toward the goal. At
        // night that keeps the screen as dim as it can be (a bedroom); by
        // day it gives the secondary greys.
        func solve(_ goal: RGB, _ target: Double, against: [RGB] = behind) -> RGB {
            let start = dark ? lighter : darker
            var t = 0.0
            while t < 1 {
                let candidate = start.mixed(with: goal, t)
                if candidate.worstContrast(against: against) >= target + margin { return candidate }
                t += 0.01
            }
            return goal
        }

        // By day the information colours are full strength (near-black
        // reads best from the couch); at night each is dimmed to its target.
        let ink = dark ? full.ink : solve(full.ink, textTarget)
        let accent = dark ? full.accent : solve(full.accent, textTarget)
        let warm = dark ? full.warm : solve(full.warm, markTarget)
        let alert = dark ? full.alert : solve(full.alert, dimTarget)
        // Secondary text a clear step down from the ink, well over 4.5:1.
        let inkDim = solve(full.ink, dimTarget + (dark ? 0.5 : 0))
        // Edges and dots only have to show against the sky beside them.
        let edge = solve(full.ink, markTarget, against: skyOnly)
        let dot = solve(full.ink, markTarget + (dark ? 0.5 : 0), against: skyOnly)
        return LampPalette(
            skyTop: top, skyBottom: bottom, panel: panel, panelEdge: edge,
            ink: ink, inkDim: inkDim, accent: accent, warm: warm, alert: alert, dot: dot, darkInk: dark
        )
    }

    /// The panels' surface: near-white paper by day, a faint lift by night.
    static func surface(_ dark: Bool, _ top: RGB, _ bottom: RGB) -> RGB {
        let lighter = top.luminance > bottom.luminance ? top : bottom
        let darker = top.luminance > bottom.luminance ? bottom : top
        return dark ? lighter.mixed(with: RGB(1, 0.99, 0.97), 0.75) : darker.mixed(with: .white, 0.07)
    }

    /// Dark ink when it beats light ink on the sky's worst end: the text
    /// colour swaps exactly at the crossover, not at a fixed brightness.
    static func prefersDarkInk(top: RGB, bottom: RGB) -> Bool {
        dayInk.worstContrast(against: [top, bottom]) >= nightInk.worstContrast(against: [top, bottom])
    }

    /// One end of the sky: near-black at night, deep red to amber to gold
    /// through dawn, a warm white daylight sky by day, amber back to dark at
    /// dusk. (Moved here from the TV app so the contrast can be checked.)
    public static func sky(_ lamp: SunLampState, top: Bool) -> RGB {
        let b = lamp.brightness, w = lamp.warmth
        let night = top ? RGB(0.02, 0.025, 0.04) : RGB(0.035, 0.045, 0.07)
        let day = top ? RGB(0.86, 0.91, 0.96) : RGB(0.97, 0.94, 0.88)
        // Warm runs deep red when dim, amber, then gold as it brightens.
        let lit = min(1, b * 3)
        let warm = RGB(min(1, 0.55 + b * 0.5) * lit, (0.12 + b * 0.62) * lit, (0.04 + b * 0.32) * lit)
        let glow = w * (top ? 0.75 : 1)
        return night.mixed(with: day, b).mixed(with: warm, glow)
    }
}
