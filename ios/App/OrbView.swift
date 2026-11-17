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
    /// How bright (high) that voice sounds (0..1): a rising inflection swells the shell a little more.
    var tone: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Everything that moves, carried from frame to frame.
    @State private var animator = OrbAnimator()

    /// Redraws every frame (or once, with Reduce Motion on).
    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { canvas, area in
                animator.step(to: OrbLook.of(state), speaking: state == .speaking, level: reduceMotion ? 0 : level, tone: reduceMotion ? 0 : tone, at: t)
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
        // Up to ~21% from his voice, plus up to ~5% more on a rising inflection.
        let radius = side * look.radius * breath * (1 + a.shellVoice * 0.21 + a.shellVoice * a.shellTone * 0.05)
        let points = Self.sphere(count: Self.count, angle: a.angle)
        let color = look.color.color
        let shellGlow = a.shellVoice

        lines(points, back: true, in: &canvas, center: center, radius: radius, color: color, voice: shellGlow, alpha: look.lineAlpha)
        for point in points where point.z < 0 {
            dot(point, in: &canvas, center: center, radius: radius, color: color, voice: shellGlow)
        }
        core(in: &canvas, center: center, radius: side * 0.2 * look.coreScale * (1 + a.coreVoice * 0.25), glow: look.glow.color, voice: min(1, look.coreBright + a.coreVoice * 1.15))
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
    private(set) var angle: Double = 0
    private(set) var breathPhase: Double = 0
    /// How much the voice belongs to Jarvis (1) rather than Dylan (0), eased.
    private var speakingMix: Double = 0
    private var stage1: Double = 0
    private var envelope: Double = 0
    /// Dylan's own envelope for the shell: same timing as the core, but a
    /// lower noise floor and a steeper curve, so emphasised syllables swell
    /// clearly more than quiet ones (Dylan, 2026-11-17: "move more with my
    /// inflections", not faster).
    private var shellStage1: Double = 0
    private var shellEnvelope: Double = 0
    /// How high Dylan sounds, smoothed the same way (0..1).
    private(set) var shellTone: Double = 0
    private var last: Double?

    /// Dylan's voice, as the shell sees it.
    var shellVoice: Double { shellEnvelope * (1 - speakingMix) }
    /// Jarvis's voice, as the core sees it.
    var coreVoice: Double { envelope * speakingMix }

    func step(to target: OrbLook, speaking: Bool, level: Double, tone: Double = 0, at t: Double) {
        let dt = min(max(t - (last ?? t), 0), 0.1)
        last = t
        let ease = 1 - exp(-dt / 0.75)
        look = look.toward(target, ease)
        speakingMix += ((speaking ? 1 : 0) - speakingMix) * (1 - exp(-dt / 0.5))
        angle += look.speed * dt
        breathPhase += 2.4 * dt

        // Dead zone and soft knee: below 0.08 is room noise; above it the
        // level rises gently at first.
        let raw = min(max(level, 0), 1)
        let gated = max(0, (raw - 0.08) / 0.92)
        let input = gated * gated * (3 - 2 * gated)
        // Two cascaded one-pole filters: ~170 ms to rise, ~560 ms to fall
        // (Dylan, 2026-11-17: "a little less smooth" than 250/800).
        // Jarvis's core: ~170 ms up / ~560 ms down.
        let tau = input > envelope ? 0.085 : 0.28
        let k = 1 - exp(-dt / tau)
        stage1 += (input - stage1) * k
        envelope += (stage1 - envelope) * k
        // The shell: noise floor 0.05, then a gamma 0.7 curve that opens up
        // the middle of the range; same ~170 ms up / ~560 ms down.
        let shellGated = max(0, (raw - 0.05) / 0.95)
        let shellInput = pow(shellGated, 0.7)
        let sk = 1 - exp(-dt / (shellInput > shellEnvelope ? 0.085 : 0.28))
        shellStage1 += (shellInput - shellStage1) * sk
        shellEnvelope += (shellStage1 - shellEnvelope) * sk
        // Pitch only counts while he's audible, and eases like the level.
        if shellGated > 0 { shellTone += (min(max(tone, 0), 1) - shellTone) * (1 - exp(-dt / 0.28)) }
    }
}
