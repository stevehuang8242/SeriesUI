import SwiftUI

/// The type scale. New text picks a ROLE, never a raw size, so the hierarchy
/// cannot drift as screens are added.
///
/// The union of what the three apps had. Gloss was missing `note` and so ran
/// its explanatory paragraphs through `micro` — whose bold rounded design was
/// chosen for one-or-two-word small caps labels, and which sets a paragraph as
/// a slab of fat round grey. Minute was missing `header`. Both are here.
public enum SeriesTextRole: Sendable, CaseIterable {
    /// Small-caps labels, keyboard hints. The only role that is rounded.
    case micro
    /// Explanatory prose under a label or card — same size as `micro`, but
    /// regular and not rounded, because a sentence is not a label.
    case note
    /// Secondary information, stage rows, pills, buttons.
    case meta
    /// Section headers.
    case header
    /// Row content, field values, names.
    case body
    /// Long-form prose. Carries `lineSpacing(6)` at the call site — a Notion-ish
    /// 1.5 line height, which is what mixed Chinese and English needs.
    case reading
    /// The one thing a surface is about.
    case display

    public var size: CGFloat {
        switch self {
        case .micro, .note: return 12
        case .meta: return 14
        case .header, .body, .reading: return 16
        case .display: return 18
        }
    }

    public var weight: Font.Weight {
        switch self {
        case .micro: return .bold
        case .note, .reading: return .regular
        case .meta, .body: return .medium
        case .header: return .semibold
        case .display: return .bold
        }
    }

    public var design: Font.Design {
        self == .micro ? .rounded : .default
    }
}

private struct SeriesScaledFont: ViewModifier {
    @Environment(\.seriesTheme) private var theme
    @Environment(\.seriesTextScale) private var scale
    @Environment(\.seriesTypeface) private var typeface

    let role: SeriesTextRole
    var weightOverride: Font.Weight?
    var designOverride: Font.Design?
    var monospacedDigit: Bool

    func body(content: Content) -> some View {
        // A chosen serif or mono overrides every role, `micro` included — else
        // the small-caps labels stay rounded in serif mode and read as a
        // missed edit. `default` keeps each role's own design.
        let design = typeface.design ?? designOverride ?? role.design
        var font = Font.system(
            size: scale.apply(to: role.size),
            weight: theme.weight(weightOverride ?? role.weight),
            design: design
        )
        if monospacedDigit { font = font.monospacedDigit() }
        return content.font(font)
    }
}

extension View {
    /// Type at a role, scaled and weight-corrected for the current ground.
    public func scaledFont(
        _ role: SeriesTextRole,
        weight: Font.Weight? = nil,
        design: Font.Design? = nil,
        monospacedDigit: Bool = false
    ) -> some View {
        modifier(SeriesScaledFont(
            role: role,
            weightOverride: weight,
            designOverride: design,
            monospacedDigit: monospacedDigit
        ))
    }

    /// A section label: small caps, tracked out, recessed.
    public func sectionLabel() -> some View {
        modifier(SectionLabel())
    }
}

private struct SectionLabel: ViewModifier {
    @Environment(\.seriesTheme) private var theme

    func body(content: Content) -> some View {
        content
            .scaledFont(.micro)
            .foregroundStyle(theme.text(0.4))
            .textCase(.uppercase)
            .kerning(0.6)
    }
}

/// A layout width that grows with the type scale.
///
/// Hard-coded widths are exactly where a text-size setting breaks: the labels
/// inside them are `lineLimit(1)`, so turning the scale up silently truncates
/// every rail, dropdown and field. Anything measured against text goes through
/// here. The proportions do not change — `scaledWidth` and `scaledFont`
/// multiply by the same factor.
public func scaledWidth(_ base: CGFloat, _ scale: SeriesTextScale) -> CGFloat {
    base * scale.multiplier
}
