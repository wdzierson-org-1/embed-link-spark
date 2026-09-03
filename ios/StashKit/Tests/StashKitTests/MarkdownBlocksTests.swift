import XCTest
@testable import StashKit

final class MarkdownBlocksTests: XCTestCase {
    // MARK: - parse: real-world fixture (Will's screenshot — farfetch summary)

    func testFarfetchSummaryFixture() {
        let text = """
        Key features include:

        - Brown tortoiseshell effect
        - Brand logo detailing
        - Round frame
        - Tinted lenses
        - Comes with a protective case

        These sunglasses pair well with **casual** and **smart-casual** outfits alike.
        """

        let blocks = MarkdownBlocks.parse(text)

        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks[0], .paragraph("Key features include:"))
        XCTAssertEqual(blocks[1], .bullets([
            "Brown tortoiseshell effect",
            "Brand logo detailing",
            "Round frame",
            "Tinted lenses",
            "Comes with a protective case",
        ]))
        if case .paragraph(let text) = blocks[2] {
            XCTAssertTrue(text.contains("**casual**"))
            XCTAssertTrue(text.contains("**smart-casual**"))
        } else {
            XCTFail("expected trailing paragraph, got \(blocks[2])")
        }
    }

    // MARK: - Numbered lists

    func testNumberedList() {
        let text = """
        Steps to set up:

        1. Unbox the device
        2. Charge for two hours
        3. Pair via Bluetooth
        """

        let blocks = MarkdownBlocks.parse(text)

        XCTAssertEqual(blocks, [
            .paragraph("Steps to set up:"),
            .numbered([
                "Unbox the device",
                "Charge for two hours",
                "Pair via Bluetooth",
            ]),
        ])
    }

    // MARK: - Inline bold survives inside paragraph text (for AttributedString(markdown:) later)

    func testBoldSurvivesInsideParagraph() {
        let blocks = MarkdownBlocks.parse("This is **bold** and this is *italic*.")

        XCTAssertEqual(blocks, [.paragraph("This is **bold** and this is *italic*.")])
    }

    // MARK: - Blank-line paragraph splitting

    func testBlankLineSplitsParagraphs() {
        let text = "First paragraph.\n\nSecond paragraph.\n\n\nThird paragraph after extra blank lines."

        let blocks = MarkdownBlocks.parse(text)

        XCTAssertEqual(blocks, [
            .paragraph("First paragraph."),
            .paragraph("Second paragraph."),
            .paragraph("Third paragraph after extra blank lines."),
        ])
    }

    func testConsecutiveLinesWithinAParagraphJoinWithASpace() {
        let text = "Line one\nLine two\nLine three"

        let blocks = MarkdownBlocks.parse(text)

        XCTAssertEqual(blocks, [.paragraph("Line one Line two Line three")])
    }

    // MARK: - CRLF input

    func testCRLFInput() {
        let text = "Paragraph one.\r\n\r\n- item one\r\n- item two\r\n"

        let blocks = MarkdownBlocks.parse(text)

        XCTAssertEqual(blocks, [
            .paragraph("Paragraph one."),
            .bullets(["item one", "item two"]),
        ])
    }

    // MARK: - Headings

    func testHeading() {
        let blocks = MarkdownBlocks.parse("## Section title\n\nBody text.")

        XCTAssertEqual(blocks, [
            .heading(level: 2, "Section title"),
            .paragraph("Body text."),
        ])
    }

    func testMoreThanSixHashesIsNotAHeading() {
        let blocks = MarkdownBlocks.parse("####### Not a heading")

        XCTAssertEqual(blocks, [.paragraph("####### Not a heading")])
    }

    // MARK: - Quote blocks

    func testQuoteBlock() {
        let blocks = MarkdownBlocks.parse("> A line of wisdom\n> continued on the next line.")

        XCTAssertEqual(blocks, [.quote("A line of wisdom continued on the next line.")])
    }

    // MARK: - Fenced code blocks

    func testFencedCodeBlock() {
        let text = """
        Here's a snippet:

        ```
        let x = 1
        let y = 2
        ```

        That's it.
        """

        let blocks = MarkdownBlocks.parse(text)

        XCTAssertEqual(blocks, [
            .paragraph("Here's a snippet:"),
            .code("let x = 1\nlet y = 2"),
            .paragraph("That's it."),
        ])
    }

    // MARK: - Bullet marker variants

    func testAsteriskAndDotBulletMarkersBothParse() {
        let blocks = MarkdownBlocks.parse("* first\n* second")
        XCTAssertEqual(blocks, [.bullets(["first", "second"])])

        let blocksDot = MarkdownBlocks.parse("• first\n• second")
        XCTAssertEqual(blocksDot, [.bullets(["first", "second"])])
    }

    // MARK: - looksLikeMarkdown

    func testLooksLikeMarkdownTrueForBulletLines() {
        XCTAssertTrue(MarkdownBlocks.looksLikeMarkdown("Some intro\n- item one\n- item two"))
    }

    func testLooksLikeMarkdownTrueForBoldMarkers() {
        XCTAssertTrue(MarkdownBlocks.looksLikeMarkdown("This has **bold** text in it."))
    }

    func testLooksLikeMarkdownTrueForHeadings() {
        XCTAssertTrue(MarkdownBlocks.looksLikeMarkdown("# Title\n\nBody"))
    }

    func testLooksLikeMarkdownTrueForLinks() {
        XCTAssertTrue(MarkdownBlocks.looksLikeMarkdown("Check out [this page](https://example.com) for more."))
    }

    func testLooksLikeMarkdownFalseForPlainProse() {
        XCTAssertFalse(MarkdownBlocks.looksLikeMarkdown("Just a normal sentence with no special formatting at all."))
    }

    func testLooksLikeMarkdownFalseForLoneAsteriskOrHyphenMidSentence() {
        // A hyphen used as a normal dash mid-sentence, and a lone asterisk, should not trip the heuristic.
        XCTAssertFalse(MarkdownBlocks.looksLikeMarkdown("Prices range from 10-20 dollars * plus tax."))
    }

    // MARK: - Performance / no quadratic blowup

    func testLargeInputParsesQuickly() {
        var lines: [String] = []
        for i in 0..<2000 {
            lines.append("Paragraph line number \(i) with some **bold** filler text to pad it out further.")
            if i % 10 == 0 {
                lines.append("")
                lines.append("- bullet item \(i)")
                lines.append("- another bullet item \(i)")
                lines.append("")
            }
        }
        let text = lines.joined(separator: "\n")
        XCTAssertGreaterThan(text.count, 100_000)

        let start = Date()
        let blocks = MarkdownBlocks.parse(text)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertFalse(blocks.isEmpty)
        XCTAssertLessThan(elapsed, 1.0, "parse of \(text.count) chars took \(elapsed)s — expected < 1s")
    }

    func testEmptyInputProducesNoBlocks() {
        XCTAssertEqual(MarkdownBlocks.parse(""), [])
        XCTAssertEqual(MarkdownBlocks.parse("   \n\n  "), [])
    }
}
