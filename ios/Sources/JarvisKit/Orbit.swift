// The dots that orbit the orb (Dylan, 2026-11-18): "BLUE if there's an
// active thing (another thread or thing Jarvis is chasing down), ORANGE if
// action / notification such as approval or a notification that needs my
// viewing. These dots should look like they're orbiting around the orb,
// going in front and behind it… when it's clicked, all the orbs and the net
// of dots should stop moving and it should tell me what it is." These are
// the rules: what orbits, each dot's own 3D path, the timers, and when
// reading a notice clears it. The iPhone, iPad and TV all draw from here.
import Foundation

/// One dot round the orb: a task Jarvis is running (blue) or an unread
/// notice (orange).
public struct OrbitItem: Equatable, Identifiable, Sendable {
    public enum Kind: Equatable, Sendable { case task, notice }
    public let id: String
    public let kind: Kind
    public let title: String
    public let detail: String
    /// A task's start (ISO), for its timer.
    public let startedAt: String?
    /// The notice behind an orange dot.
    public let notice: Notice?

    /// How bold the dot is: a notice that needs Dylan is brightest and a
    /// little bigger; an FYI a little dimmer; tasks in between.
    public var emphasis: Double {
        switch notice?.kind {
        case .need?: return 1
        case .fyi?: return 0.7
        case .heads?: return 0.85
        case nil: return 0.85
        }
    }
}

/// A dot's orbit: a circle round the orb, tilted and turned its own way.
public struct OrbitPath: Equatable, Sendable {
    /// Distance from the centre, in shell radii.
    public let radius: Double
    /// How far the orbit's plane leans toward the viewer, radians.
    public let tilt: Double
    /// Which way the plane is turned on the screen, radians.
    public let yaw: Double
    /// Radians a second; negative goes the other way round.
    public let speed: Double
    /// Where on the orbit it starts.
    public let phase: Double
}

public enum Orbit {
    /// The widest orbit, in shell radii (see `path`).
    public static let widest = 1.28
    /// How far from the centre a dot may sit, as a share of the orb's
    /// side, so its glow stays inside the frame instead of being cut off.
    public static let reach = 0.44
    /// How long a tapped dot holds everything still before it all moves on.
    public static let holdSeconds: Double = 6

    /// The dots: unread notices first (needs, then heads-ups, then FYIs),
    /// then running tasks: one dot for every one, so the dots match the
    /// notice count (Dylan, 2026-11-19). At night only the notices that
    /// need Dylan, so the bedroom stays dark.
    public static func items(running: [RunningTask], notices: [Notice], night: Bool = false) -> [OrbitItem] {
        let orange = notices
            .filter { !night || $0.kind == .need }
            .sorted { $0.kind < $1.kind }
            .map { OrbitItem(id: "notice-" + $0.id, kind: .notice, title: $0.title, detail: $0.body, startedAt: nil, notice: $0) }
        let blue = night ? [] : running.map { OrbitItem(id: "task-" + $0.id, kind: .task, title: $0.label, detail: $0.state == "queued" ? "Queued" : "", startedAt: $0.startedAt, notice: nil) }
        return orange + blue
    }

    /// The radius (points) the orbits are measured in: the shell's, shrunk
    /// when the widest orbit would carry a dot past `reach` of the orb's
    /// side (the working shell is big enough to push dots off the edge).
    public static func scale(shellRadius: Double, side: Double) -> Double {
        min(shellRadius, side * reach / widest)
    }

    /// Each dot's own orbit, the same on every device and every launch (a
    /// fixed hash of its id, so it doesn't jump between snapshots).
    public static func path(for id: String) -> OrbitPath {
        var h: UInt64 = 5381
        for byte in id.utf8 { h = (h &* 33) ^ UInt64(byte) }
        func unit(_ shift: UInt64) -> Double { Double((h >> shift) & 0xFFFF) / 65_535 }
        let direction: Double = (h & 1) == 0 ? 1 : -1
        return OrbitPath(
            radius: 1.12 + (widest - 1.12) * unit(4),
            tilt: 0.35 + 0.75 * unit(20),
            yaw: -0.9 + 1.8 * unit(36),
            speed: direction * (0.22 + 0.22 * unit(48)),
            phase: 2 * .pi * unit(8)
        )
    }

    /// Where a dot is at time `t` (seconds), in shell radii from the
    /// centre: x right, y down, z toward the viewer (z < 0 is behind).
    public static func position(_ path: OrbitPath, t: Double) -> (x: Double, y: Double, z: Double) {
        let a = path.phase + path.speed * t
        // A flat circle, leaned back by `tilt`, then turned by `yaw`.
        let x0 = cos(a) * path.radius, z0 = sin(a) * path.radius
        let y1 = -z0 * sin(path.tilt), z1 = z0 * cos(path.tilt)
        let x = x0 * cos(path.yaw) - y1 * sin(path.yaw)
        let y = x0 * sin(path.yaw) + y1 * cos(path.yaw)
        return (x, y, z1)
    }

    /// A task's live timer: "0:42", "12:05", "1:02:10"; nil without a start.
    public static func elapsed(since startedAt: String?, now: Date = Date()) -> String? {
        guard let startedAt, let start = AgendaTime.parse(startedAt) else { return nil }
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// Seeing a notice reads it, and reading clears it everywhere, except
    /// one that needs Dylan: that stays until he answers it.
    public static func readOnView(_ notice: Notice) -> Bool {
        notice.kind != .need
    }

    /// How often to refresh: every 5 s while an orange dot is up (so a
    /// notice read on another device fades here soon after), else 15 s.
    public static func refreshSeconds(orangeShowing: Bool) -> Double {
        orangeShowing ? 5 : 15
    }
}

/// What a tap on the orb means (Dylan, 2026-11-18: "in kiosk tapping an
/// orbiting dot will freeze everything and tell what it's representing.
/// Tapping the blue inner orb itself (without tapping an orbiting dot)
/// starts and stops talk").
public enum OrbHit: Equatable, Sendable {
    /// A dot: hold everything still and show its label.
    case dot(String)
    /// The inner orb, off any dot: start or stop Talk (kiosks).
    case core
    /// Anywhere while held still: let it all move again.
    case release
    case nothing

    /// A dot answers to taps this far from its centre (a 52 pt target, over
    /// the 44 pt minimum), and wins over the orb under it.
    public static let dotReach: Double = 26

    /// Resolves a tap at (x, y) against the dots' screen positions, the
    /// orb's centre and its inner radius. While held still, a tap on
    /// another dot switches to it and anything else releases.
    public static func resolve(x: Double, y: Double, dots: [(id: String, x: Double, y: Double)], centerX: Double, centerY: Double, coreRadius: Double, frozen: Bool) -> OrbHit {
        let nearest = dots
            .map { (id: $0.id, d: ((x - $0.x) * (x - $0.x) + (y - $0.y) * (y - $0.y)).squareRoot()) }
            .filter { $0.d <= dotReach }
            .min { $0.d < $1.d }
        if let nearest { return .dot(nearest.id) }
        if frozen { return .release }
        let fromCenter = ((x - centerX) * (x - centerX) + (y - centerY) * (y - centerY)).squareRoot()
        return fromCenter <= coreRadius ? .core : .nothing
    }
}
