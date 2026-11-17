// Jarvis's orb, design D (Dylan, 2026-11-16): a see-through glass core
// inside a constellation of points that turns in 3D around it. Points
// behind the core are drawn first, smaller and dimmer, so they show
// through the glass; points in front pass over it. Faint lines join each
// point to its nearest neighbours, so the shell reads as a constellation.
//
// One continuous animation (Dylan, 2026-11-17): nothing restarts or cuts.
// A single clock drives an OrbAnimator that keeps its own turning angle
// and eases every look (speed, size, colours, glow) toward the mood's, so
// listening → thinking → speaking cross-fade. While Dylan talks the whole
// shell swells calmly as one (a doubly smoothed envelope, with a dead zone
// for room noise); while Jarvis talks only the core swells and brightens.
import SwiftUI

struct OrbView: View {
    enum Mood {
        case listening, thinking, working, speaking
    }

    var state: Mood
    var size: CGFloat
    /// How loud the voice that matters is (0..1).
    var level: Double = 0
    /// How bright that voice sounds (0..1); kept for callers, not drawn.
    var tone: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Everything that moves, carried from frame to frame.
    @State private var animator = OrbAnimator()
    /// How quickly the dots and the core rise with a voice, in ms; set in
    /// Settings → Orb feel (Dylan, 2026-11-17). Settling takes ~3.5× as long.
    @AppStorage(OrbTuning.dotsKey) private var dotsRiseMs: Double = OrbTuning.dotsDefault
    @AppStorage(OrbTuning.coreKey) private var coreRiseMs: Double = OrbTuning.coreDefault

