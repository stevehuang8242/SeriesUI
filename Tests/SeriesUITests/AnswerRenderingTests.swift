import AppKit

import XCTest
@testable import SeriesUI

/// The answer used to be a column of `Text` views, one per block, and SwiftUI
/// scopes selection to a single one — so a drag could never cross from a
/// heading into the paragraph under it. These cover the properties that make
/// the one-text-view rendering a replacement rather than a rewrite: every
/// block still ends up in ONE string, and each still looks like what it is.
final class AnswerRenderingTests: XCTestCase {
    private let style = AnswerTextStyle(
        theme: SeriesTheme(appearance: .dark),
        typeScale: .reading,
        textScale: .standard,
        typeface: .standard
    )

    private func render(_ text: String) -> NSAttributedString {
        AnswerRenderer.attributed(text, style: style)
    }

    // MARK: The point of the exercise

    /// One string, so one selection can run the length of it.
    func testEveryBlockLandsInOneString() {
        let rendered = render("# Heading\n\nA paragraph.\n\n- a bullet")
        XCTAssertEqual(rendered.string, "Heading\nA paragraph.\n•\ta bullet")
    }

    /// A block's own line breaks are the model's, and they survive — the
    /// gap that separates blocks must not open inside one.
    func testLinesWithinAParagraphShareItsSpacing() {
        let rendered = render("first line\nsecond line")
        let first = paragraphStyle(rendered, at: 0)
        let second = paragraphStyle(rendered, at: index(of: "second", in: rendered))
        XCTAssertEqual(first.paragraphSpacing, 0)
        XCTAssertEqual(second.paragraphSpacing, AnswerRenderer.blockGap)
        XCTAssertEqual(first.lineSpacing, second.lineSpacing)
    }

    /// Nothing trails the last block: a stray newline is a stray blank line in
    /// anything the reader pastes.
    func testTheLastBlockCarriesNoSeparator() {
        XCTAssertEqual(render("Just a sentence.").string, "Just a sentence.")
    }

    // MARK: Structure

    func testHeadingsAreSizedAndInked() {
        let rendered = render("# Big\n\n### Small")
        XCTAssertEqual(font(rendered, at: 0).pointSize, style.display)
        XCTAssertEqual(font(rendered, at: index(of: "Small", in: rendered)).pointSize, style.reading)
    }

    /// The marker sits in its own column, so wrapped lines line up under the
    /// text rather than under the bullet.
    func testListMarkersHangOnATabStop() {
        let rendered = render("  - nested")
        XCTAssertEqual(rendered.string, "•\tnested")
        let paragraph = paragraphStyle(rendered, at: 0)
        XCTAssertEqual(paragraph.firstLineHeadIndent, AnswerRenderer.listIndent)
        XCTAssertEqual(paragraph.headIndent, paragraph.tabStops.first?.location)
        XCTAssertGreaterThan(paragraph.headIndent, paragraph.firstLineHeadIndent)
    }

    func testNumberedStepsKeepTheirOwnMarker() {
        XCTAssertEqual(render("1. first\n2. second").string, "1.\tfirst\n2.\tsecond")
    }

    /// Fenced code is marked for the box the text view draws behind it —
    /// TextKit has no rounded fill to attach as an attribute.
    func testFencedCodeIsMarkedForItsBox() {
        let rendered = render("```swift\nlet x = 1\n```")
        XCTAssertEqual(rendered.string, "swift\nlet x = 1")
        var range = NSRange()
        let whole = NSRange(location: 0, length: rendered.length)
        XCTAssertNotNil(rendered.attribute(
            AnswerRenderer.codeBlock, at: 0, longestEffectiveRange: &range, in: whole
        ))
        XCTAssertEqual(range, whole, "the language label belongs inside the box too")
        XCTAssertTrue(font(rendered, at: index(of: "let", in: rendered)).isFixedPitch)
    }

    func testRulesCarryNoVisibleText() {
        let rendered = render("above\n\n---\n\nbelow")
        XCTAssertEqual(rendered.string, "above\n\u{00A0}\nbelow")
        XCTAssertNotNil(rendered.attribute(
            AnswerRenderer.horizontalRule,
            at: index(of: "\u{00A0}", in: rendered),
            effectiveRange: nil
        ))
    }

    // MARK: Inline markdown

