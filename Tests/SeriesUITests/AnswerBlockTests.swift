import XCTest
@testable import SeriesUI

/// Answers used to render their own markup: a model that wrote `### 常見搭配`
/// and a bulleted list put `###` and `-` on screen as characters. This splits
/// the text into blocks so each can be drawn as what it is.
///
/// It runs against text that is still arriving, so the half-written cases
/// matter as much as the finished ones.
final class AnswerBlockTests: XCTestCase {
    func testPlainProseIsOneParagraph() {
        XCTAssertEqual(
            SeriesAnswer.blocks("Just a sentence."),
            [.paragraph("Just a sentence.")]
        )
    }

    /// Streamed text carries its own line breaks, and a paragraph has to keep
    /// them — that behaviour predates this parser and readers rely on it.
    func testLinesWithinAParagraphStayTogether() {
        XCTAssertEqual(
            SeriesAnswer.blocks("first line\nsecond line"),
            [.paragraph("first line\nsecond line")]
        )
    }

    func testBlankLinesSeparateParagraphs() {
        XCTAssertEqual(
            SeriesAnswer.blocks("one\n\ntwo"),
            [.paragraph("one"), .paragraph("two")]
        )
    }

    func testHeadingsCarryTheirLevel() {
        XCTAssertEqual(
            SeriesAnswer.blocks("# Big\n## Medium\n###### Small"),
            [
                .heading(level: 1, text: "Big"),
                .heading(level: 2, text: "Medium"),
                .heading(level: 6, text: "Small"),
            ]
        )
    }

    /// `#hashtag` and `#1` are ordinary text. Only `# ` opens a heading.
    func testAHashWithoutASpaceIsNotAHeading() {
        XCTAssertEqual(SeriesAnswer.blocks("#hashtag"), [.paragraph("#hashtag")])
        XCTAssertEqual(SeriesAnswer.blocks("####### seven"), [.paragraph("####### seven")])
    }

    func testBulletsInAllThreeMarkers() {
        for marker in ["-", "*", "+"] {
            XCTAssertEqual(
                SeriesAnswer.blocks("\(marker) an item"),
                [.bullet(depth: 0, text: "an item")],
                "marker \(marker)"
            )
        }
    }

    func testNestedBulletsCarryDepth() {
        let blocks = SeriesAnswer.blocks("- top\n  - nested\n    - deeper")
        XCTAssertEqual(blocks, [
            .bullet(depth: 0, text: "top"),
            .bullet(depth: 1, text: "nested"),
            .bullet(depth: 2, text: "deeper"),
        ])
    }

    func testNumberedItemsKeepTheirOwnMarker() {
        XCTAssertEqual(
            SeriesAnswer.blocks("1. first\n2. second\n10) tenth"),
            [
                .numbered(marker: "1.", depth: 0, text: "first"),
                .numbered(marker: "2.", depth: 0, text: "second"),
                .numbered(marker: "10)", depth: 0, text: "tenth"),
            ]
        )
    }

    /// A sentence that happens to start with a year isn't a list.
    func testANumberWithoutAListMarkerIsProse() {
        XCTAssertEqual(
            SeriesAnswer.blocks("2026 was the year."),
            [.paragraph("2026 was the year.")]
        )
    }

    func testFencedCodeKeepsItsContentVerbatim() {
        let text = """
        Here:

        ```swift
        let x = 1
          indented()
        ```

        Done.
        """
        XCTAssertEqual(SeriesAnswer.blocks(text), [
            .paragraph("Here:"),
            .code(language: "swift", text: "let x = 1\n  indented()"),
            .paragraph("Done."),
        ])
    }

    func testAFenceWithoutALanguageStillParses() {
        XCTAssertEqual(
            SeriesAnswer.blocks("```\nplain\n```"),
            [.code(language: nil, text: "plain")]
        )
    }

    /// Markup inside a fence is content, not structure — a shell comment must
    /// not become a heading.
    func testMarkupInsideAFenceIsNotParsed() {
        XCTAssertEqual(
            SeriesAnswer.blocks("```\n# not a heading\n- not a bullet\n```"),
            [.code(language: nil, text: "# not a heading\n- not a bullet")]
        )
    }

    /// Mid-stream: the opening fence has arrived and the closing one hasn't.
    /// The code so far is what the reader should see — waiting would blank the
    /// rest of the answer for as long as the block takes to finish.
    func testAnUnclosedFenceRendersWhatHasArrived() {
        XCTAssertEqual(
            SeriesAnswer.blocks("```python\nprint(1)\nprint(2)"),
            [.code(language: "python", text: "print(1)\nprint(2)")]
        )
    }

    /// The same idea one character earlier: three backticks and nothing else
    /// yet. It must not throw away the paragraph above it.
    func testABareOpeningFenceKeepsTheTextBeforeIt() {
        XCTAssertEqual(
            SeriesAnswer.blocks("Here is code:\n```"),
            [.paragraph("Here is code:"), .code(language: nil, text: "")]
        )
    }

    func testHorizontalRules() {
        XCTAssertEqual(
            SeriesAnswer.blocks("above\n\n---\n\nbelow"),
            [.paragraph("above"), .rule, .paragraph("below")]
        )
    }

    /// Inline markup stays in the text: `SeriesAnswer.markdown` renders it per block,
    /// so stripping it here would lose the bold the model asked for.
    func testInlineMarkupIsLeftForTheInlineRenderer() {
        XCTAssertEqual(
            SeriesAnswer.blocks("- **bold** and `code`"),
            [.bullet(depth: 0, text: "**bold** and `code`")]
        )
    }

    /// The shape a real answer to "compare these synonyms" actually arrives in.
    func testATypicalStructuredAnswer() {
        let text = """
        **pushback** means resistance to a proposal.

        ## 常見搭配

        - face pushback
        - considerable pushback

        1. Formal register
        2. Common in business writing
        """
        XCTAssertEqual(SeriesAnswer.blocks(text), [
            .paragraph("**pushback** means resistance to a proposal."),
            .heading(level: 2, text: "常見搭配"),
            .bullet(depth: 0, text: "face pushback"),
            .bullet(depth: 0, text: "considerable pushback"),
            .numbered(marker: "1.", depth: 0, text: "Formal register"),
            .numbered(marker: "2.", depth: 0, text: "Common in business writing"),
        ])
    }

    func testEmptyTextProducesNoBlocks() {
        XCTAssertEqual(SeriesAnswer.blocks(""), [])
        XCTAssertEqual(SeriesAnswer.blocks("\n\n"), [])
    }

    /// Every prefix of an answer has to parse — that is precisely the sequence
    /// a reader watches go by while it streams.
    func testEveryPrefixOfAnAnswerParsesWithoutLosingTheText() {
        let full = "# Title\n\nSome prose.\n\n- one\n- two\n\n```swift\ncode()\n```\n\nEnd."
        for length in 1...full.count {
            let partial = String(full.prefix(length))
            let blocks = SeriesAnswer.blocks(partial)
            // Nothing is dropped silently: some block must exist for any
            // prefix that contains a non-whitespace character.
            if partial.contains(where: { !$0.isWhitespace && $0 != "#" && $0 != "`" && $0 != "-" }) {
                XCTAssertFalse(blocks.isEmpty, "prefix of length \(length) produced nothing")
            }
        }
    }
}
