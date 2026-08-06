import AppKit
import SwiftUI

/// A 1pt divider.
///
/// Never `Divider()`, which brings its own inset and its own colour and so
/// disagrees with every other line on the surface.
public struct Hairline: View {
    @Environment(\.seriesTheme) private var theme
    var vertical: Bool

    public init(vertical: Bool = false) {
        self.vertical = vertical
    }

    public var body: some View {
        Rectangle()
            .fill(theme.hairline)
            .frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
    }
}

/// Round status dot. While `pulsing`, it breathes to signal live work.
///
/// Clock-driven through `TimelineView`: a persistent `repeatForever` animation
/// leaks into sibling layout on these panels, so the phase is computed from
/// wall-clock time each frame instead.
public struct StatusDot: View {
    var color: Color
    var pulsing: Bool
    var size: CGFloat

    public init(color: Color, pulsing: Bool = false, size: CGFloat = 6) {
        self.color = color
        self.pulsing = pulsing
        self.size = size
    }

    public var body: some View {
        if pulsing {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let phase = (sin(t * 2 * .pi / 2.2) + 1) / 2
                dot
                    .opacity(0.25 + 0.75 * phase)
                    .scaleEffect(0.8 + 0.2 * phase)
            }
            .frame(width: size, height: size)
        } else {
            dot
        }
    }

    private var dot: some View {
        Circle().fill(color).frame(width: size, height: size)
    }
}

/// Working indicator: dimmed text with an aurora band of light sweeping through
/// the letterforms, while the words cycle through status phrases with a soft
/// crossfade. Masked to the glyphs, so only the word glints.
///
/// This is the series' loading state. There is no `ProgressView`.
public struct ShimmerText: View {
    let phrases: [String]
    /// Seconds per light sweep.
    var sweepCycle: TimeInterval
    /// Seconds each phrase stays before rotating.
    var phraseCycle: TimeInterval

    @State private var appearedAt = Date()
    @Environment(\.seriesTheme) private var theme

    public init(text: String, sweepCycle: TimeInterval = 1.8, phraseCycle: TimeInterval = 2.4) {
        self.phrases = [text]
        self.sweepCycle = sweepCycle
        self.phraseCycle = phraseCycle
    }

    public init(phrases: [String], sweepCycle: TimeInterval = 1.8, phraseCycle: TimeInterval = 2.4) {
        self.phrases = phrases.isEmpty ? ["…"] : phrases
        self.sweepCycle = sweepCycle
        self.phraseCycle = phraseCycle
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(appearedAt))
            let sweep = elapsed.truncatingRemainder(dividingBy: sweepCycle) / sweepCycle
            let index = phrases.count > 1 ? Int(elapsed / phraseCycle) % phrases.count : 0
            let phrasePhase = elapsed.truncatingRemainder(dividingBy: phraseCycle) / phraseCycle
            // Fade out and back in over the last and first ~0.24s of each slot.
            let fade = phrases.count > 1
                ? max(0, min(1, min(phrasePhase, 1 - phrasePhase) / 0.1))
                : 1
            let current = phrases[index]
            label(current)
                .foregroundStyle(theme.ink.opacity(0.3))
                .overlay(
                    GeometryReader { geo in
                        // A wider band than a two-colour sweep would need, so
                        // all four aurora stops are visible at once.
                        let band = geo.size.width * 0.8
                        LinearGradient(
                            colors: [.clear] + theme.aurora.map { $0.opacity(0.9) } + [.clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: band)
                        .offset(x: -band + sweep * (geo.size.width + band * 2))
                    }
                )
                .mask(label(current))
                .opacity(fade)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text).scaledFont(.body)
    }
}

/// Single-line text that scrolls itself past the frame on hover, so a long
/// phrase can be read in full without widening the surface. At rest it sits
/// still with a tail ellipsis; the pointer runs it, leaving snaps it back.
public struct MarqueeText: View {
    let text: String
    /// Points travelled per second once running. Brisk enough that the cut-off
    /// tail arrives within a few seconds, slow enough to read on the way past.
    var speed: CGFloat
    /// Blank run between the tail of one pass and the head of the next.
    var gap: CGFloat
    /// Beat at the top of every loop, so the opening words stay readable.
    var pause: TimeInterval

    @State private var hovering = false
    @State private var startedAt = Date()
    @State private var textWidth: CGFloat = 0
    @State private var frameWidth: CGFloat = 0

    public init(text: String, speed: CGFloat = 48, gap: CGFloat = 52, pause: TimeInterval = 0.7) {
        self.text = text
        self.speed = speed
        self.gap = gap
        self.pause = pause
    }

