import AppKit
import SwiftUI

// An answer, drawn as ONE text view.
//
// SwiftUI's selection scope is a single `Text`. The answer used to be a column
// of them — a heading, three bullets, a paragraph, each its own view — so a
// drag could select inside any one block and never across two, and even a
// bullet's marker and its own sentence were separate scopes. In an app whose
// entire output is prose meant to be quoted back into notes, that is the wrong
// seam.
//
// So the blocks are rendered into one `NSAttributedString` and handed to one
// `NSTextView`. The structure survives — headings sized, list markers on a tab
// stop, fenced code in a tinted box — and a drag runs from the first word to
// the last. ⌘C, ⌘A, right-click → Look Up and the Services menu come with it,
// because they are what a text view has always had.
//
// Moved here from Gloss so Minute's meeting assistant draws its answers the
// same way. The one addition is `onLink`: a link in the answer can mean
// something to the host app — Minute turns `[12:34]` into a link that seeks
// the recording — and the text view hands the click back instead of opening
// the URL itself.

// MARK: - Resolved style

/// Everything the renderer needs from the environment, resolved up front so
/// the AppKit side never reaches back into SwiftUI. Equatable, and holding
/// `Color`/`Font.Weight` rather than their AppKit equivalents, so a rebuild
/// can be skipped when nothing about the appearance actually changed.
public struct AnswerTextStyle: Equatable {
    /// Point sizes, already through the reader's text-size preference.
    public let reading: CGFloat
    public let display: CGFloat
    public let meta: CGFloat
    public let code: CGFloat
    public let design: Font.Design
    public let regular: Font.Weight
    public let medium: Font.Weight
    public let semibold: Font.Weight
    public let ink: Color
    public let body: Color
    public let marker: Color
    public let recessed: Color
    public let codeInk: Color
    public let codeFill: Color
    public let hairline: Color
    public let link: Color

    public init(
        theme: SeriesTheme,
        typeScale: SeriesTypeScale,
        textScale: SeriesTextScale,
        typeface: SeriesTypeface
    ) {
        reading = textScale.apply(to: typeScale.size(.reading))
        display = textScale.apply(to: typeScale.size(.display))
        meta = textScale.apply(to: typeScale.size(.meta))
        // Fenced code was the one hard-coded point size in an answer, and so
        // the one thing on the card that ignored the text-size preference.
        code = textScale.apply(to: 12.5)
        design = typeface.design ?? .default
        regular = theme.weight(.regular)
        medium = theme.weight(.medium)
        semibold = theme.weight(.semibold)
        ink = theme.ink
        body = theme.text(0.92)
        marker = theme.text(0.45)
        recessed = theme.text(0.4)
        codeInk = theme.text(0.9)
        codeFill = theme.fill(0.06)
        hairline = theme.cardBorder
        link = theme.focus
    }

    /// The AppKit font for a role, honouring the chosen typeface the way
    /// `scaledFont` does — a serif or mono choice overrides every role.
    public func font(size: CGFloat, weight: Font.Weight, mono: Bool = false) -> NSFont {
        let weight = Self.weight(weight)
        if mono { return .monospacedSystemFont(ofSize: size, weight: weight) }
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        guard let system = Self.design(design), system != .default,
              let descriptor = base.fontDescriptor.withDesign(system),
              let font = NSFont(descriptor: descriptor, size: size)
        else { return base }
        return font
    }

    /// Bold and italic are asked for as TRAITS on whatever font the block
    /// already uses, so `**bold**` inside a heading stays a heading.
    public static func adding(_ traits: NSFontDescriptor.SymbolicTraits, to font: NSFont) -> NSFont {
        let descriptor = font.fontDescriptor
            .withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(traits))
        return NSFont(descriptor: descriptor, size: font.pointSize) ?? font
    }

    private static func weight(_ weight: Font.Weight) -> NSFont.Weight {
        switch weight {
        case .ultraLight: return .ultraLight
        case .thin: return .thin
        case .light: return .light
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        default: return .regular
        }
    }

    private static func design(_ design: Font.Design) -> NSFontDescriptor.SystemDesign? {
        switch design {
        case .serif: return .serif
        case .rounded: return .rounded
        case .monospaced: return .monospaced
        default: return .default
        }
    }
}

// MARK: - Blocks into one attributed string

