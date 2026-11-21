// His live words on Talk, fading in from left to right as they arrive
// (Dylan, 2026-11-21: "fading the words in, like it's sort of fading it from
// left to right … instead of being one word appearing at a time"). Only the
// new part sweeps in (JarvisKit FreshWords): words already shown never dim
// or flicker, and a revised word fades in whole. Settled words are solid,
// the tentative tail lighter, as before (HeardWords).
//
// One Text drawn by one TextRenderer: the fresh run is tagged, and the
// renderer sets each of its glyphs' opacity from a single animated
// progress, so there are no per-character views (cheap on the iPad).
// Reduce Motion: the fresh part simply fades in.
import SwiftUI
import JarvisKit

struct LiveWords: View {
    let text: String
    let stable: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Seconds a sweep takes (the web /talk page uses about the same).
    static let sweep: Double = {
        #if DEBUG
        // `-slowSweep`: ten times slower, to see a sweep mid-way.
        if ProcessInfo.processInfo.arguments.contains("-slowSweep") { return 3 }
        #endif
        return 0.3
    }()

    @State private var shown = ""
    @State private var freshFrom = Int.max
    @State private var progress: Double = 1

    var body: some View {
        let styled = LiveWords.styled(text, stable: stable, freshFrom: freshFrom)
        Group {
            if #available(iOS 18.0, *) {
                styled.textRenderer(SweepRenderer(progress: progress, plain: reduceMotion))
            } else {
                styled
            }
        }
        .onAppear { shown = text }
        .onChange(of: text) { old, new in
            let from = FreshWords.start(old: shown, new: new)
            shown = new
            guard from < new.count else { return }
            // Start from 0 with no animation, then sweep in the next turn of
            // the run loop: set together, SwiftUI would see 1 → 1 and skip it.
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) {
                freshFrom = from
                progress = 0
            }
            DispatchQueue.main.async {
                withAnimation(.linear(duration: LiveWords.sweep)) { progress = 1 }
            }
        }
    }

    /// The words as one Text: settled solid, tail light, the fresh part
    /// tagged for the renderer.
    static func styled(_ text: String, stable: Int?, freshFrom: Int) -> Text {
        let parts = HeardWords.split(text, stable: stable)
        // Rebuilt from the split so spacing matches what's drawn.
        let whole = parts.tail.isEmpty ? parts.settled : (parts.settled.isEmpty ? parts.tail : parts.settled + " " + parts.tail)
        let settledEnd = parts.settled.count
        let chars = Array(whole)
        let cut = min(max(freshFrom, 0), chars.count)
        // Pieces split at the settled/tail boundary and where fresh begins.
        var bounds = Set([0, chars.count, settledEnd, cut]).filter { $0 >= 0 && $0 <= chars.count }.sorted()
        if bounds.first != 0 { bounds.insert(0, at: 0) }
        var out = Text("")
        for (a, b) in zip(bounds, bounds.dropFirst()) where b > a {
            var piece = Text(String(chars[a..<b]))
            if a >= settledEnd, !parts.tail.isEmpty { piece = piece.foregroundColor(.white.opacity(HeardWords.tailOpacity)) }
            if a >= cut {
                if #available(iOS 18.0, *) { piece = piece.customAttribute(Fresh()) }
            }
            out = out + piece
        }
        return out
    }
}

/// Marks the fresh run.
@available(iOS 18.0, *)
private struct Fresh: TextAttribute {}

/// Draws the text; the fresh run's glyphs fade in one after another from
/// left to right (reading order, across lines) as `progress` runs 0 → 1.
@available(iOS 18.0, *)
private struct SweepRenderer: TextRenderer, Animatable {
    var progress: Double
    var plain: Bool
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    /// How much of the sweep each glyph takes to come in: a soft edge.
    private let edge = 0.35

    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        // How many fresh glyphs there are, so each knows its place.
        var total = 0
        for line in layout { for run in line where run[Fresh.self] != nil { total += run.count } }
        var index = 0
        for line in layout {
            for run in line {
                guard run[Fresh.self] != nil, progress < 1 else {
                    ctx.draw(run)
                    continue
                }
                for slice in run {
                    var c = ctx
                    if plain {
                        c.opacity = progress
                    } else {
                        let at = Double(index) / Double(max(total, 1)) * (1 - edge)
                        c.opacity = min(1, max(0, (progress - at) / edge))
                    }
                    c.draw(slice)
                    index += 1
                }
            }
        }
    }
}
