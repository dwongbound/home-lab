// The pieces of the TV's always-on board (Dylan, 2026-11-17: "more dynamic /
// nicely styled — people will see this as they walk into my room"): the
// living sky (the sun or moon on its arc, stars at night, drifting haze and
// rain from the weather), the status chips, the Now/Next hero card, the
// rotating cards' rows entering one after another, and page dots that fill
// while a card is up. Every colour comes from the measured LampPalette, so
// the contrast tests still hold. Everything that moves stops for Reduce
// Motion and stays GPU-cheap: two Canvases and a few blurred shapes.
import SwiftUI
import JarvisKit

// MARK: Sky

/// The layers over the lamp's gradient: the arc with the sun or moon, the
/// stars, and the weather's haze or rain. Kept to the top of the screen and
/// faint, so text never sits on anything brighter than the tests measured.
struct SkyLayers: View {
    let lamp: SunLampState
    let arc: SkyArc
    let condition: String?
    let palette: LampPalette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { area in
            let size = area.size
            TimelineView(.animation(minimumInterval: 1.0 / 20, paused: reduceMotion)) { tick in
                let t = tick.date.timeIntervalSinceReferenceDate
                ZStack {
                    haze(size, t: t)
                    Canvas { context, size in
                        drawStars(context, size: size, t: t)
                        drawArc(context, size: size)
                        drawRain(context, size: size, t: t)
                    }
                    body(size, t: t)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The arc's point at `p` (0…1): a wide shallow curve across the top.
    private func arcPoint(_ p: Double, _ size: CGSize) -> CGPoint {
        CGPoint(x: size.width * (0.03 + 0.94 * p), y: size.height * (0.22 - 0.18 * sin(.pi * p)))
    }

    /// A dotted line for the sun's path, faint: decoration, not text.
    private func drawArc(_ context: GraphicsContext, size: CGSize) {
        var path = Path()
        for i in 0...80 {
            let point = arcPoint(Double(i) / 80, size)
            i == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        context.stroke(path, with: .color(palette.dot.color.opacity(0.35)), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 14]))
    }

    /// The sun (glowing, warm) or the moon (small and pale) on the arc.
    @ViewBuilder
    private func body(_ size: CGSize, t: Double) -> some View {
        let point = arcPoint(arc.progress, size)
        // Rises out of the horizon and sinks into it rather than popping.
        let fade = min(1, arc.height * 4)
        if arc.sun {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Color(red: 1, green: 0.86, blue: 0.55).opacity(0.55), .clear], center: .center, startRadius: 0, endRadius: 170))
                    .frame(width: 340, height: 340)
                    .scaleEffect(1 + 0.04 * sin(t / 3))
                Circle()
                    .fill(Color(red: 1, green: 0.80, blue: 0.40))
                    .frame(width: 46, height: 46)
                    .shadow(color: Color(red: 1, green: 0.7, blue: 0.3).opacity(0.6), radius: 20)
            }
            .opacity(fade)
            .position(point)
        } else {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Color.white.opacity(0.10), .clear], center: .center, startRadius: 0, endRadius: 90))
                    .frame(width: 180, height: 180)
                // A crescent: a pale disc with a sky-coloured disc over it.
                Circle().fill(palette.dot.color).frame(width: 34, height: 34)
                Circle().fill(palette.skyTop.color).frame(width: 30, height: 30).offset(x: 9, y: -5)
            }
            .opacity(fade)
            .position(point)
        }
    }

    /// Stars in the top band, twinkling slowly, fading out at dawn.
    private func drawStars(_ context: GraphicsContext, size: CGSize, t: Double) {
        let visible = SkyArc.stars(lamp)
        guard visible > 0.01 else { return }
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func next() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 11) / Double(1 << 53)
        }
        for i in 0..<70 {
            let x = next() * size.width, y = next() * size.height * 0.2
            let r = 1.0 + next() * 1.6
            let twinkle = 0.55 + 0.45 * sin(t * (0.6 + next()) + Double(i))
            let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
            context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.5 * visible * twinkle)))
        }
    }

    /// Thin falling streaks when it's raining, faint.
    private func drawRain(_ context: GraphicsContext, size: CGSize, t: Double) {
        guard let condition, condition.lowercased().contains("rain") || condition.lowercased().contains("pour") else { return }
        var seed: UInt64 = 42
        func next() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 11) / Double(1 << 53)
        }
        for _ in 0..<90 {
            let x0 = next() * size.width * 1.2, speed = 300 + next() * 200
            let y = (next() * size.height + t * speed).truncatingRemainder(dividingBy: size.height)
            let x = x0 - y * 0.25
            var path = Path()
            path.move(to: CGPoint(x: x, y: y))
            path.addLine(to: CGPoint(x: x - 6, y: y + 24))
            context.stroke(path, with: .color(palette.dot.color.opacity(0.18)), lineWidth: 1.5)
        }
    }

    /// Soft cloud haze drifting across when it's cloudy, foggy or raining.
    @ViewBuilder
    private func haze(_ size: CGSize, t: Double) -> some View {
        let c = (condition ?? "").lowercased()
        if c.contains("cloud") || c.contains("fog") || c.contains("rain") || c.contains("pour") || c.contains("partly") {
            let strength = palette.darkInk ? 0.35 : 0.05
            ZStack {
                ForEach(0..<3) { i in
                    let speed = 6.0 + Double(i) * 3
                    let x = (Double(i) * 0.37 + t / (size.width / speed * 6)).truncatingRemainder(dividingBy: 1.4) - 0.2
                    Ellipse()
                        .fill(Color.white.opacity(strength))
                        .frame(width: size.width * 0.45, height: size.height * 0.14)
                        .blur(radius: 60)
                        .position(x: size.width * x, y: size.height * (0.08 + 0.07 * Double(i)))
                }
            }
        }
    }
}