/// Turns `SeriesAnswer.blocks` into a single attributed string. Pure, and run
/// against text that is still arriving — it is rebuilt on every flush, which
/// is affordable only because deltas are batched (see `DeltaBuffer`).
public enum AnswerRenderer {
    /// Marks the runs the text view draws a box or a line behind. Neither can
    /// be an attributed-string attribute — TextKit has no rounded fill and no
    /// horizontal rule — so they are drawn by hand from these ranges.
    public static let codeBlock = NSAttributedString.Key("seriesCodeBlock")
    public static let horizontalRule = NSAttributedString.Key("seriesRule")

    /// The gap between blocks: the VStack spacing this replaced.
    public static let blockGap: CGFloat = 10
    /// Breathing room inside a fenced-code box, and so how far past the glyphs
    /// the box is drawn.
    public static let codePadding: CGFloat = 10
    /// One level of list indent. Two spaces of markdown indent is one level.
    public static let listIndent: CGFloat = 14
    /// The leading between the lines of a paragraph.
    public static let leading: CGFloat = 6

    /// Sets a paragraph's leading, split the way a browser splits it: half
    /// above the glyphs and half below.
    ///
    /// TextKit lays `lineSpacing` entirely BELOW a line, so every line sits
    /// high in its own box. Nothing shows that while the text is only being
    /// read — the pitch is the same either way — but a selection is drawn to
    /// the box, and a highlight with all its air underneath looks like it has
    /// slipped down off the words. `lineHeightMultiple` is the other half: it
    /// grows the line and puts the growth above the baseline.
    static func lead(_ paragraph: NSMutableParagraphStyle, _ leading: CGFloat, _ font: NSFont) {
        let line = font.ascender - font.descender + font.leading
        guard line > 0 else { return }
        paragraph.lineSpacing = leading / 2
        paragraph.lineHeightMultiple = (line + leading / 2) / line
    }

    public static func attributed(_ text: String, style: AnswerTextStyle) -> NSAttributedString {
        let blocks = SeriesAnswer.blocks(text)
        let out = NSMutableAttributedString()
        for (index, block) in blocks.enumerated() {
            out.append(render(block, style: style, isLast: index == blocks.count - 1))
        }
        return out
    }

    private static func render(
        _ block: SeriesAnswer.Block, style: AnswerTextStyle, isLast: Bool
    ) -> NSAttributedString {
        switch block {
        case .paragraph(let body):
            let font = style.font(size: style.reading, weight: style.regular)
            let piece = inline(body, font: font, color: style.body, style: style)
            return finish(piece, isLast: isLast) { _, last in
                let paragraph = NSMutableParagraphStyle()
                lead(paragraph, leading, font)
                paragraph.paragraphSpacing = last ? blockGap : 0
                return paragraph
            }

        case .heading(let level, let body):
            // Three sizes for six levels: past the third the distinction stops
            // carrying meaning in a card this narrow.
            let size = level <= 1 ? style.display : style.reading
            let piece = inline(
                body,
                font: style.font(size: size, weight: style.semibold),
                color: style.ink,
                style: style
            )
            return finish(piece, isLast: isLast) { first, last in
                let paragraph = NSMutableParagraphStyle()
                paragraph.paragraphSpacingBefore = first ? 2 : 0
                paragraph.paragraphSpacing = last ? blockGap : 0
                return paragraph
            }

        case .bullet(let depth, let body):
            return list(
                marker: "•", column: 12, depth: depth, body: body,
                style: style, isLast: isLast
            )

        case .numbered(let marker, let depth, let body):
            return list(
                marker: marker, column: 20, depth: depth, body: body,
                style: style, isLast: isLast
            )

        case .code(let language, let body):
            return code(language: language, body: body, style: style, isLast: isLast)

        case .rule:
            // A rule has no text of its own, and a text view can only lay out
            // text — so it is one invisible character wide enough to give the
            // line something to be drawn across.
            let piece = NSMutableAttributedString(string: "\u{00A0}", attributes: [
                .font: NSFont.systemFont(ofSize: 1),
                .foregroundColor: NSColor.clear,
                horizontalRule: true,
            ])
            return finish(piece, isLast: isLast) { _, _ in
                let paragraph = NSMutableParagraphStyle()
                paragraph.paragraphSpacingBefore = blockGap + 2
                paragraph.paragraphSpacing = blockGap + 2
                return paragraph
            }
        }
    }

