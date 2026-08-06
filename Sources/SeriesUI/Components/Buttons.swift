import SwiftUI

// Icons are SF Symbol names for now.
//
// Minute draws its own 37 glyphs on the grounds that SF Symbols are the
// system's handwriting and are recognised instantly as such — a fair argument,
// and the open question for the series. Every component here renders its icon
// in exactly ONE place, so swapping the icon layer later is a change inside
// this package rather than at hundreds of call sites.

/// Ghost capsule — the secondary action on a panel or a header row.
///
/// Invisible at rest, washed on hover (Notion's own popup-control pattern).
public struct PillButton: View {
    let systemImage: String
    /// An empty title renders an icon-only pill.
    let title: String
    let action: () -> Void
    let help: String

    @State private var hovering = false
    @Environment(\.seriesTheme) private var theme

    public init(systemImage: String, title: String, action: @escaping () -> Void, help: String) {
        self.systemImage = systemImage
        self.title = title
        self.action = action
        self.help = help
    }

    /// Shared content height, so icon-only pills match text pills — a bare
    /// glyph is shorter than a text line, which otherwise shrinks its capsule.
    public static let contentHeight: CGFloat = 18

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                if !systemImage.isEmpty {
                    Image(systemName: systemImage)
                }
                if !title.isEmpty {
                    Text(title)
                }
            }
            .scaledFont(.meta, weight: .bold, design: .rounded)
            .foregroundStyle(theme.text(hovering ? 1 : 0.7))
            .frame(height: Self.contentHeight)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            // The contentShape keeps the full capsule clickable even while the
            // fill is transparent.
            .background(Capsule().fill(hovering ? theme.fill(0.16) : .clear))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        // Most of these are icon-only, so without a label VoiceOver reads out
        // an SF Symbol name — or nothing. `help` is already written for a
        // human; it is the right label too.
        .accessibilityLabel(title.isEmpty ? help : title)
        .onHover { hovering = $0 }
        .pointingHand()
        .help(help)
    }
}

public enum InkButtonStyle: Sendable {
    /// Solid ink, label knocked out to the canvas colour. At most one per
    /// screen — that is what makes it read as the primary action.
    case primary
    case secondary
    /// Transparent until hovered.
    case ghost
    /// Solid negative. For the moment of commitment — the confirm button in a
    /// destructive dialog — and only there.
    case danger
    /// Negative label on a transparent ground, washing negative on hover.
    ///
    /// For the affordance that OPENS a destructive confirmation. A solid red
    /// block sitting permanently in a toolbar shouts before anything has been
    /// decided, and by the time the real commitment arrives it has nothing
    /// louder left to say.
    case dangerGhost
}

/// The standard button. Replaces `.borderedProminent` and `.bordered`.
public struct InkButton: View {
    var title: String
    var systemImage: String?
    var style: InkButtonStyle
    var small: Bool
    var disabled: Bool
    var help: String
    var action: () -> Void

    @State private var hovering = false
    @State private var pressed = false
    @Environment(\.seriesTheme) private var theme

    public init(
        _ title: String = "",
        systemImage: String? = nil,
        style: InkButtonStyle = .secondary,
        small: Bool = false,
        disabled: Bool = false,
        help: String = "",
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.style = style
        self.small = small
        self.disabled = disabled
        self.help = help
        self.action = action
    }

    private var height: CGFloat { small ? SeriesControl.smallHeight : SeriesControl.height }
    private var hPad: CGFloat { title.isEmpty ? (small ? 5 : 7) : (small ? 9 : 13) }
    private var active: Bool { hovering && !disabled }

    private var foreground: Color {
        switch style {
        case .primary: return theme.canvas
        case .danger: return .white
        case .dangerGhost: return active ? theme.negativeDeep : theme.negative
        case .secondary: return theme.text(active ? 1 : 0.85)
        case .ghost: return theme.text(active ? 1 : 0.65)
        }
    }

    private var background: Color {
        switch style {
        case .primary: return theme.ink.opacity(active ? 1 : 0.88)
        // Solid semantic buttons hover DARKER, never faded — see
        // `SeriesTheme.negativeDeep`.
        case .danger: return active ? theme.negativeDeep : theme.negative
        case .dangerGhost: return active ? theme.negative.opacity(0.14) : .clear
        case .secondary: return theme.fill(active ? 0.18 : 0.10)
        case .ghost: return active ? theme.fill(0.12) : .clear
        }
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage { Image(systemName: systemImage) }
                if !title.isEmpty { Text(title) }
            }
            .scaledFont(.meta)
            .foregroundStyle(foreground)
            .padding(.horizontal, hPad)
            .frame(height: height)
            .background(shape.fill(background))
            .overlay(shape.stroke(style == .secondary ? theme.cardBorder : .clear, lineWidth: 1))
            .opacity(disabled ? 0.35 : 1)
            .scaleEffect(pressed && !disabled ? 0.97 : 1)
            .animation(SeriesMotion.expand, value: pressed)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(help)
        // With an icon and no title, VoiceOver has nothing to read.
        .accessibilityLabel(title.isEmpty ? help : title)
        .onHover { hovering = $0 }
        .pointingHand(!disabled)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: SeriesRadius.row, style: .continuous)
    }
}

/// Square icon-only ghost button — toolbar add/remove/close.
public struct IconButton: View {
    var systemImage: String
    var size: CGFloat
    var tint: Color?
    var help: String
    var disabled: Bool
    var action: () -> Void

    @State private var hovering = false
    @Environment(\.seriesTheme) private var theme

    public init(
        systemImage: String,
        size: CGFloat = 26,
        tint: Color? = nil,
        help: String = "",
        disabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.size = size
        self.tint = tint
        self.help = help
        self.disabled = disabled
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.44))
                .foregroundStyle(tint ?? theme.text(hovering && !disabled ? 1 : 0.6))
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(hovering && !disabled ? theme.fill(0.14) : .clear)
                )
                .opacity(disabled ? 0.35 : 1)
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(help)
        .accessibilityLabel(help)
        .onHover { hovering = $0 }
        .pointingHand(!disabled)
    }
}
