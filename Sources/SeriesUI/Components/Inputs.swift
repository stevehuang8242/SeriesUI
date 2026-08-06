import SwiftUI

/// Pick one of a few. Replaces `Picker(.segmented)`.
///
/// Use up to about four options; past that the labels stop fitting and the
/// choice belongs in a `SeriesDropdown`.
public struct SegmentedRail<Value: Hashable>: View {
    @Binding var selection: Value
    var options: [(value: Value, label: String)]
    var small: Bool

    @Environment(\.seriesTheme) private var theme

    public init(
        selection: Binding<Value>,
        options: [(value: Value, label: String)],
        small: Bool = false
    ) {
        self._selection = selection
        self.options = options
        self.small = small
    }

    private var index: Int {
        options.firstIndex { $0.value == selection } ?? 0
    }

    public var body: some View {
        GeometryReader { geo in
            let w = geo.size.width / CGFloat(max(1, options.count))
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: SeriesRadius.row - 2, style: .continuous)
                    .fill(theme.fill(0.16))
                    .frame(width: max(0, w - 4))
                    .padding(.vertical, 2)
                    .offset(x: w * CGFloat(index) + 2)
                    .animation(SeriesMotion.expand, value: index)

                HStack(spacing: 0) {
                    ForEach(Array(options.enumerated()), id: \.offset) { i, option in
                        Text(option.label)
                            .scaledFont(small ? .micro : .meta)
                            .foregroundStyle(theme.text(i == index ? 1 : 0.5))
                            .lineLimit(1)
                            .frame(width: w, height: geo.size.height)
                            .contentShape(Rectangle())
                            .onTapGesture { selection = option.value }
                            .pointingHand()
                            // `onTapGesture` is not a Button: without these,
                            // VoiceOver can neither read nor activate a segment.
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(option.label)
                            .accessibilityAddTraits(i == index ? [.isButton, .isSelected] : .isButton)
                            .accessibilityAction { selection = option.value }
                    }
                }
            }
        }
        .frame(height: small ? 24 : SeriesControl.height)
        .background(shape.fill(theme.fill(0.07)))
        .overlay(shape.stroke(theme.cardBorder, lineWidth: 1))
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: SeriesRadius.row, style: .continuous)
    }
}

/// Pick one of many. Replaces `Picker(.menu)`.
///
/// The closed control is ours; the dropped list is still the system's menu.
/// Minute draws that list too (`OverlayHost`), which is the better answer and
/// the one to port here — but it needs a window-root overlay layer, and the
/// closed state is what a settings screen shows 99% of the time.
public struct SeriesDropdown<Value: Hashable>: View {
    @Binding var selection: Value
    var options: [(value: Value, label: String)]
    /// Accessible name — the visible label lives in the `SettingRow` beside it.
    var label: String

    @Environment(\.seriesTheme) private var theme

    public init(
        selection: Binding<Value>,
        options: [(value: Value, label: String)],
        label: String
    ) {
        self._selection = selection
        self.options = options
        self.label = label
    }

    private var currentLabel: String {
        options.first { $0.value == selection }?.label ?? ""
    }

    public var body: some View {
        Menu {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                Button(option.label) { selection = option.value }
            }
        } label: {
            HStack(spacing: 8) {
                Text(currentLabel)
                    .scaledFont(.meta)
                    .foregroundStyle(theme.text(0.9))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(theme.text(0.4))
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .frame(height: SeriesControl.height)
            .background(shape.fill(theme.fill(0.07)))
            .overlay(shape.stroke(theme.cardBorder, lineWidth: 1))
            .contentShape(shape)
        }
        // `.button`, NOT `.borderlessButton`: the borderless style discards the
        // custom label and draws its own bare title-plus-chevron, which is how
        // the one styled control on the screen ends up as tinted text floating
        // with no well around it.
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .pointingHand()
        .accessibilityLabel(label)
        .accessibilityValue(currentLabel)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: SeriesRadius.row, style: .continuous)
    }
}

/// Single-line input. Replaces `TextField(.roundedBorder)` and `SecureField`.
public struct InkField: View {
    var placeholder: String
    @Binding var text: String
    var secure: Bool
    var systemImage: String?
    var onSubmit: () -> Void

    @FocusState private var focused: Bool
    @Environment(\.seriesTheme) private var theme

    public init(
        _ placeholder: String,
        text: Binding<String>,
        secure: Bool = false,
        systemImage: String? = nil,
        onSubmit: @escaping () -> Void = {}
    ) {
        self.placeholder = placeholder
        self._text = text
        self.secure = secure
        self.systemImage = systemImage
        self.onSubmit = onSubmit
    }