    /// A list row: the marker sits in its own column so wrapped lines line up
    /// under the text rather than under the bullet.
    private static func list(
        marker: String, column: CGFloat, depth: Int, body: String,
        style: AnswerTextStyle, isLast: Bool
    ) -> NSAttributedString {
        let font = style.font(size: style.reading, weight: style.regular)
        let indent = CGFloat(depth) * listIndent
        // A marker wider than its column — "10." at Extra Large — pushes its
        // own row out rather than running into the first word.
        let width = (marker as NSString).size(withAttributes: [.font: font]).width
        let stop = indent + max(column, ceil(width)) + 6

        let piece = NSMutableAttributedString(
            string: marker + "\t",
            attributes: [.font: font, .foregroundColor: NSColor(style.marker)]
        )
        piece.append(inline(body, font: font, color: style.body, style: style))

        return finish(piece, isLast: isLast) { _, last in
            let paragraph = NSMutableParagraphStyle()
            lead(paragraph, leading, font)
            paragraph.paragraphSpacing = last ? blockGap : 0
            paragraph.firstLineHeadIndent = indent
            paragraph.headIndent = stop
            paragraph.tabStops = [NSTextTab(textAlignment: .left, location: stop)]
            paragraph.defaultTabInterval = stop
            return paragraph
        }
    }

    private static func code(
        language: String?, body: String, style: AnswerTextStyle, isLast: Bool
    ) -> NSAttributedString {
        let mono = style.font(size: style.code, weight: style.regular, mono: true)
        let piece = NSMutableAttributedString()
        if let language {
            piece.append(NSAttributedString(string: language + "\n", attributes: [
                .font: style.font(size: style.meta, weight: style.medium),
                .foregroundColor: NSColor(style.recessed),
            ]))
        }
        piece.append(NSAttributedString(string: body, attributes: [
            .font: mono,
            .foregroundColor: NSColor(style.codeInk),
        ]))
        piece.addAttribute(
            codeBlock, value: true, range: NSRange(location: 0, length: piece.length)
        )

        let labelled = language != nil
        return finish(piece, isLast: isLast) { first, last in
            let paragraph = NSMutableParagraphStyle()
            paragraph.firstLineHeadIndent = codePadding
            paragraph.headIndent = codePadding
            paragraph.tailIndent = -codePadding
            lead(paragraph, 2, mono)
            // Room for the box, drawn `codePadding` past the glyphs top and
            // bottom, and then the same gap to the next block as anywhere
            // else. Every line of the code is its own paragraph, so only the
            // outer two carry any of it.
            paragraph.paragraphSpacingBefore = first ? blockGap + codePadding : 0
            if last {
                paragraph.paragraphSpacing = blockGap + codePadding
            } else if first, labelled {
                paragraph.paragraphSpacing = 4
            }
            return paragraph
        }
    }

    /// Inline markdown — bold, italic, `code`, links — onto the block's own
    /// font and colour.
    private static func inline(
        _ body: String, font: NSFont, color: Color, style: AnswerTextStyle
    ) -> NSMutableAttributedString {
        let parsed = SeriesAnswer.markdown(body)
        let ink = NSColor(color)
        let out = NSMutableAttributedString()
        for run in parsed.runs {
            let text = String(parsed[run.range].characters)
            guard !text.isEmpty else { continue }
            let intent = run.inlinePresentationIntent ?? []

            var runFont = font
            if intent.contains(.code) {
                runFont = style.font(size: font.pointSize, weight: style.regular, mono: true)
            } else {
                if intent.contains(.stronglyEmphasized) {
                    runFont = AnswerTextStyle.adding(.bold, to: runFont)
                }
                if intent.contains(.emphasized) {
                    runFont = AnswerTextStyle.adding(.italic, to: runFont)
                }
            }

            var attributes: [NSAttributedString.Key: Any] = [
                .font: runFont,
                .foregroundColor: ink,
            ]
            if intent.contains(.strikethrough) {
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
            if let link = run.link {
                attributes[.link] = link
            }
            out.append(NSAttributedString(string: text, attributes: attributes))
        }
        return out
    }

    /// Closes a block: the newline that separates it from the next one, then
    /// its paragraph style.
    ///
    /// Applied per PARAGRAPH rather than to the block as a whole, because the
    /// two are not the same thing. A paragraph block keeps the model's own
    /// line breaks and a fenced block is nothing but line breaks — so the gap
    /// that belongs AFTER the block would otherwise open inside it, once per
    /// line.
    private static func finish(
        _ piece: NSMutableAttributedString,
        isLast: Bool,
        style: (_ first: Bool, _ last: Bool) -> NSParagraphStyle
    ) -> NSAttributedString {
        if !isLast {
            let attributes = piece.length > 0
                ? piece.attributes(at: piece.length - 1, effectiveRange: nil)
                : [:]
            piece.append(NSAttributedString(string: "\n", attributes: attributes))
        }
        let text = piece.string as NSString
        var ranges: [NSRange] = []
        var location = 0
        while location < text.length {
            let range = text.paragraphRange(for: NSRange(location: location, length: 0))
            ranges.append(range)
            location = max(range.upperBound, location + 1)
        }
        for (index, range) in ranges.enumerated() {
            piece.addAttribute(
                .paragraphStyle,
                value: style(index == 0, index == ranges.count - 1),
                range: range
            )
        }
        return piece
    }
}

// MARK: - The view

/// An answer, with the structure the model actually wrote — headings sized,
/// bullets given a real bullet, numbered steps aligned by their marker, fenced
/// code in a monospaced tinted box — and selectable end to end.
public struct AnswerText: View {
    let text: String
    /// Called with a link's URL when the reader clicks it. Return true to say
    /// the click was handled; false lets the text view open the URL itself.
    let onLink: ((URL) -> Bool)?
    @Environment(\.seriesTheme) private var theme
    @Environment(\.seriesTypeScale) private var typeScale
    @Environment(\.seriesTextScale) private var textScale
    @Environment(\.seriesTypeface) private var typeface