    /// Bold is a trait on the block's own font, not a font of its own — so
    /// `**bold**` inside a heading stays heading-sized.
    func testBoldInsideAHeadingKeepsTheHeadingSize() {
        let rendered = render("# A **loud** word")
        let emphasised = font(rendered, at: index(of: "loud", in: rendered))
        XCTAssertEqual(emphasised.pointSize, style.display)
        XCTAssertTrue(emphasised.fontDescriptor.symbolicTraits.contains(.bold))
    }

    func testInlineCodeIsMonospaced() {
        let rendered = render("call `map` on it")
        XCTAssertTrue(font(rendered, at: index(of: "map", in: rendered)).isFixedPitch)
        XCTAssertFalse(font(rendered, at: 0).isFixedPitch)
    }

    /// The markers themselves are gone — putting `**` on screen as characters
    /// is the bug this whole path exists to avoid.
    func testMarkupItselfNeverReachesTheScreen() {
        XCTAssertEqual(render("a **bold** and *soft* word").string, "a bold and soft word")
    }

    /// A markdown link survives into the attributed string as `.link`, which
    /// is what lets a host turn `[12:34](minute-seek://754)` into a click it
    /// can act on rather than a URL the text view opens.
    func testInlineLinksCarryTheirURL() {
        let rendered = render("see [12:34](minute-seek://754) for the decision")
        let at = index(of: "12:34", in: rendered)
        XCTAssertEqual(rendered.attribute(.link, at: at, effectiveRange: nil) as? URL,
                       URL(string: "minute-seek://754"))
        XCTAssertEqual(rendered.string, "see 12:34 for the decision")
    }

    /// The click goes to the host first; only when the host declines does the
    /// text view get to open the link itself.
    @MainActor
    func testAClickedLinkIsOfferedToTheHost() {
        let view = answerView("x")
        var seen: URL?
        view.onLink = { seen = $0; return true }
        XCTAssertTrue(view.textView(view, clickedOnLink: URL(string: "minute-seek://9")!, at: 0))
        XCTAssertEqual(seen, URL(string: "minute-seek://9"))

        view.onLink = nil
        XCTAssertFalse(view.textView(view, clickedOnLink: URL(string: "https://example.com")!, at: 0))
    }

    // MARK: What a copy carries

    /// The whole point of a selectable answer is quoting part of it, and for
    /// a while a copy put nothing but type names on the clipboard: the view
    /// declared `.string` and NSTextView filled it from a list of its own.
    @MainActor
    func testCopyingASelectionCarriesItsWords() {
        let view = answerView("Alpha bravo charlie")
        view.setSelectedRange(NSRange(location: 0, length: 5))
        let pasteboard = testPasteboard()

        XCTAssertTrue(view.writeSelection(to: pasteboard, types: view.writablePasteboardTypes))
        XCTAssertEqual(pasteboard.string(forType: .string), "Alpha")
    }

    /// The card's colours are its own — an RTF copy pastes white text into a
    /// white document.
    @MainActor
    func testACopyCarriesNoStyling() {
        let view = answerView("Alpha bravo")
        view.setSelectedRange(NSRange(location: 0, length: 11))
        let pasteboard = testPasteboard()

        _ = view.writeSelection(to: pasteboard, types: view.writablePasteboardTypes)
        XCTAssertNil(pasteboard.data(forType: .rtf))
    }

    /// ⌘-dragging picks out several passages; a copy that kept only the first
    /// would be a quiet way to lose the rest.
    @MainActor
    func testEverySelectedPassageIsCopied() {
        let view = answerView("Alpha bravo charlie")
        view.selectedRanges = [
            NSValue(range: NSRange(location: 0, length: 5)),
            NSValue(range: NSRange(location: 12, length: 7)),
        ]
        let pasteboard = testPasteboard()

        _ = view.writeSelection(to: pasteboard, types: view.writablePasteboardTypes)
        XCTAssertEqual(pasteboard.string(forType: .string), "Alpha\ncharlie")
    }

    @MainActor
    func testCopyingNothingWritesNothing() {
        let view = answerView("Alpha bravo")
        view.setSelectedRange(NSRange(location: 3, length: 0))
        let pasteboard = testPasteboard()

        XCTAssertFalse(view.writeSelection(to: pasteboard, types: view.writablePasteboardTypes))
    }

    // MARK: What a selection covers

    /// Two lines of one paragraph are highlighted as one shape: the leading
    /// between them is covered, so a quote that wraps is not read as stripes.
    @MainActor
    func testWrappedLinesAreHighlightedWithoutASeam() throws {
        let view = laidOutAnswer(twoBlocks)
        let layout = try XCTUnwrap(view.layoutManager as? AnswerLayoutManager)

        let bands = layout.textBands(for: selection(of: view))
        XCTAssertEqual(bands.count, 3)
        XCTAssertEqual(bands[0].maxY, bands[1].minY, "the lines of a paragraph touch")
    }