// MARK: Chips

/// The status pills: problems, approvals (a count only), work, or all clear.
struct ChipRow: View {
    let chips: [StatusChip]
    let palette: LampPalette

    var body: some View {
        HStack(spacing: 14) {
            ForEach(chips) { chip in
                Label(chip.text, systemImage: chip.symbol)
                    .font(.caption.weight(.semibold))
                    .labelStyle(TintedIconLabel(icon: tone(chip.tone)))
                    .foregroundStyle(chip.tone == .attention ? palette.alert.color : palette.ink.color)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(palette.panel.color))
                    .overlay(Capsule().strokeBorder(chip.tone == .attention ? palette.alert.color : palette.panelEdge.color, lineWidth: 2))
                    .symbolEffect(.pulse, options: .repeating, isActive: chip.tone == .working)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.6), value: chips)
    }

    private func tone(_ tone: StatusChip.Tone) -> Color {
        switch tone {
        case .calm: return palette.accent.color
        case .working: return palette.warm.color
        case .attention: return palette.alert.color
        }
    }
}

// MARK: Now / Next

/// The hero card: the event on now (with how far through it is) or next
/// (with a live countdown), its time and place.
struct NowNextCard: View {
    let item: NowNext
    let now: Date
    let palette: LampPalette

    var body: some View {
        HStack(alignment: .center, spacing: 30) {
            ZStack {
                Circle().fill(palette.accent.color.opacity(0.14)).frame(width: 96, height: 96)
                Image(systemName: KioskIcons.agendaSymbol(item.title))
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(palette.accent.color)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(item.label.uppercased())
                    .font(.caption.weight(.bold))
                    .kerning(2)
                    .foregroundStyle(palette.inkDim.color)
                Text(item.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(palette.ink.color)
                    .lineLimit(1)
                HStack(spacing: 14) {
                    Text(item.countdown(now: now))
                        .font(.headline.weight(.bold))
                        .foregroundStyle(palette.accent.color)
                        .contentTransition(.numericText())
                        .monospacedDigit()
                    Text(detail).font(.callout).foregroundStyle(palette.inkDim.color).lineLimit(1).minimumScaleFactor(0.75)
                }
                if let progress = item.progress(now: now) {
                    GeometryReader { area in
                        Capsule().fill(palette.dot.color.opacity(0.35))
                            .overlay(alignment: .leading) {
                                Capsule().fill(palette.accent.color).frame(width: area.size.width * progress)
                            }
                    }
                    .frame(height: 8)
                    .padding(.top, 6)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(28)
        .background(RoundedRectangle(cornerRadius: 34, style: .continuous).fill(palette.panel.color))
        .overlay(RoundedRectangle(cornerRadius: 34, style: .continuous).strokeBorder(palette.accent.color, lineWidth: 3))
        .animation(.smooth(duration: 0.8), value: item.countdown(now: now))
    }

    /// "8:00 PM · Tender Greens".
    private var detail: String {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US")
        format.dateFormat = "h:mm a"
        var parts = [format.string(from: item.start)]
        if item.kind == .now, let end = item.end { parts = ["until \(format.string(from: end))"] }
        if let place = item.location { parts.append(place) }
        return parts.joined(separator: " · ")
    }
}

// MARK: Dots

/// Page dots, centred; the active one is a pill that fills while its card
/// is up, so the screen always shows something gently moving.
struct CardDots: View {
    let count: Int
    let active: Int
    let seconds: Double
    let palette: LampPalette
    @State private var fill: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            ForEach(0..<count, id: \.self) { index in
                if index == active {
                    Capsule().fill(palette.dot.color.opacity(0.45))
                        .frame(width: 56, height: 12)
                        .overlay(alignment: .leading) {
                            Capsule().fill(palette.ink.color).frame(width: 56 * (reduceMotion ? 1 : fill), height: 12)
                        }
                } else {
                    Circle().fill(palette.dot.color).frame(width: 12, height: 12)
                }
            }
        }
        .animation(.smooth(duration: 0.5), value: active)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
        .onAppear(perform: restart)
        .onChange(of: active) { _, _ in restart() }
    }

    private func restart() {
        fill = 0
        withAnimation(.linear(duration: seconds)) { fill = 1 }
    }
}

// MARK: Rows entering

/// Rows of a card come in one after another: up a little and fading in.
struct StaggerIn: ViewModifier {
    let index: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 14)
            .onAppear {
                withAnimation(.smooth(duration: 0.6).delay(0.25 + Double(index) * 0.08)) { shown = true }
            }
    }
}

extension View {
    /// Enters after the rows above it.
    func staggered(_ index: Int) -> some View { modifier(StaggerIn(index: index)) }
}