    public init(text: String, onLink: ((URL) -> Bool)? = nil) {
        self.text = text
        self.onLink = onLink
    }

    public var body: some View {
        SelectableAnswerText(
            text: text,
            style: AnswerTextStyle(
                theme: theme,
                typeScale: typeScale,
                textScale: textScale,
                typeface: typeface
            ),
            onLink: onLink
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

public struct SelectableAnswerText: NSViewRepresentable {
    let text: String
    let style: AnswerTextStyle
    let onLink: ((URL) -> Bool)?

    public init(text: String, style: AnswerTextStyle, onLink: ((URL) -> Bool)? = nil) {
        self.text = text
        self.style = style
        self.onLink = onLink
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public func makeNSView(context: Context) -> AnswerTextView {
        let view = AnswerTextView()
        apply(to: view, context: context)
        return view
    }

    public func updateNSView(_ view: AnswerTextView, context: Context) {
        apply(to: view, context: context)
    }

    /// The card and the window size themselves FROM the laid-out answer, so
    /// this has to be the same height the text view will actually draw at.
    /// Measured on a layout stack of its own rather than by resizing the live
    /// view mid-layout, which is a loop SwiftUI is entitled to complain about.
    public func sizeThatFits(
        _ proposal: ProposedViewSize, nsView: AnswerTextView, context: Context
    ) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        let attributed = context.coordinator.attributed(text: text, style: style)
        return CGSize(width: width, height: context.coordinator.height(attributed, width: width))
    }

    private func apply(to view: AnswerTextView, context: Context) {
        view.codeFill = NSColor(style.codeFill)
        view.ruleColor = NSColor(style.hairline)
        view.onLink = onLink
        view.linkTextAttributes = [
            .foregroundColor: NSColor(style.link),
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .cursor: NSCursor.pointingHand,
        ]
        view.show(context.coordinator.attributed(text: text, style: style))
    }

    @MainActor
    public final class Coordinator {
        private var key: (text: String, style: AnswerTextStyle)?
        private var built: NSAttributedString?
        private let measure = AnswerTextMeasure()

        /// One build per change, shared by sizing and drawing — SwiftUI asks
        /// for both, repeatedly, for the same text.
        func attributed(text: String, style: AnswerTextStyle) -> NSAttributedString {
            if let key, key.text == text, key.style == style, let built { return built }
            let value = AnswerRenderer.attributed(text, style: style)
            key = (text, style)
            built = value
            return value
        }

        func height(_ attributed: NSAttributedString, width: CGFloat) -> CGFloat {
            measure.height(attributed, width: width)
        }
    }
}

/// An offscreen TextKit stack that answers "how tall, at this width?".
@MainActor
public final class AnswerTextMeasure {
    private let storage = NSTextStorage()
    private let layout = NSLayoutManager()
    private let container = NSTextContainer(
        size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
    )
    private var cache: (text: NSAttributedString, width: CGFloat, height: CGFloat)?

    public init() {
        container.lineFragmentPadding = 0
        container.widthTracksTextView = false
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
    }

    public func height(_ attributed: NSAttributedString, width: CGFloat) -> CGFloat {
        if let cache, cache.text === attributed, cache.width == width { return cache.height }
        storage.setAttributedString(attributed)
        container.size = CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        let height = ceil(layout.usedRect(for: container).height)
        cache = (attributed, width, height)
        return height
    }
}

/// Highlights the selection line by line rather than fragment by fragment.
///
/// A line fragment is taller than its line in two different ways, and only one
/// of them should be painted. The leading BETWEEN the lines of a paragraph has
/// to be covered, or a quote spanning two lines comes back as stripes.
/// `paragraphSpacing` is the gap between BLOCKS — ten points, the air around a
/// heading and between numbered steps — and covering that is what turned a
/// selected answer into one unbroken slab.
///
/// TextKit's used rect draws exactly that line: the leading, not the block gap.
/// So the rectangles it hands over are replaced by the used rect of each line
/// they cover — vertically. Horizontally they were always right, and they know
/// what the used rect cannot: where a partial first line starts and where the
/// last one stops.
public final class AnswerLayoutManager: NSLayoutManager {
    /// Where the container was last drawn. The fill below is handed rectangles
    /// in the view's coordinates while the layout manager measures in the
    /// container's, and this is the only place the offset between them is said.
    private var backgroundOrigin: NSPoint = .zero

    override public func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        backgroundOrigin = origin
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
    }

    override public func fillBackgroundRectArray(
        _ rectArray: UnsafePointer<NSRect>,
        count rectCount: Int,
        forCharacterRange charRange: NSRange,
        color: NSColor
    ) {
        let bands = textBands(for: charRange, origin: backgroundOrigin)
        guard !bands.isEmpty else {
            super.fillBackgroundRectArray(
                rectArray, count: rectCount, forCharacterRange: charRange, color: color
            )
            return
        }
        color.setFill()
        for index in 0..<rectCount {
            let rect = rectArray[index]
            // One rectangle can stand for several lines — TextKit coalesces the
            // full-width middle of a long selection — so each line it spans is
            // filled on its own band. Claimed by the midpoint rather than by
            // overlap: a rectangle covers whole fragments, and a band that only
            // grazes one belongs to the line either side of it.
            let spanned = bands.filter { rect.minY <= $0.midY && $0.midY < rect.maxY }
            guard !spanned.isEmpty else { rect.fill(); continue }
            for band in spanned {
                NSRect(x: rect.minX, y: band.minY, width: rect.width, height: band.height).fill()
            }
        }
    }

    /// The band highlighting each line of a character range, in view
    /// coordinates.
    ///
    /// The used rect IS the band: it holds the line and its leading, and the
    /// renderer has already centred the glyphs inside it. Nothing here reaches
    /// past it, which is the point — a text view redraws a line fragment at a
    /// time, and a fill that leaned into the fragment above was clipped away on
    /// one pass and painted on the next at that pass's width, leaving a ragged
    /// three-point shoulder over every line.
    public func textBands(for charRange: NSRange, origin: NSPoint = .zero) -> [NSRect] {
        guard let storage = textStorage, storage.length > 0 else { return [] }
        let glyphs = glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
        guard glyphs.length > 0 else { return [] }

        var bands: [NSRect] = []
        enumerateLineFragments(forGlyphRange: glyphs) { _, used, _, _, _ in
            bands.append(used.offsetBy(dx: origin.x, dy: origin.y))
        }
        return bands
    }
}

/// The answer's text view: read-only, transparent, and drawing the two things
/// an attributed string cannot say — the fenced-code box and the rule.
public final class AnswerTextView: NSTextView, NSTextViewDelegate {
    public var codeFill: NSColor = .clear
    public var ruleColor: NSColor = .clear
    /// The host's chance to act on a link before the text view opens it.
    /// Return true to claim the click.
    public var onLink: ((URL) -> Bool)?
    private var applied: NSAttributedString?

    public convenience init() {
        // Built on an explicit TextKit 1 stack: the height the card sizes
        // itself from comes off this layout manager, and a view left to pick
        // its own stack can answer with a different one than it draws with.
        // The layout manager is ours for a second reason — it is what draws
        // the selection, and the selection wants to hug the words.
        let storage = NSTextStorage()
        let layout = AnswerLayoutManager()
        let container = NSTextContainer(
            size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        )
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)

        self.init(frame: .zero, textContainer: container)
        isEditable = false
        isSelectable = true
        drawsBackground = false
        isVerticallyResizable = false
        isHorizontallyResizable = false
        textContainerInset = .zero
        focusRingType = .none
        usesFontPanel = false
        usesFindBar = false
        delegate = self
    }

    /// A link the host recognises is the host's; anything else opens as a
    /// link normally would.
    public func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        guard let onLink else { return false }
        let url: URL?
        if let link = link as? URL { url = link } else if let string = link as? String { url = URL(string: string) } else { url = nil }
        guard let url else { return false }
        return onLink(url)
    }