    /// A point of slack: text that just fits should not twitch into a scroll.
    private var overflows: Bool { frameWidth > 1 && textWidth > frameWidth + 1 }

    public var body: some View {
        Group {
            if hovering && overflows {
                runner
            } else {
                label.truncationMode(.tail)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .onContentSize { frameWidth = $0.width }
        // The same string measured invisibly at full length: only the gap
        // between what the sentence wants and what the frame gives says whether
        // there is anything to scroll.
        .background(alignment: .leading) {
            label.fixedSize().hidden().onContentSize { textWidth = $0.width }
        }
        .contentShape(Rectangle())
        .onHover { inside in
            hovering = inside
            // Every entry starts the loop from the first word, not from
            // wherever a previous hover happened to leave the clock.
            if inside { startedAt = Date() }
        }
    }

    private var runner: some View {
        let travel = textWidth + gap
        let scrollTime = TimeInterval(travel / speed)
        return TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(startedAt))
            let t = elapsed.truncatingRemainder(dividingBy: pause + scrollTime)
            // One loop is a hold, then a travel of exactly one text-plus-gap
            // length — at which point the trailing copy sits where the leading
            // one started, so the wrap has no seam.
            let shift = t <= pause ? 0 : travel * CGFloat((t - pause) / scrollTime)
            HStack(spacing: gap) {
                label
                label
            }
            .fixedSize()
            .offset(x: -shift)
            // Back to the visible width before masking, so the gradient is
            // measured against the frame and not against the much wider pair
            // of copies it is masking.
            .frame(width: frameWidth, alignment: .leading)
            .mask(fade(shift: shift))
        }
    }

    private var label: some View {
        Text(text).lineLimit(1)
    }

    /// Glyphs dissolve at the edges rather than being sliced off by the clip.
    /// The leading edge only fades in once the text is actually moving, so the
    /// first word stays crisp through the opening beat.
    private func fade(shift: CGFloat) -> LinearGradient {
        let width: CGFloat = 14
        guard frameWidth > width * 4 else {
            return LinearGradient(colors: [.black], startPoint: .leading, endPoint: .trailing)
        }
        let trailing = width / frameWidth
        let leading = trailing * min(1, shift / width)
        return LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: leading),
                .init(color: .black, location: 1 - trailing),
                .init(color: .clear, location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

/// A short status line beside a control — "Connected", "No meeting in
/// progress", "Copied". Replaces the scattered `Label` +
/// `.foregroundStyle(.secondary)` pattern with one shape.
public struct InlineNote: View {
    @Environment(\.seriesTheme) private var theme
    var text: String
    var systemImage: String?
    var tint: Color?

    public init(_ text: String, systemImage: String? = nil, tint: Color? = nil) {
        self.text = text
        self.systemImage = systemImage
        self.tint = tint
    }

    public var body: some View {
        HStack(spacing: 5) {
            if let systemImage { Image(systemName: systemImage) }
            Text(text).lineLimit(2)
        }
        .scaledFont(.note)
        .foregroundStyle(tint ?? theme.text(0.45))
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Cursor

extension View {
    /// Pointing-hand cursor while hovering.
    public func pointingHand(_ active: Bool = true) -> some View {
        hoverCursor(.pointingHand, active: active)
    }

    public func hoverCursor(_ cursor: NSCursor, active: Bool = true) -> some View {
        modifier(HoverCursor(cursor: cursor, active: active))
    }
}

/// Cursor management, in one place.
///
/// Controls that each wrote `(inside ? .pointingHand : .arrow).set()` hit two
/// real problems:
///
/// 1. **The cursor sticks.** When a view is removed while hovered (a toolbar
///    swapping on an edit toggle, a menu closing on the click), the leaving
///    branch never runs and the cursor stays a hand.
/// 2. **It overrides other cursors.** Forcing `.arrow` on exit claims "this
///    should be an arrow" — leaving a timestamp inside prose replaces the
///    I-beam that prose is entitled to.
///
/// A matched push/pop restores the PREVIOUS cursor instead of asserting a new
/// one, and the `onDisappear` pop covers the first case.
private struct HoverCursor: ViewModifier {
    let cursor: NSCursor
    var active: Bool
    @State private var pushed = false

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                if inside && active { push() } else { pop() }
            }
            .onDisappear(perform: pop)
            .onChange(of: active) { _, on in if !on { pop() } }
    }

    private func push() {
        guard !pushed else { return }
        pushed = true
        cursor.push()
    }

    private func pop() {
        guard pushed else { return }
        pushed = false
        NSCursor.pop()
    }
}