    /// Redraws every frame (or once, with Reduce Motion on).
    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { canvas, area in
                animator.step(to: OrbLook.of(state), speaking: state == .speaking, level: reduceMotion ? 0 : level, dotsRiseMs: dotsRiseMs, coreRiseMs: coreRiseMs, at: t)
                draw(in: &canvas, area: area)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// Back lines and points, the glass core, then front lines and points.
    private func draw(in canvas: inout GraphicsContext, area: CGSize) {
        let a = animator
        let look = a.look
        let side = min(area.width, area.height)
        let center = CGPoint(x: area.width / 2, y: area.height / 2)
        let breath = 1 + look.breathe * sin(a.breathPhase)
        // Up to ~11% from his voice.
        let radius = side * look.radius * breath * (1 + a.shellVoice * 0.11)
        let points = a.orient(Self.base)
        let color = look.color.color
        let shellGlow = a.shellVoice

        lines(points, back: true, in: &canvas, center: center, radius: radius, color: color, voice: shellGlow, alpha: look.lineAlpha)
        for point in points where point.z < 0 {
            dot(point, in: &canvas, center: center, radius: radius, color: color, voice: shellGlow)
        }
        core(in: &canvas, center: center, radius: side * 0.2 * look.coreScale * (1 + a.coreVoice * 0.2), glow: look.glow.color, voice: min(1, look.coreBright + a.coreVoice))
        lines(points, back: false, in: &canvas, center: center, radius: radius, color: color, voice: shellGlow, alpha: look.lineAlpha)
        for point in points where point.z >= 0 {
            dot(point, in: &canvas, center: center, radius: radius, color: color, voice: shellGlow)
        }
    }

    /// Faint lines from each point to its nearest neighbours: the ones
    /// behind the core first and dimmer, the front ones over it. They
    /// brighten with the voice.
    private func lines(_ points: [(x: Double, y: Double, z: Double)], back: Bool, in canvas: inout GraphicsContext, center: CGPoint, radius: Double, color: Color, voice: Double, alpha: Double) {
        for (a, b) in Self.edges {
            let pa = points[a], pb = points[b]
            let depth = (pa.z + pb.z) / 2
            if (depth < 0) != back { continue }
            let near = (depth + 1) / 2
            var path = Path()
            path.move(to: CGPoint(x: center.x + pa.x * radius, y: center.y + pa.y * radius))
            path.addLine(to: CGPoint(x: center.x + pb.x * radius, y: center.y + pb.y * radius))
            let opacity = (0.05 + near * 0.16) * alpha * (1 + voice * 0.8)
            canvas.stroke(path, with: .color(color.opacity(min(opacity, 0.5))), lineWidth: 0.6 + near * 0.4)
        }
    }

    /// The shell's points before any turning: the golden spiral, tilted
    /// toward the viewer.
    static let base = sphere(count: count, angle: 0)

    /// How many points make the shell.
    static let count = 60

    /// Each point's three nearest neighbours, worked out once. The shell only
    /// ever turns as a whole, so who is next to whom never changes.
    static let edges: [(Int, Int)] = {
        let points = sphere(count: count, angle: 0)
        var seen = Set<[Int]>()
        var out: [(Int, Int)] = []
        for i in points.indices {
            let nearest = points.indices
                .filter { $0 != i }
                .sorted { distance(points[i], points[$0]) < distance(points[i], points[$1]) }
                .prefix(3)
            for j in nearest where seen.insert([min(i, j), max(i, j)]).inserted {
                out.append((min(i, j), max(i, j)))
            }
        }
        return out
    }()

    /// Straight-line distance between two points on the shell.
    private static func distance(_ a: (x: Double, y: Double, z: Double), _ b: (x: Double, y: Double, z: Double)) -> Double {
        let dx = a.x - b.x, dy = a.y - b.y, dz = a.z - b.z
        return (dx * dx + dy * dy + dz * dz).squareRoot()
    }

    /// One point: bigger and brighter the nearer it is.
    private func dot(_ p: (x: Double, y: Double, z: Double), in canvas: inout GraphicsContext, center: CGPoint, radius: Double, color: Color, voice: Double) {
        let near = (p.z + 1) / 2
        let d = (1.4 + near * 3.0) * (1 + voice * 0.35)
        let rect = CGRect(x: center.x + p.x * radius - d / 2, y: center.y + p.y * radius - d / 2, width: d, height: d)
        canvas.fill(Path(ellipseIn: rect), with: .color(color.opacity(0.18 + near * 0.8)))
    }

    /// The translucent glass core: a faint fill, a soft rim and a highlight.
    /// `voice` lights it from inside (Jarvis's words come from here).
    private func core(in canvas: inout GraphicsContext, center: CGPoint, radius: Double, glow: Color, voice: Double) {
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        let circle = Path(ellipseIn: rect)
        canvas.fill(circle, with: .radialGradient(
            Gradient(colors: [Color.white.opacity(voice * 0.35), glow.opacity(0.35 + voice * 0.45), glow.opacity(0.08 + voice * 0.18)]),
            center: center, startRadius: 0, endRadius: radius
        ))
        canvas.stroke(circle, with: .color(.white.opacity(0.35 + voice * 0.3)), lineWidth: 1)
        if voice > 0.01 {
            // A soft halo just outside the glass that swells with his voice.
            let halo = radius * (1.15 + voice * 0.35)
            let haloRect = CGRect(x: center.x - halo, y: center.y - halo, width: halo * 2, height: halo * 2)
            canvas.fill(Path(ellipseIn: haloRect), with: .radialGradient(
                Gradient(colors: [glow.opacity(voice * 0.25), glow.opacity(0)]),
                center: center, startRadius: radius * 0.9, endRadius: halo
            ))
        }
        let shine = CGRect(x: center.x - radius * 0.55, y: center.y - radius * 0.75, width: radius * 0.8, height: radius * 0.45)
        canvas.fill(Path(ellipseIn: shine), with: .color(.white.opacity(0.28)))
    }

    /// Points spread evenly on a unit sphere (golden-angle spiral), turned
    /// about the vertical axis by `angle` and tilted toward the viewer.
    static func sphere(count: Int, angle turn: Double) -> [(x: Double, y: Double, z: Double)] {
        let tilt = 0.45
        var out: [(x: Double, y: Double, z: Double)] = []
        for i in 0..<count {
            let y0 = 1 - (Double(i) / Double(count - 1)) * 2
            let ring = (1 - y0 * y0).squareRoot()
            let angle = Double(i) * 2.39996 + turn
            let x = cos(angle) * ring
            let z0 = sin(angle) * ring
            let y = y0 * cos(tilt) - z0 * sin(tilt)
            let z = y0 * sin(tilt) + z0 * cos(tilt)
            out.append((x, y, z))
        }
        return out
    }
}

/// An RGB colour that can be blended frame by frame.
struct OrbRGB {
    var r, g, b: Double