    /// The answer is prose the reader is quoting into their own notes, and
    /// this card's colours are its own — an RTF copy would paste white text
    /// into a white document. Copying and dragging carry the words only.
    override public var writablePasteboardTypes: [NSPasteboard.PasteboardType] { [.string] }

    /// Narrowing that list is not enough by itself. NSTextView declares the
    /// types it was handed and then fills them from a list of its own, so a
    /// pasteboard promising nothing but `.string` was declared and never
    /// written: ⌘C left type names on the clipboard and no words behind them,
    /// and a paste anywhere else produced nothing. Writing the selection here
    /// is both the fix and the whole of what the narrowing ever meant.
    override public func writeSelection(
        to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]
    ) -> Bool {
        guard types.contains(.string) else {
            return super.writeSelection(to: pboard, types: types)
        }
        // Ranges, plural: ⌘-dragging picks out several passages, and a copy
        // that kept only the first would be a quiet way to lose the rest.
        let text = (string as NSString)
        let selected = selectedRanges
            .map { text.substring(with: $0.rangeValue) }
            .joined(separator: "\n")
        guard !selected.isEmpty else { return false }
        pboard.clearContents()
        pboard.setString(selected, forType: .string)
        return true
    }

    /// A non-activating panel never activates the app, so a click on it is
    /// always a "first" click. Without this the drag that came with it selects
    /// nothing and the reader has to press twice to quote a sentence. Harmless
    /// in an ordinary window.
    override public func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    public func show(_ attributed: NSAttributedString) {
        guard applied !== attributed, let storage = textStorage else { return }
        applied = attributed
        // A selection made mid-answer survives the deltas that follow it, as
        // long as the text it covers is still there.
        let selection = selectedRanges
        storage.setAttributedString(attributed)
        let kept = selection.filter { NSMaxRange($0.rangeValue) <= storage.length }
        if !kept.isEmpty { selectedRanges = kept }
        needsDisplay = true
    }

