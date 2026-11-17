// Jarvis's orb, design D (Dylan, 2026-11-16): a see-through glass core
// inside a constellation of points that turns in 3D around it. Points
// behind the core are drawn first, smaller and dimmer, so they show
// through the glass; points in front pass over it.
import SwiftUI

struct OrbView: View {
    enum Mood {
        case listening, thinking, working, speaking
    }

    var state: Mood
    var size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Redraws every frame (or once, with Reduce Motion on).
    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            Canvas { canvas, area in
                draw(in: &canvas, area: area, t: t)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// How each state looks: point colour, orbit radius and speed, and how
    /// much the whole thing breathes.
    private var look: (color: Color, glow: Color, radius: Double, speed: Double, breathe: Double) {
        switch state {
        case .listening: return (Theme.frost, Theme.glacier, 0.36, 0.35, 0.02)
        case .thinking: return (.white, Color(red: 0.73, green: 0.65, blue: 0.94), 0.33, 1.4, 0)
        case .working: return (Color(red: 0.98, green: 0.89, blue: 0.75), Theme.ember, 0.44, 0.9, 0)
        case .speaking: return (.white, Theme.glacier, 0.36, 0.6, 0.06)
        }
    }

    /// Back points, the glass core, then front points.
    private func draw(in canvas: inout GraphicsContext, area: CGSize, t: Double) {
        let look = look
        let side = min(area.width, area.height)
        let center = CGPoint(x: area.width / 2, y: area.height / 2)
        let scale = 1 + look.breathe * sin(t * 5)
        let points = Self.sphere(count: 60, t: t, speed: look.speed)

        for point in points where point.z < 0 {
            dot(point, in: &canvas, center: center, radius: side * look.radius * scale, color: look.color)
        }
        core(in: &canvas, center: center, radius: side * 0.2, glow: look.glow)
        for point in points where point.z >= 0 {
            dot(point, in: &canvas, center: center, radius: side * look.radius * scale, color: look.color)
        }
    }

    /// One point: bigger and brighter the nearer it is.
    private func dot(_ p: (x: Double, y: Double, z: Double), in canvas: inout GraphicsContext, center: CGPoint, radius: Double, color: Color) {
        let near = (p.z + 1) / 2
        let d = 1.4 + near * 3.0
        let rect = CGRect(x: center.x + p.x * radius - d / 2, y: center.y + p.y * radius - d / 2, width: d, height: d)
        canvas.fill(Path(ellipseIn: rect), with: .color(color.opacity(0.18 + near * 0.8)))
    }

    /// The translucent glass core: a faint fill, a soft rim and a highlight.
    private func core(in canvas: inout GraphicsContext, center: CGPoint, radius: Double, glow: Color) {
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        let circle = Path(ellipseIn: rect)
        canvas.fill(circle, with: .radialGradient(
            Gradient(colors: [glow.opacity(0.35), glow.opacity(0.08)]),
            center: center, startRadius: 0, endRadius: radius
        ))
        canvas.stroke(circle, with: .color(.white.opacity(0.35)), lineWidth: 1)
        let shine = CGRect(x: center.x - radius * 0.55, y: center.y - radius * 0.75, width: radius * 0.8, height: radius * 0.45)
        canvas.fill(Path(ellipseIn: shine), with: .color(.white.opacity(0.28)))
    }

    /// Points spread evenly on a unit sphere (golden-angle spiral), turned
    /// about the vertical axis by `t * speed` and tilted toward the viewer.
    static func sphere(count: Int, t: Double, speed: Double) -> [(x: Double, y: Double, z: Double)] {
        let tilt = 0.45
        var out: [(x: Double, y: Double, z: Double)] = []
        for i in 0..<count {
            let y0 = 1 - (Double(i) / Double(count - 1)) * 2
            let ring = (1 - y0 * y0).squareRoot()
            let angle = Double(i) * 2.39996 + t * speed
            let x = cos(angle) * ring
            let z0 = sin(angle) * ring
            let y = y0 * cos(tilt) - z0 * sin(tilt)
            let z = y0 * sin(tilt) + z0 * cos(tilt)
            out.append((x, y, z))
        }
        return out
    }
}
