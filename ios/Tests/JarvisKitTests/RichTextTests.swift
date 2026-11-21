// The page's markdown tests (tests/unit/markdown.test.ts), ported so the
// app and the page read Jarvis's replies the same way.
import XCTest
@testable import JarvisKit

final class RichTextTests: XCTestCase {
    func testAPlainReplyIsOneParagraphWithItsLineBreaks() {
        XCTAssertEqual(RichText.parse("It is 64°.\nClear tonight."), [.paragraph([.text("It is 64°.\nClear tonight.")])])
    }

    func testHeadingsListsADividerAndParagraphs() {
        let blocks = RichText.parse("## Today\n- Church 10 AM\n- Golf 2 PM\n\n---\n1. First\n2. Second\n\nDone.")
        XCTAssertEqual(blocks.count, 5)
        XCTAssertEqual(blocks[0], .heading(level: 2, spans: [.text("Today")]))
        XCTAssertEqual(blocks[1], .list(ordered: false, items: [[.text("Church 10 AM")], [.text("Golf 2 PM")]]))
        XCTAssertEqual(blocks[2], .rule)
        XCTAssertEqual(blocks[3], .list(ordered: true, items: [[.text("First")], [.text("Second")]]))
        XCTAssertEqual(blocks[4], .paragraph([.text("Done.")]))
    }

    func testAPipeTableWithAHeaderRow() {
        XCTAssertEqual(RichText.parse("| Item | Price |\n|---|---:|\n| A30 | $900 |\n| A20 | **$650** |"), [
            .table(header: [[.text("Item")], [.text("Price")]],
                   rows: [[[.text("A30")], [.text("$900")]], [[.text("A20")], [.bold("$650")]]]),
        ])
    }

    func testFencedCodeStaysAsIs() {
        XCTAssertEqual(RichText.parse("Run:\n```\n# a comment\n- not a list\n```"), [
            .paragraph([.text("Run:")]),
            .code("# a comment\n- not a list"),
        ])
    }

    func testHTMLIsNeverMarkup() {
        XCTAssertEqual(RichText.parse("<b>hi</b>"), [.paragraph([.text("<b>hi</b>")])])
    }

    func testInlineStylesAndStrayStars() {
        XCTAssertEqual(RichText.spans("**Bold** and *soft* with `code` at [Bose](https://bose.com/x) 5*3"), [
            .bold("Bold"), .text(" and "), .italic("soft"), .text(" with "), .code("code"),
            .text(" at "), .link("Bose", href: "https://bose.com/x"), .text(" 5*3"),
        ])
    }

    /// Half-written replies (still streaming) read sensibly, never crash.
    func testHalfWrittenMarkupStaysPlain() {
        XCTAssertEqual(RichText.parse("- **Bose QC"), [.list(ordered: false, items: [[.text("**Bose QC")]])])
        XCTAssertEqual(RichText.parse("Code:\n```\nlet x"), [.paragraph([.text("Code:")]), .code("let x")])
        XCTAssertEqual(RichText.parse("| a | b |"), [.paragraph([.text("| a | b |")])])
    }
}