    override public func draw(_ dirtyRect: NSRect) {
        drawBlocks()
        super.draw(dirtyRect)
    }

    private func drawBlocks() {
        guard let layoutManager, let textContainer, let storage = textStorage,
              storage.length > 0
        else { return }
        let origin = textContainerOrigin
        let whole = NSRange(location: 0, length: storage.length)

        storage.enumerateAttribute(AnswerRenderer.codeBlock, in: whole) { value, range, _ in
            guard value != nil,
                  let used = self.used(range, layoutManager, textContainer)
            else { return }
            let box = NSRect(
                x: 0,
                y: used.minY + origin.y - AnswerRenderer.codePadding,
                width: self.bounds.width,
                height: used.height + AnswerRenderer.codePadding * 2
            )
            self.codeFill.setFill()
            NSBezierPath(roundedRect: box, xRadius: 8, yRadius: 8).fill()
        }

        storage.enumerateAttribute(AnswerRenderer.horizontalRule, in: whole) { value, range, _ in
            guard value != nil,
                  let used = self.used(range, layoutManager, textContainer)
            else { return }
            self.ruleColor.setFill()
            NSRect(
                x: 0, y: (used.midY + origin.y).rounded(),
                width: self.bounds.width, height: 1
            ).fill()
        }
    }

    /// The lines a character range occupies, in view coordinates.
    private func used(
        _ range: NSRange, _ layoutManager: NSLayoutManager, _ container: NSTextContainer
    ) -> NSRect? {
        let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        guard glyphs.length > 0 else { return nil }
        var union: NSRect?
        layoutManager.enumerateLineFragments(forGlyphRange: glyphs) { _, used, _, _, _ in
            union = union.map { $0.union(used) } ?? used
        }
        return union
    }
}