    var color: Color { Color(red: r, green: g, blue: b) }

    /// `self` moved `k` (0..1) of the way to `target`.
    func toward(_ target: OrbRGB, _ k: Double) -> OrbRGB {
        OrbRGB(r: r + (target.r - r) * k, g: g + (target.g - g) * k, b: b + (target.b - b) * k)
    }
}

/// Everything a mood decides about the orb. Each is a target the drawn
/// orb eases toward, never a value it jumps to.
struct OrbLook {
    var color: OrbRGB
    var glow: OrbRGB
    var radius: Double
    var speed: Double
    var breathe: Double
    var coreScale: Double
    var coreBright: Double
    var lineAlpha: Double

    static let frost = OrbRGB(r: 0xf2 / 255, g: 0xef / 255, b: 0xe9 / 255)
    static let glacier = OrbRGB(r: 0x8e / 255, g: 0xc5 / 255, b: 0xea / 255)
    static let violet = OrbRGB(r: 0.73, g: 0.65, b: 0.94)
    static let ember = OrbRGB(r: 0xe8 / 255, g: 0xb0 / 255, b: 0x6a / 255)
    static let warm = OrbRGB(r: 0.98, g: 0.89, b: 0.75)
    static let white = OrbRGB(r: 1, g: 1, b: 1)

    static func of(_ mood: OrbView.Mood) -> OrbLook {
        switch mood {
        case .listening: return OrbLook(color: frost, glow: glacier, radius: 0.36, speed: 0.35, breathe: 0.015, coreScale: 1, coreBright: 0, lineAlpha: 1)
        case .thinking: return OrbLook(color: white, glow: violet, radius: 0.34, speed: 1.2, breathe: 0, coreScale: 0.97, coreBright: 0.12, lineAlpha: 1.15)
        case .working: return OrbLook(color: warm, glow: ember, radius: 0.42, speed: 0.8, breathe: 0, coreScale: 1, coreBright: 0.1, lineAlpha: 1)
        case .speaking: return OrbLook(color: white, glow: glacier, radius: 0.36, speed: 0.5, breathe: 0, coreScale: 1.04, coreBright: 0.15, lineAlpha: 1)
        }
    }

    /// `self` moved `k` (0..1) of the way to `target`, every field at once.
    func toward(_ t: OrbLook, _ k: Double) -> OrbLook {
        func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * k }
        return OrbLook(
            color: color.toward(t.color, k), glow: glow.toward(t.glow, k),
            radius: mix(radius, t.radius), speed: mix(speed, t.speed), breathe: mix(breathe, t.breathe),
            coreScale: mix(coreScale, t.coreScale), coreBright: mix(coreBright, t.coreBright), lineAlpha: mix(lineAlpha, t.lineAlpha)
        )
    }
}

