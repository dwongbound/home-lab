// Jarvis's replies as rich text (Dylan, 2026-11-20: "can we also make the
// chat and the chaat from the talk tab support rich text"). The native twin
// of the home page's src/lib/markdown.ts: headings, paragraphs, bullet and
// numbered lists, pipe tables, dividers, fenced code and, inline, bold,
// italic, code and links. No HTML is ever read as markup. Keep the two in
// step; the page's unit tests are ported in RichTextTests.
import Foundation

public enum RichText {
    /// One piece of a line: plain words, or words with one style on them.
    public enum Span: Equatable, Sendable {
        case text(String)
        case bold(String)
        case italic(String)
        case code(String)
        case link(String, href: String)
    }

    /// One block of a reply.
    public enum Block: Equatable, Sendable {
        case heading(level: Int, spans: [Span])
        case paragraph([Span])
        case list(ordered: Bool, items: [[Span]])
        case table(header: [[Span]], rows: [[[Span]]])
        case rule
        case code(String)
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern)
    }
    nonisolated(unsafe) private static let heading = regex(#"^(#{1,3})\s+(.*)$"#)
    nonisolated(unsafe) private static let bullet = regex(#"^\s*[-*•]\s+(.*)$"#)
    nonisolated(unsafe) private static let numbered = regex(#"^\s*\d+[.)]\s+(.*)$"#)
    nonisolated(unsafe) private static let rule = regex(#"^\s*(-{3,}|\*{3,}|_{3,})\s*$"#)
    nonisolated(unsafe) private static let fence = regex(#"^\s*```"#)
    nonisolated(unsafe) private static let tableRow = regex(#"^\s*\|.*\|\s*$"#)
    nonisolated(unsafe) private static let tableDivider = regex(#"^\s*\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?\s*$"#)
    nonisolated(unsafe) private static let inline = regex(#"(\*\*(.+?)\*\*|__(.+?)__|`([^`]+)`|\[([^\]]+)\]\((https?://[^\s)]+)\)|(?<![\w*])\*([^*\n]+)\*(?![\w*])|(?<![\w_])_([^_\n]+)_(?![\w_]))"#)

    private static func test(_ re: NSRegularExpression, _ line: String) -> Bool {
        re.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
    }

    /// The capture groups of a whole-line match, or nil.
    private static func groups(_ re: NSRegularExpression, _ line: String) -> [String?]? {
        guard let m = re.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else { return nil }
        return (0..<m.numberOfRanges).map { Range(m.range(at: $0), in: line).map { String(line[$0]) } }
    }

    /// Reads a whole reply into blocks. Plain text comes back as paragraphs, line breaks kept.
    public static func parse(_ text: String) -> [Block] {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var blocks: [Block] = []
        var paragraph: [String] = []

        func flush() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(spans(paragraph.joined(separator: "\n"))))
            paragraph = []
        }

        var i = 0
        while i < lines.count {
            let line = lines[i]
            if test(fence, line) {
                flush()
                var code: [String] = []
                i += 1
                while i < lines.count && !test(fence, lines[i]) { code.append(lines[i]); i += 1 }
                blocks.append(.code(code.joined(separator: "\n")))
                i += 1
                continue
            }
            if line.trimmingCharacters(in: .whitespaces).isEmpty { flush(); i += 1; continue }
            if test(rule, line) { flush(); blocks.append(.rule); i += 1; continue }
            if let g = groups(heading, line), let marks = g[1], let words = g[2] {
                flush()
                blocks.append(.heading(level: marks.count, spans: spans(words.trimmingCharacters(in: .whitespaces))))
                i += 1
                continue
            }
            if test(tableRow, line), i + 1 < lines.count, test(tableDivider, lines[i + 1]) {
                flush()
                let header = splitRow(line)
                var rows: [[[Span]]] = []
                i += 2
                while i < lines.count && test(tableRow, lines[i]) { rows.append(splitRow(lines[i])); i += 1 }
                blocks.append(.table(header: header, rows: rows))
                continue
            }
            let isBullet = test(bullet, line)
            if isBullet || test(numbered, line) {
                flush()
                let re = isBullet ? bullet : numbered
                var items: [[Span]] = []
                while i < lines.count, let g = groups(re, lines[i]), let words = g[1] {
                    items.append(spans(words.trimmingCharacters(in: .whitespaces)))
                    i += 1
                }
                blocks.append(.list(ordered: !isBullet, items: items))
                continue
            }
            paragraph.append(line)
            i += 1
        }
        flush()
        return blocks
    }

    /// The cells of one "| a | b |" table line.
    private static func splitRow(_ line: String) -> [[Span]] {
        var inner = line.trimmingCharacters(in: .whitespaces)
        if inner.hasPrefix("|") { inner.removeFirst() }
        if inner.hasSuffix("|") { inner.removeLast() }
        return inner.split(separator: "|", omittingEmptySubsequences: false).map { spans($0.trimmingCharacters(in: .whitespaces)) }
    }

    /// Reads bold, italic, code and links out of one run of text.
    public static func spans(_ text: String) -> [Span] {
        var out: [Span] = []
        let ns = text as NSString
        var last = 0
        for m in inline.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            if m.range.location > last { out.append(.text(ns.substring(with: NSRange(location: last, length: m.range.location - last)))) }
            func g(_ n: Int) -> String? { m.range(at: n).location == NSNotFound ? nil : ns.substring(with: m.range(at: n)) }
            if let bold = g(2) ?? g(3) { out.append(.bold(bold)) }
            else if let code = g(4) { out.append(.code(code)) }
            else if let label = g(5), let href = g(6) { out.append(.link(label, href: href)) }
            else { out.append(.italic(g(7) ?? g(8) ?? "")) }
            last = m.range.location + m.range.length
        }
        if last < ns.length { out.append(.text(ns.substring(from: last))) }
        // Bare web addresses in the plain words become links too (Dylan,
        // 2026-11-25: "links should be clickable in chat on the app").
        return out.flatMap { span -> [Span] in
            guard case .text(let words) = span else { return [span] }
            return autolinked(words)
        }
    }

    /// Plain words with every bare "https://…" address as a link.
    static func autolinked(_ words: String) -> [Span] {
        var out: [Span] = []
        var last = words.startIndex
        for range in bareLinks(in: words) {
            if range.lowerBound > last { out.append(.text(String(words[last..<range.lowerBound]))) }
            let address = String(words[range])
            out.append(.link(address, href: address))
            last = range.upperBound
        }
        if last < words.endIndex { out.append(.text(String(words[last...]))) }
        return out.isEmpty ? [.text(words)] : out
    }

    nonisolated(unsafe) private static let bare = regex(#"https?://[^\s<>"'`]+"#)

    /// Where the bare web addresses are in some words. Punctuation that ends
    /// a sentence is left out ("see https://x.com." links x.com), and so is
    /// a closing bracket the address didn't open.
    public static func bareLinks(in words: String) -> [Range<String.Index>] {
        let ns = words as NSString
        var out: [Range<String.Index>] = []
        for m in bare.matches(in: words, range: NSRange(location: 0, length: ns.length)) {
            guard var range = Range(m.range, in: words) else { continue }
            while range.upperBound > range.lowerBound {
                let last = words[words.index(before: range.upperBound)]
                let candidate = words[range]
                let unopened = (last == ")" && !candidate.contains("(")) || (last == "]" && !candidate.contains("["))
                if ".,;:!?*_".contains(last) || unopened {
                    range = range.lowerBound..<words.index(before: range.upperBound)
                } else {
                    break
                }
            }
            // Just the scheme left ("https://"): not an address.
            if words[range].hasSuffix("//") { continue }
            out.append(range)
        }
        return out
    }
}
