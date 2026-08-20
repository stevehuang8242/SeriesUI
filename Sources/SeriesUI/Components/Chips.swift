import AppKit
import SwiftUI

// The small controls that sit around a streamed answer: one-tap suggestion
// chips, the stop glyph while it is being written, and retry with a choice of
// model once it is done. Moved here from Gloss's session window so Minute's
// meeting assistant offers the same affordances in the same places.

// MARK: - Chips

/// A one-tap suggestion. Kept to one line — a chip that wraps inside its
/// capsule reads as a mistake — and truncated when even a row of its own is
/// too narrow.
public struct SeriesChip: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.seriesTheme) private var theme

    public init(title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .scaledFont(.meta)
                .lineLimit(1)
                .foregroundStyle(theme.text(hovering ? 0.9 : 0.55))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(hovering ? theme.fill(0.14) : theme.fill(0.06)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onContinuousHover { phase in
            switch phase {
            case .active:
                hovering = true
                NSCursor.pointingHand.set()
            case .ended:
                hovering = false
                NSCursor.arrow.set()
            }
        }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// Chips in rows, breaking to a new row when the next one won't fit.
///
/// An HStack gave each chip a share of the width and let its label wrap inside
/// the capsule, so "Compare synonyms" became a two-line pill — taller than a
/// second row of one-line pills, and the wrapped word reads as a mistake. Here
/// a chip either fits its row whole or starts the next one, and a label that
/// can't fit even a row of its own truncates rather than escaping the panel.
public struct ChipFlow: Layout {
    public var spacing: CGFloat
    public var rowSpacing: CGFloat

    public init(spacing: CGFloat = 6, rowSpacing: CGFloat = 6) {
        self.spacing = spacing
        self.rowSpacing = rowSpacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(within: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(
            width: rows.map(\.width).max() ?? 0,
            height: rows.map(\.height).reduce(0, +)
                + rowSpacing * CGFloat(max(rows.count - 1, 0))
        )
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(within: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for placement in row.placements {
                subviews[placement.index].place(
                    at: CGPoint(x: x, y: y + (row.height - placement.size.height) / 2),
                    proposal: ProposedViewSize(placement.size)
                )
                x += placement.size.width + spacing
            }
            y += row.height + rowSpacing
        }
    }

    private struct Placement {
        let index: Int
        let size: CGSize
    }

    private struct Row {
        var placements: [Placement] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(within maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            var size = subviews[index].sizeThatFits(.unspecified)
            // Wider than a whole row: keep it on a row of its own at the width
            // there is, which the chip spends on truncation.
            size.width = min(size.width, maxWidth)
            let advance = row.placements.isEmpty ? size.width : size.width + spacing
            if !row.placements.isEmpty, row.width + advance > maxWidth {
                rows.append(row)
                row = Row()
            }
            row.placements.append(Placement(index: index, size: size))
            row.width += row.placements.count == 1 ? size.width : advance
            row.height = max(row.height, size.height)
        }
        if !row.placements.isEmpty { rows.append(row) }
        return rows
    }
}

// MARK: - Stop

/// Interrupt an answer being written. Deliberately as quiet as the copy and
/// retry glyphs it shares a slot with — stopping is ordinary, not an alarm.
///
/// The glyph is the host's to supply (Minute draws its own icon set); the
/// convenience initialiser uses the SF Symbol Gloss always did.
public struct StopButton<Icon: View>: View {
    let action: () -> Void
    let label: String
    let icon: Icon
    @State private var hovering = false
    @Environment(\.seriesTheme) private var theme

    public init(
        label: String = "Stop generating",
        action: @escaping () -> Void,
        @ViewBuilder icon: () -> Icon
    ) {
        self.action = action
        self.label = label
        self.icon = icon()
    }

    public var body: some View {
        Button(action: action) {
            icon
                .foregroundStyle(theme.text(hovering ? 0.7 : 0.35))
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onContinuousHover { phase in
            switch phase {
            case .active:
                hovering = true
                NSCursor.pointingHand.set()
            case .ended:
                hovering = false
                NSCursor.arrow.set()
            }
        }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help("Stop")
        .accessibilityLabel(label)
    }
}

extension StopButton where Icon == AnyView {
    public init(label: String = "Stop generating", action: @escaping () -> Void) {
        self.init(label: label, action: action) {
            AnyView(Image(systemName: "stop.fill").font(.system(size: 10, weight: .medium)))
        }
    }
}

// MARK: - Retry

/// One thing an answer can be re-asked with.
public struct RetryChoice: Identifiable, Equatable, Sendable {
    public var id: String
    public var label: String

    public init(id: String, label: String) {
        self.id = id
        self.label = label
    }
}

/// Retry, with the choice of model tucked behind it. At rest the row is one
/// quiet glyph; the chevron fades in when the pointer is anywhere on the
/// pair. Which model wrote this answer is worth knowing but not worth a
/// permanent label, so it lives in the retry's tooltip and as the menu's
/// checkmark instead.
public struct RetryControl<Icon: View>: View {
    let current: String
    let choices: [RetryChoice]
    let onRetry: () -> Void
    let onPick: (String) -> Void
    /// Failures keep the chevron visible: after an error, trying a different
    /// model is the likeliest next move, so it shouldn't need discovering.
    let alwaysShowChevron: Bool
    let icon: Icon
    @State private var hovering = false
    @Environment(\.seriesTheme) private var theme

    /// `current` is the id of the choice that wrote this answer; it names the
    /// retry in the tooltip and carries the checkmark in the menu.
    public init(
        current: String,
        choices: [RetryChoice],
        onRetry: @escaping () -> Void,
        onPick: @escaping (String) -> Void,
        alwaysShowChevron: Bool = false,
        @ViewBuilder icon: () -> Icon
    ) {
        self.current = current
        self.choices = choices
        self.onRetry = onRetry
        self.onPick = onPick
        self.alwaysShowChevron = alwaysShowChevron
        self.icon = icon()
    }

    private var currentLabel: String {
        choices.first { $0.id == current }?.label ?? current
    }

    public var body: some View {
        HStack(spacing: 2) {
            Button(action: onRetry) {
                icon
                    .foregroundStyle(theme.text(hovering ? 0.6 : 0.35))
                    // A glyph is not a target. Framing it gives the pointer
                    // something to actually hit.
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Retry with \(currentLabel)")
            .accessibilityLabel("Retry with \(currentLabel)")

            Menu {
                ForEach(choices) { choice in
                    Button {
                        onPick(choice.id)
                    } label: {
                        if choice.id == current {
                            Label(choice.label, systemImage: "checkmark")
                        } else {
                            Text(choice.label)
                        }
                    }
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(theme.text(0.5))
                    .frame(width: 16, height: 18)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Retry with a different model")
            .accessibilityLabel("Retry with a different model")
            // Hidden by opacity rather than removed from the layout: its
            // space is always reserved, so revealing it shifts nothing and
            // leaves no gap for the pointer to fall through on the way over.
            // Deliberately NOT gated on hover for hit testing — a click that
            // arrives a frame before the hover registers would land on
            // nothing, which is exactly how a control "sometimes" fails.
            .opacity(alwaysShowChevron || hovering ? 1 : 0)
        }
        // ONE hover zone spanning both, with slack past the chevron so the
        // zone doesn't end at the very pixel you are aiming for. Continuous,
        // so the pointer survives the copy icon next door resetting the
        // cursor on its own way out, and the menu control doing the same.
        .padding(.trailing, 6)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active:
                hovering = true
                NSCursor.pointingHand.set()
            case .ended:
                hovering = false
                NSCursor.arrow.set()
            }
        }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

extension RetryControl where Icon == AnyView {
    public init(
        current: String,
        choices: [RetryChoice],
        onRetry: @escaping () -> Void,
        onPick: @escaping (String) -> Void,
        alwaysShowChevron: Bool = false
    ) {
        self.init(
            current: current, choices: choices, onRetry: onRetry, onPick: onPick,
            alwaysShowChevron: alwaysShowChevron
        ) {
            AnyView(Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .medium)))
        }
    }
}