/// The orb's running state, stepped once per frame and never reset: the
/// turning angle and breathing phase accumulate (so a speed change never
/// jumps them), the look eases toward the mood's over about 0.75 s, and
/// the voice runs through two one-pole filters after a dead zone, so the
/// swell is calm and room noise doesn't move it. A class so the Canvas can
/// update it while drawing without redrawing the view.
final class OrbAnimator {
    private(set) var look = OrbLook.of(.listening)
    /// The shell's orientation, a rotation matrix (rows), turned a little
    /// every frame by `spin`. Never reset, so nothing ever jumps.
    private var rotation: [[Double]] = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
    /// The current angular velocity (x, y, z, radians per second), eased
    /// toward each mood's: about the vertical while he thinks or speaks,
    /// still while Dylan is talking, and a slow wandering tumble when idle.
    private var spin: (Double, Double, Double) = (0, 0.35, 0)
    /// How recently Dylan was audible (0..1), slow to fall so the orb
    /// doesn't start turning in the gaps between words.
    private var hearing: Double = 0
    private var clock: Double = 0
    private(set) var breathPhase: Double = 0
    /// How much the voice belongs to Jarvis (1) rather than Dylan (0), eased.
    private var speakingMix: Double = 0
    private var stage1: Double = 0
    private var envelope: Double = 0
    /// Dylan's own envelope for the shell: lighter smoothing than the core's
    /// so it visibly follows his syllables, within the same ~11% swell.
    private var shellStage1: Double = 0
    private var shellEnvelope: Double = 0
    private var last: Double?

    /// Dylan's voice, as the shell sees it.
    var shellVoice: Double { shellEnvelope * (1 - speakingMix) }
    /// Jarvis's voice, as the core sees it.
    var coreVoice: Double { envelope * speakingMix }

    func step(to target: OrbLook, speaking: Bool, level: Double, dotsRiseMs: Double = OrbTuning.dotsDefault, coreRiseMs: Double = OrbTuning.coreDefault, at t: Double) {
        let dt = min(max(t - (last ?? t), 0), 0.1)
        last = t
        let ease = 1 - exp(-dt / 0.75)
        look = look.toward(target, ease)
        speakingMix += ((speaking ? 1 : 0) - speakingMix) * (1 - exp(-dt / 0.5))
        clock += dt
        turn(dt: dt, speaking: speaking, level: level)
        breathPhase += 2.4 * dt

        // Dead zone and soft knee: below 0.08 is room noise; above it the
        // level rises gently at first.
        let raw = min(max(level, 0), 1)
        let gated = max(0, (raw - 0.08) / 0.92)
        let input = gated * gated * (3 - 2 * gated)
        // Two cascaded one-pole filters: ~170 ms to rise, ~560 ms to fall
        // (Dylan, 2026-11-17: "a little less smooth" than 250/800).
        // Jarvis's core: rises in about coreRiseMs, settles ~3.3× slower.
        let coreRise = max(coreRiseMs, 20) / 1800
        let tau = input > envelope ? coreRise : coreRise * 3.3
        let k = 1 - exp(-dt / tau)
        stage1 += (input - stage1) * k
        envelope += (stage1 - envelope) * k
        // The shell, a little less smoothed so it follows his syllables
        // (Dylan, 2026-11-17: "looks more responsive", same size): the same
        // dead zone and curve, scaled so normal speech travels the whole
        // range; one main stage (rise set in Settings, settle ~3.6× that)
        // and a light 30 ms second stage that only takes the edge off.
        let shellInput = min(1, input * 1.25)
        let dotsRise = max(dotsRiseMs, 20) / 1800
        let sk = 1 - exp(-dt / (shellInput > shellStage1 ? dotsRise : dotsRise * 3.6))
        shellStage1 += (shellInput - shellStage1) * sk
        // De-jitter: enough that a single audio chunk can't make it flicker.
        shellEnvelope += (shellStage1 - shellEnvelope) * (1 - exp(-dt / 0.03))
    }
}

/// The orb's feel, tunable in Settings → Orb feel.
enum OrbTuning {
    static let dotsKey = "orb.dotsRiseMs"
    static let coreKey = "orb.coreRiseMs"
    /// About 50 ms up / 180 ms down for the dots.
    static let dotsDefault: Double = 50
    /// About 85 ms up / 275 ms down for the core.
    static let coreDefault: Double = 85
}

