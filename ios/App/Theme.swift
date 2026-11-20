// The home page's colours (src/styles.css :root), so the app and the page
// look like one thing.
import SwiftUI

enum Theme {
    /// The room: page base.
    static let basalt = Color(red: 0x16 / 255, green: 0x21 / 255, blue: 0x2c / 255)
    /// Text.
    static let frost = Color(red: 0xf2 / 255, green: 0xef / 255, blue: 0xe9 / 255)
    static let frostDim = frost.opacity(0.66)
    static let frostFaint = frost.opacity(0.42)
    /// Data accent, Jarvis's blue, local-model chip.
    static let glacier = Color(red: 0x8e / 255, green: 0xc5 / 255, blue: 0xea / 255)
    /// The sun; approvals, working, Claude's chip.
    static let ember = Color(red: 0xe8 / 255, green: 0xb0 / 255, blue: 0x6a / 255)
    /// Running, connected.
    static let moss = Color(red: 0x93 / 255, green: 0xd6 / 255, blue: 0xae / 255)
    /// Failed, down, denied.
    static let rose = Color(red: 0xf0 / 255, green: 0x91 / 255, blue: 0x9a / 255)
    /// Dylan's own chat bubbles.
    static let userBubble = Color(red: 0x3f / 255, green: 0x78 / 255, blue: 0xa3 / 255)
    /// Glass panels over the sky.
    static let glass = Color.white.opacity(0.075)
    static let glassEdge = Color.white.opacity(0.16)

    /// The top colour of the sky, for fades over it.
    static let skyTop = Color(red: 0x0f / 255, green: 0x17 / 255, blue: 0x26 / 255)

    /// The night sky behind every screen.
    static let sky = LinearGradient(
        colors: [
            Color(red: 0x0f / 255, green: 0x17 / 255, blue: 0x26 / 255),
            Color(red: 0x1d / 255, green: 0x2a / 255, blue: 0x40 / 255),
            basalt,
        ],
        startPoint: .top,
        endPoint: .bottom
    )
}

/// How much the app spends drawing glass, decided once at launch (Dylan,
/// 2026-11-20: his 2018 iPad Pro hitched where the iPhone didn't, and the
/// trace blamed GPU work, 20-40 offscreen passes a frame). Liquid Glass
/// samples and bends what's behind it, several passes per element, every
/// frame something moves under it. The iPad draws cards as flat tinted
/// panels and floating controls as one plain frosted pass; the iPhone keeps
/// the full look. `-lightGlass` / `-fullGlass` force either (debug builds).
enum RenderQuality {
    static let light: Bool = {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-lightGlass") { return true }
        if args.contains("-fullGlass") { return false }
        #endif
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .pad
        #else
        return false
        #endif
    }()
}

/// A frosted panel like the home page's `.glass`. On iOS 26 and later it's
/// Apple's Liquid Glass (it bends the sky behind it); before that, a
/// translucent material with a hairline edge.
struct GlassPanel: ViewModifier {
    var tint: Color? = nil
    var radius: CGFloat = 22
    /// Floats over moving content (the tab bar): on the light path it stays
    /// frosted, so what scrolls under it doesn't show through.
    var floating = false

    /// Rounded glass; tinted for approvals and offers.
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if RenderQuality.light {
            if floating {
                frosted(content, shape: shape)
            } else {
                // A card: the same tint, corner and hairline edge, no blur.
                content
                    .background(shape.fill(tint.map { $0.opacity(0.17) } ?? Color.white.opacity(0.085)))
                    .overlay(shape.strokeBorder(tint.map { $0.opacity(0.4) } ?? Theme.glassEdge.opacity(0.8), lineWidth: 0.5))
            }
        } else {
            glass(content, shape: shape)
        }
    }

    @ViewBuilder
    private func glass(_ content: Content, shape: RoundedRectangle) -> some View {
        // Liquid Glass only exists in the iOS 26 SDK (Swift 6.2 and later),
        // so older Xcodes, like CI's, must not even see the call.
        #if compiler(>=6.2)
        if #available(iOS 26.0, watchOS 26.0, tvOS 26.0, *) {
            content
                .glassEffect(.regular.tint(tint.map { $0.opacity(0.18) } ?? Color.white.opacity(0.02)), in: shape)
                .overlay(shape.strokeBorder(tint.map { $0.opacity(0.35) } ?? Theme.glassEdge.opacity(0.6), lineWidth: 0.5))
        } else {
            frosted(content, shape: shape)
        }
        #else
        frosted(content, shape: shape)
        #endif
    }

    /// The look before Liquid Glass: a translucent material with a hairline edge.
    private func frosted(_ content: Content, shape: RoundedRectangle) -> some View {
        content
            .background(shape.fill(tint.map { $0.opacity(0.10) } ?? Theme.glass))
            .background(.ultraThinMaterial.opacity(0.6), in: shape)
            .overlay(shape.strokeBorder(tint.map { $0.opacity(0.45) } ?? Theme.glassEdge))
    }
}

