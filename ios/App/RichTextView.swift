// Jarvis's replies drawn as rich text, in Chat and on Talk (Dylan,
// 2026-11-20: "make the chat and the chaat from the talk tab support rich
// text"), the way the home page's Markdown component draws them: headings,
// lists, bold, italic, code, links, code blocks, dividers and tables. Parsed
// by JarvisKit RichText, once per text (cached), never on a redraw; a reply
// still streaming is parsed afresh as it grows, and half-written markup just
// reads as plain words until it closes. Links to Jarvis's reports open in
// the app's reader and web links in an in-app Safari view (the openURL
// handler in RootView). Bare addresses link too.
import SwiftUI
import JarvisKit

/// Parsed replies, kept so scrolling past a bubble again doesn't parse it again.
final class RichTextCache: @unchecked Sendable {
    static let shared = RichTextCache()
    private let cache: NSCache<NSString, Box> = {
        let c = NSCache<NSString, Box>()
        c.countLimit = 400
        return c
    }()
    private final class Box { let blocks: [RichText.Block]; init(_ b: [RichText.Block]) { blocks = b } }

    func blocks(_ text: String) -> [RichText.Block] {
        if let hit = cache.object(forKey: text as NSString) { return hit.blocks }
        #if DEBUG
        PerfCount.bump("markdown")
        #endif
        let blocks = RichText.parse(text)
        cache.setObject(Box(blocks), forKey: text as NSString)
        return blocks
    }
}

struct RichTextView: View {
    let text: String

    var body: some View {
        let blocks = RichTextCache.shared.blocks(text)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                RichBlockView(block: block)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        // Links in the app's blue.
        .tint(Theme.glacier)
    }

    /// One line's spans as styled text.
    static func attributed(_ spans: [RichText.Span]) -> AttributedString {
        var out = AttributedString()
        for span in spans {
            switch span {
            case .text(let words):
                out += AttributedString(words)
            case .bold(let words):
                var piece = AttributedString(words)
                piece.inlinePresentationIntent = .stronglyEmphasized
                out += piece
            case .italic(let words):
                var piece = AttributedString(words)
                piece.inlinePresentationIntent = .emphasized
                out += piece
            case .code(let words):
                var piece = AttributedString(words)
                piece.inlinePresentationIntent = .code
                out += piece
            case .link(let words, let href):
                var piece = AttributedString(words)
                piece.link = URL(string: href)
                // Underlined, so a link reads as one without colour alone.
                piece.underlineStyle = .single
                out += piece
            }
        }
        return out
    }
}

private struct RichBlockView: View {
    let block: RichText.Block

    var body: some View {
        switch block {
        case .heading(let level, let spans):
            Text(RichTextView.attributed(spans))
                .font(level == 1 ? .title3.weight(.bold) : level == 2 ? .headline : .subheadline.weight(.semibold))
                .padding(.top, 2)
        case .paragraph(let spans):
            Text(RichTextView.attributed(spans))
        case .list(let ordered, let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(ordered ? "\(index + 1)." : "•")
                            .foregroundStyle(Theme.frostDim)
                            .monospacedDigit()
                        Text(RichTextView.attributed(item))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        case .table(let header, let rows):
            // Wider than the bubble: it scrolls sideways inside it.
            ScrollView(.horizontal, showsIndicators: false) {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                    GridRow {
                        ForEach(Array(header.enumerated()), id: \.offset) { _, cell in
                            Text(RichTextView.attributed(cell)).fontWeight(.semibold).fixedSize()
                        }
                    }
                    Divider().overlay(Theme.glassEdge)
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        GridRow {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                                Text(RichTextView.attributed(cell)).fixedSize()
                            }
                        }
                    }
                }
                .font(.subheadline)
                .padding(.vertical, 2)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        case .rule:
            Rectangle().fill(Theme.glassEdge).frame(height: 1).padding(.vertical, 2)
        case .code(let code):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.footnote, design: .monospaced))
                    .fixedSize()
                    .padding(10)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.25)))
        }
    }
}
