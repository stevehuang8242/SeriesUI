import SwiftUI

/// The look of a selectable row in a sidebar or a history list.
///
/// Replaces `List`'s row, whose selection is drawn by the system in the system
/// accent colour — the one saturated blue on a surface whose whole palette is
/// one ink and an aurora. The series marks selection with a fill and a short
/// aurora capsule on the leading edge instead.
public struct SeriesListRow<Content: View>: View {
    var selected: Bool
    var action: () -> Void
    @ViewBuilder var content: () -> Content

    @State private var hovering = false
    @Environment(\.seriesTheme) private var theme

    public init(
        selected: Bool,
        action: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.selected = selected
        self.action = action
        self.content = content
    }

    public var body: some View {
        content()
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: SeriesRadius.row, style: .continuous)
                    .fill(selected ? theme.fill(0.14) : (hovering ? theme.fill(0.07) : .clear))
            )
            .overlay(alignment: .leading) {
                // Only on the selected row, and only 2.5pt wide: enough to find
                // at a glance down a long list, not enough to compete with the
                // row's own content.
                Capsule()
                    .fill(theme.auroraGradient)
                    .frame(width: 2.5)
                    .padding(.vertical, 6)
                    .opacity(selected ? 1 : 0)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            .onHover { hovering = $0 }
            .pointingHand()
    }
}

/// Long-form editing. The text engine is the system's — input methods,
/// selection, undo and spell-checking are behaviour worth keeping — but the
/// ground, the border and the type are ours.
public struct SeriesTextEditor: View {
    @Binding var text: String
    /// Prose being written for a person reads at the reading role; a prompt or
    /// a config file reads better monospaced.
    var monospaced: Bool

    @Environment(\.seriesTheme) private var theme
    @Environment(\.seriesTextScale) private var scale
    @Environment(\.seriesTypeScale) private var typeScale

    public init(text: Binding<String>, monospaced: Bool = false) {
        self._text = text
        self.monospaced = monospaced
    }

    public var body: some View {
        TextEditor(text: $text)
            .font(
                monospaced
                    ? .system(size: scale.apply(to: typeScale.size(.reading) - 3),
                              design: .monospaced)
                    : .system(size: scale.apply(to: typeScale.size(.reading)),
                              weight: theme.weight(SeriesTextRole.reading.weight))
            )
            .scrollContentBackground(.hidden)
            .foregroundStyle(theme.text(0.92))
            .padding(8)
            .background(shape.fill(theme.sunken))
            .overlay(shape.stroke(theme.cardBorder, lineWidth: 1))
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: SeriesRadius.row, style: .continuous)
    }
}

/// "Nothing here yet", with the one action that would change that.
/// Replaces `ContentUnavailableView`, which draws at system sizes in system
/// greys and ignores the text-size preference.
public struct SeriesEmptyState: View {
    var systemImage: String
    var title: String
    var message: String

    @Environment(\.seriesTheme) private var theme
    @Environment(\.seriesTextScale) private var scale

    public init(systemImage: String, title: String, message: String) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
    }

    public var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: scale.apply(to: 30), weight: .light))
                .foregroundStyle(theme.text(0.3))
            Text(title)
                .scaledFont(.header)
                .foregroundStyle(theme.text(0.7))
            Text(message)
                .scaledFont(.note)
                .foregroundStyle(theme.text(0.45))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