    public var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage).foregroundStyle(theme.text(focused ? 0.6 : 0.35))
            }
            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text(placeholder)
                        .scaledFont(.meta)
                        .foregroundStyle(theme.text(0.3))
                        .lineLimit(1)
                        .allowsHitTesting(false)
                }
                Group {
                    if secure {
                        SecureField("", text: $text)
                    } else {
                        TextField("", text: $text)
                    }
                }
                .textFieldStyle(.plain)
                .scaledFont(.meta)
                .foregroundStyle(theme.text(0.95))
                .focused($focused)
                .onSubmit(onSubmit)
                // The placeholder is drawn by us, so the system cannot see it.
                .accessibilityLabel(placeholder)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: SeriesControl.height)
        .background(shape.fill(theme.sunken))
        .overlay(shape.stroke(focused ? theme.focus.opacity(0.75) : theme.cardBorder, lineWidth: 1))
        .animation(SeriesMotion.expand, value: focused)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: SeriesRadius.row, style: .continuous)
    }
}

/// On or off. Replaces `Toggle(.switch)`.
public struct InkSwitch: View {
    @Binding var isOn: Bool
    /// Accessible name — the visible label is the `SettingRow`'s.
    var label: String

    @Environment(\.seriesTheme) private var theme

    public init(isOn: Binding<Bool>, label: String) {
        self._isOn = isOn
        self.label = label
    }

    public var body: some View {
        Capsule()
            .fill(isOn ? theme.ink.opacity(0.85) : theme.fill(0.14))
            .frame(width: 34, height: 20)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(isOn ? theme.canvas : theme.text(0.55))
                    .frame(width: 14, height: 14)
                    .padding(3)
            }
            .contentShape(Capsule())
            .onTapGesture { withAnimation(SeriesMotion.expand) { isOn.toggle() } }
            .pointingHand()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(isOn ? "On" : "Off")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { isOn.toggle() }
    }
}

/// A tick box. Replaces `Toggle(.checkbox)`.
public struct InkCheckbox: View {
    @Binding var isOn: Bool
    var label: String?

    @State private var hovering = false
    @Environment(\.seriesTheme) private var theme

    public init(isOn: Binding<Bool>, label: String? = nil) {
        self._isOn = isOn
        self.label = label
    }

    public var body: some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: SeriesRadius.tiny, style: .continuous)
                .fill(isOn ? theme.ink.opacity(0.9) : theme.fill(hovering ? 0.14 : 0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: SeriesRadius.tiny, style: .continuous)
                        .stroke(isOn ? .clear : theme.ink.opacity(hovering ? 0.35 : 0.22), lineWidth: 1)
                )
                .overlay(
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(theme.canvas)
                        .opacity(isOn ? 1 : 0)
                )
                .frame(width: 15, height: 15)
            if let label {
                Text(label).scaledFont(.meta).foregroundStyle(theme.text(0.8))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(SeriesMotion.expand) { isOn.toggle() } }
        .onHover { hovering = $0 }
        .pointingHand()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label ?? "Checkbox")
        .accessibilityValue(isOn ? "Checked" : "Unchecked")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { isOn.toggle() }
    }
}

/// Tabs with an aurora underline. Replaces `TabView`'s tab strip.
public struct UnderlineTabs<Value: Hashable>: View {
    @Binding var selection: Value
    var options: [(value: Value, label: String, systemImage: String?)]

    @Environment(\.seriesTheme) private var theme

    public init(
        selection: Binding<Value>,
        options: [(value: Value, label: String, systemImage: String?)]
    ) {
        self._selection = selection
        self.options = options
    }

    public var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let on = option.value == selection
                // The underline is an `overlay`, NOT a sibling in a VStack:
                // `Capsule` has no intrinsic width, so as a sibling it stretches
                // every tab to equal width and the strip reads as a phone tab bar.
                HStack(spacing: 6) {
                    if let image = option.systemImage { Image(systemName: image) }
                    Text(option.label).scaledFont(.meta)
                }
                .foregroundStyle(theme.text(on ? 1 : 0.5))
                .padding(.horizontal, 10)
                .padding(.top, 9)
                .padding(.bottom, 8)
                // Fill the chrome's height so the underline sits on the hairline
                // below it rather than floating in mid-air.
                .frame(maxHeight: .infinity)
                .overlay(alignment: .bottom) {
                    Capsule()
                        .fill(on ? AnyShapeStyle(theme.auroraGradient) : AnyShapeStyle(Color.clear))
                        .frame(height: 2)
                }
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(SeriesMotion.expand) { selection = option.value } }
                .pointingHand()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(option.label)
                .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
                .accessibilityAction { selection = option.value }
            }
        }
    }
}