    /// The gap between blocks is the answer's own spacing, not something the
    /// reader selected — filling it turned a selected answer into one slab.
    @MainActor
    func testTheGapBetweenBlocksIsLeftClear() throws {
        let view = laidOutAnswer(twoBlocks)
        let layout = try XCTUnwrap(view.layoutManager as? AnswerLayoutManager)
        let glyph = layout.glyphIndexForCharacter(at: index(of: "second", in: render(twoBlocks)))
        let fragment = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)

        let bands = layout.textBands(for: selection(of: view))
        XCTAssertLessThan(bands[1].height, fragment.height, "the block gap is not painted")
        XCTAssertLessThan(bands[1].maxY, bands[2].minY)
    }

    /// A line's leading is split above the glyphs and below, the way a browser
    /// splits it. TextKit lays all of it below, which is invisible while the
    /// text is only being read and unmistakable once a selection is drawn.
    @MainActor
    func testTheLeadingSitsAboveTheGlyphsAsWellAsBelow() throws {
        let view = laidOutAnswer(twoBlocks)
        let layout = try XCTUnwrap(view.layoutManager as? AnswerLayoutManager)
        let font = font(render(twoBlocks), at: 0)
        let used = layout.lineFragmentUsedRect(forGlyphAt: 0, effectiveRange: nil)
        let baseline = layout.location(forGlyphAt: 0).y

        let above = baseline - font.ascender
        let below = used.height - (baseline - font.descender)
        XCTAssertGreaterThan(above, 1, "the glyphs do not sit against the top of the line")
        XCTAssertEqual(above, below, accuracy: 1, "and they sit as far from the bottom")
    }

    /// Nothing is painted outside the line fragment it belongs to. A text view
    /// redraws a fragment at a time, so a band that leaned into the one above
    /// was clipped on one pass and painted on the next at that pass's width —
    /// a ragged shoulder over every line.
    @MainActor
    func testABandStaysInsideItsOwnLineFragment() throws {
        let view = laidOutAnswer(twoBlocks)
        let layout = try XCTUnwrap(view.layoutManager as? AnswerLayoutManager)

        for band in layout.textBands(for: selection(of: view)) {
            let glyph = layout.glyphIndex(for: NSPoint(x: band.midX, y: band.midY), in: try XCTUnwrap(view.textContainer))
            let fragment = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            XCTAssertTrue(fragment.contains(band), "\(band) escapes \(fragment)")
        }
    }

    // MARK: Helpers

    /// A paragraph of two lines and then a second block — between the lines a
    /// paragraph's leading, between the blocks the answer's own gap.
    private let twoBlocks = "first line\nsecond line\n\nlast block"

    /// A view whose text has been through a real layout pass — the bands are
    /// measured off line fragments, which do not exist until then.
    @MainActor
    private func laidOutAnswer(_ text: String) -> AnswerTextView {
        let view = AnswerTextView()
        view.frame = NSRect(x: 0, y: 0, width: 320, height: 400)
        view.show(render(text))
        if let container = view.textContainer { view.layoutManager?.ensureLayout(for: container) }
        return view
    }

    private func selection(of view: AnswerTextView) -> NSRange {
        NSRange(location: 0, length: view.textStorage?.length ?? 0)
    }

    @MainActor
    private func answerView(_ text: String) -> AnswerTextView {
        let view = AnswerTextView()
        view.textStorage?.setAttributedString(NSAttributedString(string: text))
        return view
    }

    /// Never the general pasteboard: a test suite has no business taking
    /// whatever the person running it had on their clipboard.
    private func testPasteboard() -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("SeriesUITests.answerCopy"))
        pasteboard.clearContents()
        return pasteboard
    }

    /// Where a word starts, in the UTF-16 offsets the attribute API speaks.
    private func index(of word: String, in text: NSAttributedString) -> Int {
        (text.string as NSString).range(of: word).location
    }

    private func font(_ text: NSAttributedString, at index: Int) -> NSFont {
        text.attribute(.font, at: index, effectiveRange: nil) as? NSFont ?? .systemFont(ofSize: 0)
    }

    private func paragraphStyle(
        _ text: NSAttributedString, at index: Int
    ) -> NSParagraphStyle {
        text.attribute(.paragraphStyle, at: index, effectiveRange: nil)
            as? NSParagraphStyle ?? .default
    }
}
