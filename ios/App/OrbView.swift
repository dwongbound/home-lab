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
import JarvisKit

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
    /// The dots orbiting the orb (Orbit in JarvisKit): blue for each task
    /// Jarvis is running, orange for each unread notice. Each travels its
    /// own tilted orbit, behind the orb and in front of it. Tapping one
    /// holds everything still and says what it is (Dylan, 2026-11-18).
    var orbit: [OrbitItem] = []
    /// False on the TV, where there's nothing to tap.
    var tappable = true
    /// How bright the orb itself is drawn (paused or off: dimmer); a work
    /// callout stays fully opaque.
    var dim: Double = 1
    /// True on a bright background (the TV's daytime sun lamp): the dots
    /// and lines are drawn in dark slate so they still show.
    var onLight = false
    /// Approve or Deny from an orange dot's label (nil: no buttons).
    var onAnswer: ((Notice, Bool) -> Void)? = nil
    /// A notice was seen (its label closed): read it, which clears it.
    var onRead: ((Notice) -> Void)? = nil
    /// A tap on the inner orb, off any dot (the kiosks: start or stop Talk).
    var onCoreTap: (() -> Void)? = nil
    /// "Open in Chat" on a notice's label (nil: no button, as in kiosks).
    var onOpen: ((Notice) -> Void)? = nil
    /// "Let go" on a kept (yellow) dot's label (nil: no button).
    var onLetGo: ((Notice) -> Void)? = nil
    /// The dot whose label is open, if any.
    @State private var opened: String?
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
            ZStack {
                Canvas { canvas, area in
                    animator.held = opened != nil
                    animator.step(to: OrbLook.of(state), speaking: state == .speaking, level: reduceMotion ? 0 : level, dotsRiseMs: dotsRiseMs, coreRiseMs: coreRiseMs, at: t)
                    animator.advanceOrbit(orbit, at: t, still: reduceMotion || opened != nil)
                    draw(in: &canvas, area: area, t: t)
                }
                .opacity(dim)
                .accessibilityHidden(true)
                #if !os(tvOS)
                // The TV's dots can't be selected (Dylan, 2026-11-18).
                if tappable {
                    tapLayer
                }
                #endif
            }
        }
        .frame(width: size, height: size)
        .overlay {
            if let id = opened, let item = animator.item(id) {
                // Everything holds still while this is open, so the label
                // can sit just under its dot.
                let spot = animator.orbitScreen[id] ?? CGPoint(x: size / 2, y: size / 2)
                OrbitCallout(item: item, onLight: onLight, onAnswer: onAnswer.map { answer in
                    { ok in
                        if let notice = item.notice { answer(notice, ok) }
                        opened = nil
                    }
                }, onOpen: item.notice?.turnId == nil ? nil : onOpen.map { open in
                    {
                        if let notice = item.notice { open(notice) }
                        opened = nil
                    }
                }, onKeep: (item.notice.map(Orbit.offersKeep) ?? false) ? { keep() } : nil, onLetGo: item.kind == .kept ? onLetGo.map { letGo in
                    {
                        if let notice = item.notice { letGo(notice) }
                        opened = nil
                    }
                } : nil) { close() }
                    .position(x: size / 2, y: min(size - 20, spot.y + 52))
                    .frame(width: size, height: size)
                    .background {
                        // Tapping anywhere else closes it.
                        Color.clear
                            .frame(width: 3000, height: 3000)
                            .contentShape(Rectangle())
                            .onTapGesture { close() }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
            }
        }
        .animation(.smooth(duration: 0.3), value: opened)
        // A label closes by itself after a few seconds and it all moves on,
        // leaving the notice as it was (only Close clears it).
        .task(id: opened) {
            guard opened != nil else { return }
            try? await Task.sleep(for: .seconds(Orbit.holdSeconds))
            // Timing out isn't choosing Close: the notice stays unread.
            if !Task.isCancelled { keep() }
        }
        #if DEBUG
        // Screenshot check: `-openWork` opens the first dot's label.
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-openWork"), tappable { opened = orbit.first?.id }
        }
        #endif
        // A dot that goes away closes its label.
        .onChange(of: orbit.map(\.id)) { _, ids in
            if let opened, !ids.contains(opened) { self.opened = nil }
        }
        #if DEBUG
        // `-openNotice` opens the first orange dot's label a few seconds in.
        .task {
            guard tappable, ProcessInfo.processInfo.arguments.contains("-openNotice") else { return }
            try? await Task.sleep(for: .seconds(8))
            opened = orbit.first { $0.notice != nil }?.id
        }
        #endif
    }

    #if !os(tvOS)
    /// One tap layer over the orb, read by OrbHit (JarvisKit): a dot (52 pt
    /// reach, winning over the orb under it) holds everything still and
    /// opens its label; the inner orb off any dot is `onCoreTap`. While a
    /// label is open, the label's own catcher takes every tap and releases.
    private var tapLayer: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { point in
                let dots = animator.orbitScreen.map { (id: $0.key, x: Double($0.value.x), y: Double($0.value.y)) }
                switch OrbHit.resolve(x: point.x, y: point.y, dots: dots, centerX: size / 2, centerY: size / 2, coreRadius: animator.lastCoreRadius, frozen: opened != nil) {
                case .dot(let id): opened = id
                case .core: onCoreTap?()
                case .release: close()
                case .nothing: break
                }
            }
            .accessibilityElement()
            .accessibilityLabel(onCoreTap == nil ? "Jarvis" : "Talk to Jarvis")
            .accessibilityAddTraits(onCoreTap == nil ? [] : .isButton)
            .accessibilityAction { onCoreTap?() }
            .accessibilityActions {
                ForEach(orbit) { item in
                    Button(item.kind == .task ? "Jarvis is working: \(item.title)" : item.kind == .kept ? "Kept: \(item.title)" : "Notice: \(item.title)") { opened = item.id }
                }
            }
    }

    #endif

    /// Closes the label; the orb eases back into turning. A notice that
    /// was looked at is read (cleared everywhere), unless it needs an answer.
    /// "Keep": closes the label without reading the notice, so its orange
    /// dot stays here and on every other device.
    private func keep() {
        opened = nil
    }

    private func close() {
        if let id = opened, let notice = animator.item(id)?.notice, Orbit.readOnView(notice) {
            onRead?(notice)
        }
        opened = nil
    }

    /// Far orbit dots, back lines and points, the glass core, front lines
    /// and points, then near orbit dots.
    private func draw(in canvas: inout GraphicsContext, area: CGSize, t: Double) {
        let a = animator
        let look = a.look
        let side = min(area.width, area.height)
        let center = CGPoint(x: area.width / 2, y: area.height / 2)
        let breath = 1 + look.breathe * sin(a.breathPhase)
        // Up to ~11% from his voice.
        let radius = side * look.radius * breath * (1 + a.shellVoice * 0.11)
        let points = a.orient(Self.base)
        let color = onLight ? Color(red: 0.16, green: 0.22, blue: 0.30) : look.color.color
        let shellGlow = a.shellVoice
        a.remember(points: points, center: center, radius: radius)
        let coreRadius = side * 0.2 * look.coreScale * (1 + a.coreVoice * 0.2)
        a.placeOrbit(center: center, radius: radius)
        a.lastCoreRadius = coreRadius

        drawOrbit(back: true, in: &canvas, center: center, radius: radius, coreRadius: coreRadius, side: side, t: t)
        lines(points, back: true, in: &canvas, center: center, radius: radius, color: color, voice: shellGlow, alpha: look.lineAlpha)
        for point in points where point.z < 0 {
            dot(point, in: &canvas, center: center, radius: radius, color: color, voice: shellGlow)
        }
        core(in: &canvas, center: center, radius: coreRadius, glow: look.glow.color, voice: min(1, look.coreBright + a.coreVoice))
        lines(points, back: false, in: &canvas, center: center, radius: radius, color: color, voice: shellGlow, alpha: look.lineAlpha)
        for point in points where point.z >= 0 {
            dot(point, in: &canvas, center: center, radius: radius, color: color, voice: shellGlow)
        }
        drawOrbit(back: false, in: &canvas, center: center, radius: radius, coreRadius: coreRadius, side: side, t: t)
    }

    /// The dark amber of a work dot (#E0A020), still used by the TV's
    /// task rows and the phone's kiosk work line.
    static let workAmber = Color(red: 0xE0 / 255, green: 0xA0 / 255, blue: 0x20 / 255)

    /// Blue for a task Jarvis is running; darker on the TV's day sky.
    static func taskBlue(onLight: Bool) -> Color {
        onLight ? Color(red: 0.08, green: 0.36, blue: 0.72) : Color(red: 0.42, green: 0.72, blue: 1.0)
    }

    /// Yellow for something kept to remember; darker on the TV's day sky.
    static func keptYellow(onLight: Bool) -> Color {
        onLight ? Color(red: 0.62, green: 0.50, blue: 0.02) : Color(red: 1.0, green: 0.86, blue: 0.30)
    }

    /// A dot's colour: blue Jarvis working, orange new, yellow kept.
    static func dotColor(_ kind: OrbitItem.Kind, onLight: Bool) -> Color {
        switch kind {
        case .task: return taskBlue(onLight: onLight)
        case .notice: return noticeOrange(onLight: onLight)
        case .kept: return keptYellow(onLight: onLight)
        }
    }

    /// Orange for a notice; darker on the TV's day sky.
    static func noticeOrange(onLight: Bool) -> Color {
        onLight ? Color(red: 0.80, green: 0.36, blue: 0.04) : Color(red: 1.0, green: 0.56, blue: 0.20)
    }

    /// The orbiting dots on the far side (drawn before the orb, smaller,
    /// dimmer, and faint where the core covers them) or the near side.
    private func drawOrbit(back: Bool, in canvas: inout GraphicsContext, center: CGPoint, radius: Double, coreRadius: Double, side: Double, t: Double) {
        for dot in animator.orbitDots where (dot.z < 0) == back {
            let near = (dot.z + 1) / 2
            var alpha = dot.alpha * (back ? 0.5 : 1)
            let dx = dot.point.x - center.x, dy = dot.point.y - center.y
            if back && (dx * dx + dy * dy).squareRoot() < coreRadius { alpha *= 0.35 }
            let isOpen = dot.item.id == opened
            let color = Self.dotColor(dot.item.kind, onLight: onLight)
            let core = side * 0.03 * (0.7 + near * 0.4) * (0.8 + dot.item.emphasis * 0.3) * (isOpen ? 1.45 : 1)
            let pulse = reduceMotion || opened != nil ? 0.5 : 0.5 + 0.5 * sin(t * 2.4 + dot.z * 3)
            let halo = core * (2.6 + pulse)
            canvas.fill(Path(ellipseIn: CGRect(x: dot.point.x - halo / 2, y: dot.point.y - halo / 2, width: halo, height: halo)), with: .radialGradient(
                Gradient(colors: [color.opacity(0.6 * alpha * dot.item.emphasis), color.opacity(0)]),
                center: dot.point, startRadius: 0, endRadius: halo / 2
            ))
            canvas.fill(Path(ellipseIn: CGRect(x: dot.point.x - core / 2, y: dot.point.y - core / 2, width: core, height: core)), with: .color(color.opacity(alpha * (0.55 + 0.45 * dot.item.emphasis))))
            if isOpen {
                let ring = core * 2.1
                canvas.stroke(Path(ellipseIn: CGRect(x: dot.point.x - ring / 2, y: dot.point.y - ring / 2, width: ring, height: ring)), with: .color(color.opacity(0.8)), lineWidth: 1.5)
            }
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
    /// True while a work dot's callout is open: the turning eases to a stop.
    var held = false
    /// Where the dots were last drawn, so tap targets can follow them.
    private var lastPoints: [(x: Double, y: Double, z: Double)] = []
    private var lastCenter = CGPoint.zero
    private var lastRadius: Double = 0

    // MARK: Orbit dots

    /// One orbiting dot as last placed: its item, how faded in it is, and
    /// where it sits (screen point, and z: < 0 behind the orb).
    struct OrbitDot {
        let item: OrbitItem
        let alpha: Double
        let point: CGPoint
        let z: Double
    }
    /// Each dot, fading in on arrival and out on leaving (read on another
    /// device, task done) rather than popping.
    private var tracks: [String: (item: OrbitItem, alpha: Double, live: Bool)] = [:]
    private var trackOrder: [String] = []
    /// The orbit's own clock: it stops while a label is open, so the dots
    /// hold still and pick up exactly where they were.
    private var orbitClock: Double = 0
    private var orbitLast: Double?
    private(set) var orbitDots: [OrbitDot] = []
    /// Where each dot is on screen, for its tap target and label.
    private(set) var orbitScreen: [String: CGPoint] = [:]
    /// The inner orb's radius as last drawn, for taps on it.
    var lastCoreRadius: Double = 0

    /// The item behind a dot that's showing (or fading out).
    func item(_ id: String) -> OrbitItem? { tracks[id]?.item }

    /// Moves the orbit clock and the fades on to time `t`.
    func advanceOrbit(_ items: [OrbitItem], at t: Double, still: Bool) {
        let dt = min(max(t - (orbitLast ?? t), 0), 0.1)
        orbitLast = t
        if !still { orbitClock += dt }
        let ids = Set(items.map(\.id))
        for item in items {
            if tracks[item.id] == nil { trackOrder.append(item.id) }
            tracks[item.id] = (item, tracks[item.id]?.alpha ?? 0, true)
        }
        for id in trackOrder where !ids.contains(id) { tracks[id]?.live = false }
        for id in trackOrder {
            guard var track = tracks[id] else { continue }
            track.alpha = track.live ? min(1, track.alpha + dt * 2) : max(0, track.alpha - dt * 1.2)
            tracks[id] = track
        }
        trackOrder.removeAll { id in
            guard let track = tracks[id] else { return true }
            if !track.live && track.alpha <= 0 { tracks[id] = nil; return true }
            return false
        }
    }

    /// Works out where every dot is this frame, around this orb.
    func placeOrbit(center: CGPoint, radius: Double) {
        var dots: [OrbitDot] = []
        var screen: [String: CGPoint] = [:]
        for id in trackOrder {
            guard let track = tracks[id] else { continue }
            let p = Orbit.position(Orbit.path(for: id), t: orbitClock)
            let point = CGPoint(x: center.x + p.x * radius, y: center.y + p.y * radius)
            dots.append(OrbitDot(item: track.item, alpha: track.alpha, point: point, z: p.z / max(Orbit.path(for: id).radius, 0.01)))
            if track.live { screen[id] = point }
        }
        orbitDots = dots
        orbitScreen = screen
    }

    /// Notes where this frame drew the dots.
    func remember(points: [(x: Double, y: Double, z: Double)], center: CGPoint, radius: Double) {
        lastPoints = points
        lastCenter = center
        lastRadius = radius
    }

    /// Where dot `index` sits on screen, as last drawn.
    func screen(_ index: Int) -> CGPoint {
        guard index < lastPoints.count else { return lastCenter }
        let p = lastPoints[index]
        return CGPoint(x: lastCenter.x + p.x * lastRadius, y: lastCenter.y + p.y * lastRadius)
    }
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
        if held {
            // A work callout is open: hold still so the dot stays put.
            target = (0, 0, 0)
        } else if speaking || look.speed > 0.45 {
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

/// The little label a tapped dot opens: for a blue dot, the task and a
/// live timer; for an orange one, the notice, when, and Approve/Deny if it
/// needs an answer.
struct OrbitCallout: View {
    let item: OrbitItem
    let onLight: Bool
    /// Approve (true) or Deny (false); nil hides the buttons.
    let onAnswer: ((Bool) -> Void)?
    /// Opens the full message in Chat; nil hides the button.
    var onOpen: (() -> Void)? = nil
    /// Closes without clearing, so the dot stays; nil hides the button.
    var onKeep: (() -> Void)? = nil
    /// A kept (yellow) item's "Let go"; nil hides the button.
    var onLetGo: (() -> Void)? = nil
    let onClose: () -> Void

    var body: some View {
        let color = OrbView.dotColor(item.kind, onLight: false)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Circle().fill(color).frame(width: 10, height: 10).padding(.top, 5)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.frost)
                        .fixedSize(horizontal: false, vertical: true)
                    if item.kind == .task {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(item.detail.isEmpty ? "Running · \(Orbit.elapsed(since: item.startedAt, now: context.date) ?? "now")" : item.detail)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(Theme.frostDim)
                        }
                    } else {
                        if !item.detail.isEmpty {
                            Text(item.detail).font(.caption).foregroundStyle(Theme.frostDim).lineLimit(3)
                        }
                        if let created = item.notice?.created, !Notices.when(created).isEmpty {
                            Text(Notices.when(created)).font(.caption2).foregroundStyle(Theme.frostFaint)
                        }
                    }
                }
                Spacer(minLength: 0)
                // The (x) closes and keeps the dot (Dylan, 2026-11-19: "can
                // keep just be an (x) on the top right"); where there's
                // nothing to keep it simply closes.
                Button(action: onKeep ?? onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Theme.frostDim)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(onKeep == nil ? "Close" : "Keep for later")
            }
            // A kept item: Open in Chat and Let go; the (x) just closes.
            if item.kind == .kept, onOpen != nil || onLetGo != nil {
                HStack(spacing: 10) {
                    if let onOpen {
                        Button("Open in Chat", action: onOpen).buttonStyle(.bordered)
                    }
                    if let onLetGo {
                        Button("Let go", action: onLetGo).buttonStyle(.bordered)
                    }
                }
                .font(.footnote.weight(.semibold))
                .padding(.leading, 20)
            } else if let notice = item.notice, !notice.isApproval, onOpen != nil || onKeep != nil {
                HStack(spacing: 10) {
                    if let onOpen {
                        Button("Open in Chat", action: onOpen).buttonStyle(.bordered)
                    }
                    // Close reads the notice, so the dot goes everywhere (a
                    // reminder's says it stops the nag).
                    if onKeep != nil {
                        Button(notice.source == "reminder" ? notice.clearLabel : "Close", action: onClose).buttonStyle(.borderedProminent)
                    }
                }
                .font(.footnote.weight(.semibold))
                .padding(.leading, 20)
            }
            if let onAnswer, item.notice?.isApproval == true {
                HStack(spacing: 10) {
                    Button("Deny") { onAnswer(false) }
                        .buttonStyle(.bordered)
                    Button("Approve") { onAnswer(true) }
                        .buttonStyle(.borderedProminent)
                }
                .font(.footnote.weight(.semibold))
                .padding(.leading, 20)
            }
        }
        .padding(.leading, 12)
        .padding(.vertical, 6)
        .padding(.trailing, 4)
        .frame(maxWidth: 300)
        // Solid, so the words under it don't show through.
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(red: 0.13, green: 0.16, blue: 0.21)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(color.opacity(0.55), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
        .fixedSize(horizontal: false, vertical: true)
    }
}