extension View {
    /// Wraps the view in a glass panel.
    func glassPanel(tint: Color? = nil, radius: CGFloat = 22, floating: Bool = false) -> some View {
        modifier(GlassPanel(tint: tint, radius: radius, floating: floating))
    }
}

/// A small floating glass control (the notices pill, the gear, the status
/// chip): real Liquid Glass where the system has it, frosted otherwise.
/// Shapes are fixed, so no shadow or layout changes while scrolling.
struct GlassChip<S: Shape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if RenderQuality.light {
            // One plain frosted pass instead of Liquid Glass's several.
            content.background(.ultraThinMaterial, in: shape).overlay(shape.stroke(Theme.glassEdge, lineWidth: 0.5))
        } else if #available(iOS 26.0, watchOS 26.0, tvOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content.background(.ultraThinMaterial, in: shape).overlay(shape.stroke(Theme.glassEdge, lineWidth: 0.5))
        }
        #else
        content.background(.ultraThinMaterial, in: shape).overlay(shape.stroke(Theme.glassEdge, lineWidth: 0.5))
        #endif
    }
}

extension View {
    func glassChip<S: Shape>(_ shape: S) -> some View { modifier(GlassChip(shape: shape)) }

}

/// The height the floating status takes, for content to start below it.
enum FloatingStatus {
    static let room: CGFloat = 56
}

/// A soft fade at the very top of a scrolling page, under the floating
/// buttons, so text passing beneath them stays out of the way. A plain
/// gradient layer: no mask, no blur.
struct TopFade: View {
    var body: some View {
        LinearGradient(stops: [
            .init(color: Theme.skyTop.opacity(0.95), location: 0),
            .init(color: Theme.skyTop.opacity(0.75), location: 0.55),
            .init(color: Theme.skyTop.opacity(0), location: 1),
        ], startPoint: .top, endPoint: .bottom)
            // From the very top of the screen (the pages run edge to edge)
            // to just under the floating buttons.
            .frame(height: 122)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
    }
}

/// Glass cards drawn together (one glass pass for the group where the
/// system offers it), rather than each card blurring on its own: the device
/// trace showed about 60 offscreen render passes per frame on Home.
struct GlassGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        #if compiler(>=6.2)
        if !RenderQuality.light, #available(iOS 26.0, watchOS 26.0, tvOS 26.0, *) {
            GlassEffectContainer { content() }
        } else {
            content()
        }
        #else
        content()
        #endif
    }
}

/// One row style for every list and form in the app (Dylan, 2026-11-20:
/// "standardize throughout the app how thick these rows are" and "those
/// divider lines should go all the way across"). Apple's grouped-list
/// conventions: rows at least 44 pt (the system's own insets supply the
/// padding, so a row adds no height of its own and still grows with
/// Dynamic Type), and each separator running the card's full width.
enum Rows {
    static let minHeight: CGFloat = 44
    /// How far a grouped row's content sits in from its card's edges.
    static let inset: CGFloat = 20
}

extension View {
    /// On a List or Form: 44 pt minimum rows.
    func jarvisRows() -> some View {
        environment(\.defaultMinListRowHeight, Rows.minHeight)
    }

    /// On a Section (or a row): its separators run the card's full width.
    /// (iOS only; the Watch and TV keep their own list styles.)
    @ViewBuilder
    func fullWidthSeparators() -> some View {
        #if os(iOS)
        self
            // A grouped row's content sits Rows.inset in from each side of
            // its card; the line reaches back out to both edges.
            .alignmentGuide(.listRowSeparatorLeading) { d in d[.leading] - Rows.inset }
            .alignmentGuide(.listRowSeparatorTrailing) { d in d[.trailing] + Rows.inset }
        #else
        self
        #endif
    }
}
