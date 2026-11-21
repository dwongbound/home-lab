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
    /// The web Talk page's sweep: 320 ms, ease-out, once per new word.
    static let sweep: Double = {
        #if DEBUG
        // `-slowSweep`: ten times slower, to see a sweep mid-way.
        if ProcessInfo.processInfo.arguments.contains("-slowSweep") { return 3.2 }
        #endif
        return 0.32
    }()

    @State private var shown = ""
    @State private var freshFrom = Int.max
    @State private var progress: Double = 1

    var body: some View {
        let styled = LiveWords.styled(text, stable: stable, freshFrom: freshFrom)
        Group {
            if #available(iOS 18.0, *) {
                styled.textRenderer(SweepRenderer(progress: progress))
            } else {
                styled
            }
        }
        .onAppear { shown = text }
        .onChange(of: text) { old, new in
            let from = FreshWords.firstNew(old: shown, new: new)
            shown = new
            // Reduce Motion: no animation at all (as the page).
            guard !reduceMotion, from < new.split(whereSeparator: \.isWhitespace).count else { return }
            // Start from 0 with no animation, then sweep in the next turn of
            // the run loop: set together, SwiftUI would see 1 → 1 and skip it.
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) {
                freshFrom = from
                progress = 0
            }
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: LiveWords.sweep)) { progress = 1 }
            }
        }
    }

    /// The words as one Text: settled solid, tail at 0.55, and each new
    /// word (from word index `freshFrom`) tagged on its own so it gets its
    /// own sweep.
    static func styled(_ text: String, stable: Int?, freshFrom: Int) -> Text {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        let settled = min(max(stable ?? 0, 0), words.count)
        var out = Text("")
        for (i, word) in words.enumerated() {
            var piece = Text((i == 0 ? "" : " ") + word)
            if i >= settled { piece = piece.foregroundColor(.white.opacity(HeardWords.tailOpacity)) }
            if i >= freshFrom, #available(iOS 18.0, *) { piece = piece.customAttribute(Fresh(word: i)) }
            out = out + piece
        }
        return out
    }
}

/// Marks the fresh run.
@available(iOS 18.0, *)
private struct Fresh: TextAttribute {
    /// Its place in the line, so neighbouring new words stay separate runs.
    let word: Int
}

/// Draws the text; each new word is revealed by a soft edge sweeping left
/// to right across it as `progress` runs 0 → 1 (the web page's mask: a
/// gradient opaque at 40% and clear at 60% of a mask three words wide,
/// slid from 100% to 0).
@available(iOS 18.0, *)
private struct SweepRenderer: TextRenderer, Animatable {
    var progress: Double
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        for line in layout {
            for run in line {
                guard run[Fresh.self] != nil, progress < 1 else {
                    ctx.draw(run)
                    continue
                }
                // The word's glyphs, left to right: the soft edge (0.6 of the
                // word wide, as 20% of a 3× mask) moves from before its
                // start to past its end.
                let count = max(run.count, 1)
                let edge = -0.6 + progress * 2.2
                for (i, slice) in run.enumerated() {
                    let at = (Double(i) + 0.5) / Double(count)
                    var c = ctx
                    c.opacity = min(1, max(0, (edge - at) / 0.6 + 0.5))
                    c.draw(slice)
                }
            }
        }
    }
}
