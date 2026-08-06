import SwiftUI

/// The type scale. New text picks a ROLE, never a raw size, so the hierarchy
/// cannot drift as screens are added.
///
/// The union of what the three apps had. Gloss was missing `note` and so ran
/// its explanatory paragraphs through `micro` — whose bold rounded design was
/// chosen for one-or-two-word small caps labels, and which sets a paragraph as
/// a slab of fat round grey. Minute was missing `header`. Both are here.
public enum SeriesTextRole: Sendable, CaseIterable, Hashable {
    /// Small-caps labels, keyboard hints.
    case micro
    /// Explanatory prose under a label or card — the same size as `micro`, but
    /// regular and not rounded, because a sentence is not a label.
    case note
    /// Secondary information, stage rows, pills, buttons.
    case meta
    /// Section headers.
    case header
    /// Row content, field values, names.
    case body
    /// The emphasised number — a spend, a percentage, a duration. Bold and
    /// rounded, so a figure reads as a figure among the labels around it.
    case value
    /// Long-form prose. Carries `lineSpacing(6)` at the call site — a Notion-ish
    /// 1.5 line height, which is what mixed Chinese and English needs.
    case reading
    /// The one thing a surface is about.
    case display

    /// Weight and design ARE shared: they carry the role's meaning, and a
    /// `micro` label that is bold and rounded in one app and regular in
    /// another is two roles wearing one name.
    public var weight: Font.Weight {
        switch self {
        case .micro, .value, .display: return .bold
        case .note, .reading: return .regular
        case .meta, .body: return .medium
        case .header: return .semibold
        }
    }

    public var design: Font.Design {
        switch self {
        case .micro, .value: return .rounded
        default: return .default
        }
    }
}

/// The point sizes behind the roles.
///
/// **Sizes are the app's own, the way preference VALUES are.** The surfaces are
/// physically different: Brim's panel drops out of a hardware notch and is
/// glanced at, Gloss's card sits beside the sentence you are reading, Minute's
/// window is where an hour goes. Imposing one point size on all three would
/// have made the notch panel half again as large for no reason anyone could
/// name.
///
/// What is shared is the vocabulary — the same seven roles, in the same order,
/// with the same weight and design — so `header` means "section header"
/// everywhere and no app grows a private eighth role for something the other
/// two already have a word for.
public struct SeriesTypeScale: Sendable {
    private var sizes: [SeriesTextRole: CGFloat]

    public init(
        micro: CGFloat, note: CGFloat, meta: CGFloat, header: CGFloat,
        body: CGFloat, value: CGFloat, reading: CGFloat, display: CGFloat
    ) {
        sizes = [
            .micro: micro, .note: note, .meta: meta, .header: header,
            .body: body, .value: value, .reading: reading, .display: display,
        ]
    }

    public func size(_ role: SeriesTextRole) -> CGFloat {
        sizes[role] ?? 14
    }

    /// For text meant to be read: Gloss's answer card, Minute's transcript.
    public static let reading = SeriesTypeScale(
        micro: 12, note: 12, meta: 14, header: 16,
        body: 16, value: 16, reading: 16, display: 18
    )

    /// For a dense gauge glanced at from across the desk: Brim's panel, where
    /// a column of figures has to fit under a notch.
    public static let compact = SeriesTypeScale(
        micro: 8, note: 9, meta: 9, header: 10,
        body: 11, value: 13, reading: 12, display: 15
    )
}

private struct SeriesTypeScaleKey: EnvironmentKey {
    static let defaultValue = SeriesTypeScale.reading
}

extension EnvironmentValues {
    public var seriesTypeScale: SeriesTypeScale {
        get { self[SeriesTypeScaleKey.self] }
        set { self[SeriesTypeScaleKey.self] = newValue }
    }
}

private struct SeriesScaledFont: ViewModifier {
    @Environment(\.seriesTheme) private var theme
    @Environment(\.seriesTextScale) private var scale
    @Environment(\.seriesTypeface) private var typeface
    @Environment(\.seriesTypeScale) private var typeScale

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
            size: scale.apply(to: typeScale.size(role)),
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
