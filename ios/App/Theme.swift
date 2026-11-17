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

/// A frosted panel like the home page's `.glass`. On iOS 26 and later it's
/// Apple's Liquid Glass (it bends the sky behind it); before that, a
/// translucent material with a hairline edge.
struct GlassPanel: ViewModifier {
    var tint: Color? = nil
    var radius: CGFloat = 22

    /// Rounded glass; tinted for approvals and offers.
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
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
    func glassPanel(tint: Color? = nil, radius: CGFloat = 22) -> some View { modifier(GlassPanel(tint: tint, radius: radius)) }
}