extension OrbAnimator {
    /// Turns the shell for one frame (Dylan, 2026-11-17): while he's
    /// talking it holds still; when nothing is being said (listening in
    /// silence, or paused waiting for "Hey Jarvis") it tumbles slowly
    /// about an axis that keeps wandering; while Jarvis thinks or speaks
    /// it spins about the vertical as before. The velocity eases between
    /// these over about 0.7 s, so a change never jerks.
    fileprivate func turn(dt: Double, speaking: Bool, level: Double) {
        // Audible = above the noise floor; rises fast, fades over ~1.2 s.
        let audible = (!speaking && level > 0.08) ? 1.0 : 0.0
        hearing += (audible - hearing) * (1 - exp(-dt / (audible > hearing ? 0.08 : 1.2)))

        let target: (Double, Double, Double)
        if speaking || look.speed > 0.45 {
            // Thinking, working or speaking: the vertical spin.
            target = (0, look.speed, 0)
        } else {
            // Idle tumble: an axis drifting smoothly over the sphere.
            let a = clock * 0.11, b = clock * 0.07 + 1.3
            let axis = (sin(a) * cos(b), cos(a) * 0.6 + 0.4, sin(b) * cos(a))
            let len = max(1e-6, (axis.0 * axis.0 + axis.1 * axis.1 + axis.2 * axis.2).squareRoot())
            let rate = 0.32 * (1 - hearing)
            target = (axis.0 / len * rate, axis.1 / len * rate, axis.2 / len * rate)
        }
        let k = 1 - exp(-dt / 0.7)
        spin = (spin.0 + (target.0 - spin.0) * k, spin.1 + (target.1 - spin.1) * k, spin.2 + (target.2 - spin.2) * k)

        let speed = (spin.0 * spin.0 + spin.1 * spin.1 + spin.2 * spin.2).squareRoot()
        guard speed > 1e-6 else { return }
        let angle = speed * dt
        let (x, y, z) = (spin.0 / speed, spin.1 / speed, spin.2 / speed)
        let c = cos(angle), s = sin(angle), t = 1 - c
        // Rodrigues: the small rotation for this frame, applied on top.
        let r: [[Double]] = [
            [t * x * x + c, t * x * y - s * z, t * x * z + s * y],
            [t * x * y + s * z, t * y * y + c, t * y * z - s * x],
            [t * x * z - s * y, t * y * z + s * x, t * z * z + c],
        ]
        var next = [[Double]](repeating: [0, 0, 0], count: 3)
        for i in 0..<3 { for j in 0..<3 { next[i][j] = r[i][0] * rotation[0][j] + r[i][1] * rotation[1][j] + r[i][2] * rotation[2][j] } }
        rotation = Self.orthonormal(next)
    }

    /// The shell's points turned to the current orientation.
    func orient(_ points: [(x: Double, y: Double, z: Double)]) -> [(x: Double, y: Double, z: Double)] {
        let m = rotation
        return points.map { p in
            (m[0][0] * p.x + m[0][1] * p.y + m[0][2] * p.z,
             m[1][0] * p.x + m[1][1] * p.y + m[1][2] * p.z,
             m[2][0] * p.x + m[2][1] * p.y + m[2][2] * p.z)
        }
    }

    /// Keeps the matrix a pure rotation as tiny rounding errors build up.
    private static func orthonormal(_ m: [[Double]]) -> [[Double]] {
        func norm(_ v: [Double]) -> [Double] {
            let l = max(1e-9, (v[0] * v[0] + v[1] * v[1] + v[2] * v[2]).squareRoot())
            return [v[0] / l, v[1] / l, v[2] / l]
        }
        let a = norm(m[0])
        let dot = a[0] * m[1][0] + a[1] * m[1][1] + a[2] * m[1][2]
        let b = norm([m[1][0] - dot * a[0], m[1][1] - dot * a[1], m[1][2] - dot * a[2]])
        let c = [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]
        return [a, b, c]
    }
}
