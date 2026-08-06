import SwiftUI

// The grammar of a settings screen.
//
// The three apps put settings in three different CONTAINERS, and rightly so —
// ClaudeNotch has eight switches inside an overlay, Gloss is a menu-bar utility
// with a window, Minute is a document app with a sidebar destination. Forcing
// one container on all three would be wrong.
//
// What has to match is the grammar: how one setting looks, how settings group,
// where the explaining sentence goes. That is `Card` and `SettingRow`, and it
// replaces `Form` / `Section` / `GroupBox` / `LabeledContent` everywhere.

/// A group of settings under a small-caps title, with an optional footnote.
///
/// Replaces `GroupBox` and `Form`'s `Section`.
public struct Card<Content: View>: View {
    var title: String?
    var footnote: String?
    @ViewBuilder var content: () -> Content

    @Environment(\.seriesTheme) private var theme

    public init(
        title: String? = nil,
        footnote: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.footnote = footnote
        self.content = content
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title { Text(title).sectionLabel() }
            content()
            if let footnote {
                Text(footnote)
                    .scaledFont(.note)
                    .foregroundStyle(theme.text(0.45))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(shape.fill(theme.fill(0.04)))
        .overlay(shape.stroke(theme.cardBorder, lineWidth: 1))
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: SeriesRadius.card, style: .continuous)
    }
}

/// One setting: a label on the left, its control on the right, and — when the
/// setting needs explaining — a sentence beneath both.
///
/// `detail` runs under the WHOLE row, indented only to the control column. It
/// deliberately does not share the label column: that column's width is chosen
/// for LABELS, and a forty-word explanation folded into it turns the card into
/// a grey vertical ribbon.
///
/// Write labels as labels. The card title already says "Transcription engine",
/// so the rows beneath it are `Model` / `Download` / `Language`, not
/// `Whisper model` / `Transcription language` — repeating the context only
/// pushes the label column wider. Give the full name to `accessibilityLabel`
/// instead; VoiceOver has no card title for context.
public struct SettingRow<Content: View>: View {
    var label: String
    var detail: String?
    /// nil takes the series default. Not a property initialiser because the
    /// default depends on the ambient text scale.
    var labelWidth: CGFloat?
    @ViewBuilder var content: () -> Content

    @Environment(\.seriesTheme) private var theme
    @Environment(\.seriesTextScale) private var scale

    public init(
        label: String,
        detail: String? = nil,
        labelWidth: CGFloat? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.label = label
        self.detail = detail
        self.labelWidth = labelWidth
        self.content = content
    }

    public var body: some View {
        // The width has to be scaled, not fixed: with a hard-coded column the
        // controls grow with the text-size setting and the labels do not, so
        // turning the scale up folds every label. `scaledWidth` and
        // `scaledFont` multiply by the same factor, so the proportion holds.
        let width = labelWidth ?? scaledWidth(136, scale)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(label)
                    .scaledFont(.meta)
                    .foregroundStyle(theme.text(0.75))
                    .frame(width: width, alignment: .leading)

                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let detail {
                Text(detail)
                    .scaledFont(.note)
                    .foregroundStyle(theme.text(0.45))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, width + 14)
            }
        }
    }
}
