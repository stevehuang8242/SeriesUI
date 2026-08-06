import AppKit
import SwiftUI

// In-window overlay host — replaces `Menu`'s popup, `.popover`, `.contextMenu`,
// `.alert` and `.sheet`.
//
// Each of those brings its own material, corner radius, shadow and timing, none
// of which agree with the surfaces around them. They collapse into two layers,
// both drawn in the window's root ZStack:
//
//   · MenuLayer   — dropdowns and context menus (one component; the difference
//                   is only where the anchor comes from)
//   · DialogLayer — confirmations and prompts (a scrim and a centred card, not
//                   the system's sheet of paper sliding out of the title bar)
//
// Anchors travel through the `"series-overlay-root"` named coordinate space, so
// a caller only ever has to measure its own frame.
//
// Ported from Minute, where this has been in daily use; the keyboard handling
// in particular is the version that survived contact with real use.

public struct SeriesMenuItem: Identifiable, Sendable {
    public let id = UUID()
    public var title: String = ""
    public var systemImage: String?
    public var checked = false
    public var destructive = false
    public var enabled = true
    public var isSeparator = false
    public var action: @MainActor @Sendable () -> Void = {}

    public static func item(
        _ title: String,
        systemImage: String? = nil,
        checked: Bool = false,
        destructive: Bool = false,
        enabled: Bool = true,
        action: @escaping @MainActor @Sendable () -> Void
    ) -> SeriesMenuItem {
        SeriesMenuItem(
            title: title, systemImage: systemImage, checked: checked,
            destructive: destructive, enabled: enabled, action: action
        )
    }

    public static var separator: SeriesMenuItem {
        SeriesMenuItem(isSeparator: true)
    }

    var rowHeight: CGFloat { isSeparator ? 9 : 30 }
}

public struct SeriesMenuRequest: Identifiable, Sendable {
    public let id = UUID()
    public var anchor: CGRect
    public var width: CGFloat = 220
    /// true aligns the menu's trailing edge to the anchor's — for controls that
    /// sit at the right of a toolbar.
    public var alignTrailing = false
    /// Adds a filter field, for lists long enough that scanning them is work.
    public var filterable = false
    public var items: [SeriesMenuItem]

    public init(
        anchor: CGRect,
        width: CGFloat = 220,
        alignTrailing: Bool = false,
        filterable: Bool = false,
        items: [SeriesMenuItem]
    ) {
        self.anchor = anchor
        self.width = width
        self.alignTrailing = alignTrailing
        self.filterable = filterable
        self.items = items
    }
}

/// What a dialog came back with. A dialog can carry a second, genuinely
/// separate decision alongside its main one — "uninstall" and "also delete the
/// things I wrote" are not the same question, and answering the first must not
/// silently answer the second.
public struct SeriesDialogResult: Sendable {
    public var text: String
    public var checked: Bool
}

public struct SeriesDialogRequest: Identifiable, Sendable {
    public let id = UUID()
    public var title: String
    public var message: String?
    public var fieldPlaceholder: String?
    public var fieldInitial: String = ""
    /// A secondary opt-in shown above the buttons.
    public var checkboxTitle: String?
    public var confirmTitle: String = "OK"
    public var cancelTitle: String = "Cancel"
    public var destructive = false
    public var onConfirm: @MainActor @Sendable (SeriesDialogResult) -> Void = { _ in }

    public init(
        title: String,
        message: String? = nil,
        fieldPlaceholder: String? = nil,
        fieldInitial: String = "",
        checkboxTitle: String? = nil,
        confirmTitle: String = "OK",
        cancelTitle: String = "Cancel",
        destructive: Bool = false,
        onConfirm: @escaping @MainActor @Sendable (SeriesDialogResult) -> Void = { _ in }
    ) {
        self.title = title
        self.message = message
        self.fieldPlaceholder = fieldPlaceholder
        self.fieldInitial = fieldInitial
        self.checkboxTitle = checkboxTitle
        self.confirmTitle = confirmTitle
        self.cancelTitle = cancelTitle
        self.destructive = destructive
        self.onConfirm = onConfirm
    }
}

@MainActor
public final class SeriesOverlayHost: ObservableObject {
    public static let space = "series-overlay-root"

    @Published var menu: SeriesMenuRequest?
    @Published var dialog: SeriesDialogRequest?

    public init() {}

    public func show(_ request: SeriesMenuRequest) {
        dialog = nil
        menu = request
    }

    public func show(_ request: SeriesDialogRequest) {
        menu = nil
        dialog = request
    }

    public func dismiss() {
        menu = nil
        dialog = nil
    }

    /// Context menu: the click point as a zero-width anchor.
    public func showContextMenu(at point: CGPoint, width: CGFloat = 220, items: [SeriesMenuItem]) {
        show(SeriesMenuRequest(anchor: CGRect(origin: point, size: .zero), width: width, items: items))
    }
}

private struct SeriesOverlayHostKey: @preconcurrency EnvironmentKey {
    @MainActor static let defaultValue: SeriesOverlayHost? = nil
}

extension EnvironmentValues {
    /// The overlay host for this window, if it has one.
    ///
    /// Optional on purpose. As an `@EnvironmentObject` a missing host is a
    /// `fatalError` inside a library, which turns "this view was used outside a
    /// `SeriesOverlayRoot`" into a crash with no name on it. Controls that need
    /// a host check for one and degrade instead.
    public var seriesOverlayHost: SeriesOverlayHost? {
        get { self[SeriesOverlayHostKey.self] }
        set { self[SeriesOverlayHostKey.self] = newValue }
    }
}

/// Wrap a window's content in this to give it a menu and dialog layer.
public struct SeriesOverlayRoot<Content: View>: View {
    @StateObject private var host = SeriesOverlayHost()
    @ViewBuilder var content: () -> Content

    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                content()
                    .environmentObject(host)
                    .environment(\.seriesOverlayHost, host)
                    .frame(width: geo.size.width, height: geo.size.height)
                    // While a dialog is open the content beneath must vanish for
                    // assistive technology too. The scrim blocks the MOUSE, but
                    // not `.accessibilityAction` — so without this, VoiceOver can
                    // still flip the very switch the dialog is asking about.
                    // `.alert` gave this for free; drawing our own has to pay for it.
                    .accessibilityHidden(host.dialog != nil)
                if let menu = host.menu {
                    MenuLayer(request: menu, bounds: geo.size).environmentObject(host)
                }
                if let dialog = host.dialog {
                    DialogLayer(request: dialog).environmentObject(host)
                }
            }
            .coordinateSpace(name: SeriesOverlayHost.space)
        }
    }
}

// MARK: - Menu layer

private struct MenuLayer: View {
    @EnvironmentObject var host: SeriesOverlayHost
    @Environment(\.seriesTheme) private var theme
    let request: SeriesMenuRequest
    let bounds: CGSize

    @State private var filter = ""
    @State private var hovered: UUID?
    /// nil means the keyboard has not been used yet. Lighting up the first row
    /// on open reads as "this is already chosen" when the user has done
    /// nothing; an arrow key is what gives it a position.
    @State private var highlighted: Int?
    @FocusState private var filterFocused: Bool
    /// The panel's own focus. Without it a non-filterable menu receives no
    /// arrow keys at all.
    @FocusState private var panelFocused: Bool

    private var items: [SeriesMenuItem] {
        guard request.filterable, !filter.isEmpty else { return request.items }
        return request.items.filter {
            !$0.isSeparator && $0.title.localizedCaseInsensitiveContains(filter)
        }
    }

    /// What the keyboard can reach — separators and disabled rows are skipped.
    private var selectable: [SeriesMenuItem] {
        items.filter { !$0.isSeparator && $0.enabled }
    }

    /// Filtering changes the item count, which changes the height, which moves
    /// the origin — and the panel jumps around under the pointer. A filterable
    /// menu is laid out at its UNFILTERED height; whitespace beats a jump.
    private var contentHeight: CGFloat {
        let source = request.filterable ? request.items : items
        return min(300, source.reduce(0) { $0 + $1.rowHeight })
    }

    private var panelHeight: CGFloat {
        contentHeight + 12 + (request.filterable ? 38 : 0)
    }

    private var origin: CGPoint {
        let x = request.alignTrailing ? request.anchor.maxX - request.width : request.anchor.minX
        let clampedX = min(max(8, x), max(8, bounds.width - request.width - 8))
        var y = request.anchor.maxY + 6
        // No room below: flip above the anchor rather than run off the window.
        if y + panelHeight > bounds.height - 8 {
            y = request.anchor.minY - 6 - panelHeight
        }
        return CGPoint(x: clampedX, y: min(max(8, y), max(8, bounds.height - panelHeight - 8)))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Click outside to close. Right-clicks pass through, so one context
            // menu can be replaced by the next without an extra dismiss.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { host.dismiss() }

            panel
                .frame(width: request.width)
                .offset(x: origin.x, y: origin.y)
        }
        .frame(width: bounds.width, height: bounds.height, alignment: .topLeading)
        .background(escapeHatch)
    }

    private var panel: some View {
        VStack(spacing: 0) {
            if request.filterable {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.text(0.4))
                    TextField("Filter", text: $filter)
                        .textFieldStyle(.plain)
                        .scaledFont(.meta)
                        .foregroundStyle(theme.text(0.9))
                        .focused($filterFocused)
                }
                .padding(.horizontal, 12)
                .frame(height: 32)
                Hairline()
            }

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(items) { row($0) }
                }
                .padding(.vertical, 6)
            }
            .scrollIndicators(.hidden)
            .frame(height: contentHeight + 12)
        }
        .background(shape.fill(theme.raised))
        .clipShape(shape)
        .overlay(shape.stroke(theme.cardBorder, lineWidth: 1))
        .shadow(color: theme.cardShadow,
                radius: SeriesCardShadow.menu.radius,
                y: SeriesCardShadow.menu.offsetY)
        // Keyboard operation. SwiftUI does not hand focus to a newly appearing
        // focusable view, so a non-filterable menu has to claim it explicitly —
        // otherwise arrow keys do nothing unless the user Tabs in first, and
        // full keyboard access is off by default.
        //
        // Escape has always worked because `.cancelAction` does not depend on
        // focus, which is exactly what hid this.
        .focusable()
        .focused($panelFocused)
        // Focus yes, focus ring no: a system-blue rectangle around the whole
        // card reads as "this card is selected" when it has merely opened.
        // Where the keyboard is shows through the highlight instead.
        .focusEffectDisabled()
        .onAppear {
            if request.filterable {
                filterFocused = true
            } else {
                panelFocused = true
            }
        }
        .onKeyPress(.downArrow) { moveHighlight(1); return .handled }
        .onKeyPress(.upArrow) { moveHighlight(-1); return .handled }
        .onKeyPress(.return) { activateHighlighted(); return .handled }
        // Highlighting the first row WHILE filtering is right: the field has
        // focus, and typing then pressing Return is the main gesture. Clearing
        // the filter goes back to "nothing chosen".
        .onChange(of: filter) { _, new in highlighted = new.isEmpty ? nil : 0 }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: SeriesRadius.bubble, style: .continuous)
    }

    private func moveHighlight(_ delta: Int) {
        guard !selectable.isEmpty else { return }
        guard let current = highlighted else {
            // First press: down starts at the top, up at the bottom — not at an
            // offset from an invisible row zero.
            highlighted = delta > 0 ? 0 : selectable.count - 1
            return
        }
        highlighted = (current + delta + selectable.count) % selectable.count
    }

    private func activateHighlighted() {
        guard let index = highlighted, selectable.indices.contains(index) else { return }
        let item = selectable[index]
        host.dismiss()
        item.action()
    }

    private func isHighlighted(_ item: SeriesMenuItem) -> Bool {
        guard let index = highlighted, selectable.indices.contains(index) else { return false }
        return selectable[index].id == item.id
    }

    @ViewBuilder
    private func row(_ item: SeriesMenuItem) -> some View {
        if item.isSeparator {
            Hairline().padding(.vertical, 4)
        } else {
            let active = (hovered == item.id || isHighlighted(item)) && item.enabled
            HStack(spacing: 8) {
                if let image = item.systemImage {
                    Image(systemName: image).frame(width: 14)
                } else if request.items.contains(where: { $0.checked }) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 14)
                        .opacity(item.checked ? 1 : 0)
                }
                Text(item.title).scaledFont(.meta).lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(
                item.destructive
                    ? theme.negative
                    : theme.text(item.enabled ? (active ? 1 : 0.8) : 0.3)
            )
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(active ? theme.fill(0.14) : .clear)
                    .padding(.horizontal, 5)
            )
            .contentShape(Rectangle())
            .onHover { hovered = $0 ? item.id : (hovered == item.id ? nil : hovered) }
            .onTapGesture {
                guard item.enabled else { return }
                host.dismiss()
                item.action()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(item.title)
            .accessibilityValue(item.checked ? "Selected" : "")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                guard item.enabled else { return }
                host.dismiss()
                item.action()
            }
        }
    }

    /// Escape closes. The behaviour is the system's; the look is not.
    private var escapeHatch: some View {
        Button("") { host.dismiss() }
            .keyboardShortcut(.cancelAction)
            .buttonStyle(.plain)
            .opacity(0)
            .frame(width: 0, height: 0)
    }
}

// MARK: - Dialog layer

private struct DialogLayer: View {
    @EnvironmentObject var host: SeriesOverlayHost
    @Environment(\.seriesTheme) private var theme
    let request: SeriesDialogRequest

    @State private var text = ""
    @State private var checked = false
    /// Moves VoiceOver's focus to the dialog when it appears. Without it the
    /// dialog arrives silently — `.isModal` shuts the outside away but does not
    /// announce that something is now waiting for an answer.
    @AccessibilityFocusState private var titleFocused: Bool

    var body: some View {
        ZStack {
            theme.scrim
                .contentShape(Rectangle())
                .onTapGesture {
                    // Don't throw away typing because the background was
                    // clicked. Escape and Cancel are two explicit ways out
                    // already; a third that fires by accident is not needed.
                    guard !isDirty else { return }
                    host.dismiss()
                }

            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(request.title)
                        .scaledFont(.display)
                        .foregroundStyle(theme.ink)
                        .accessibilityFocused($titleFocused)
                    if let message = request.message {
                        Text(message)
                            .scaledFont(.meta)
                            .foregroundStyle(theme.text(0.55))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 16)

                if let placeholder = request.fieldPlaceholder {
                    InkField(placeholder, text: $text, onSubmit: confirm)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                }

                if let checkboxTitle = request.checkboxTitle {
                    InkCheckbox(isOn: $checked, label: checkboxTitle)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                }

                Hairline()

                HStack(spacing: 8) {
                    Spacer()
                    InkButton(request.cancelTitle, style: .ghost) { host.dismiss() }
                        .keyboardShortcut(.cancelAction)
                    InkButton(
                        request.confirmTitle,
                        style: request.destructive ? .danger : .primary,
                        action: confirm
                    )
                    .keyboardShortcut(.defaultAction)
                }
                .padding(12)
            }
            .frame(width: 400)
            .background(cardShape.fill(theme.raised))
            .clipShape(cardShape)
            .overlay(cardShape.stroke(theme.cardBorder, lineWidth: 1))
            .shadow(color: theme.cardShadow,
                    radius: SeriesCardShadow.dialog.radius,
                    y: SeriesCardShadow.dialog.offsetY)
        }
        // Declares modality to assistive technology. Both halves are needed:
        // `.isModal` states the intent, `SeriesOverlayRoot`'s
        // `.accessibilityHidden` is what actually shuts the outside away.
        .accessibilityAddTraits(.isModal)
        .onAppear {
            text = request.fieldInitial
            titleFocused = true
        }
    }

    /// The user has typed something they would lose.
    private var isDirty: Bool {
        request.fieldPlaceholder != nil && text != request.fieldInitial
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: SeriesRadius.card, style: .continuous)
    }

    private func confirm() {
        let result = SeriesDialogResult(text: text, checked: checked)
        host.dismiss()
        request.onConfirm(result)
    }
}

// MARK: - Measuring and right-click

/// Reports this view's frame in the overlay root's coordinate space, which is
/// what a menu anchor is.
private struct RootFrame: ViewModifier {
    @Binding var frame: CGRect

    func body(content: Content) -> some View {
        content.background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { frame = geo.frame(in: .named(SeriesOverlayHost.space)) }
                    .onChange(of: geo.frame(in: .named(SeriesOverlayHost.space))) { _, new in
                        frame = new
                    }
            }
        )
    }
}

/// A transparent layer that intercepts ONLY right-clicks (and control-clicks).
/// Left-click events pass straight through to SwiftUI.
private struct RightClickCatcher: NSViewRepresentable {
    var onClick: (CGPoint) -> Void

    final class CatcherView: NSView {
        var onClick: ((CGPoint) -> Void)?
        override var isFlipped: Bool { true }
        override func menu(for event: NSEvent) -> NSMenu? { nil }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent else { return nil }
            switch event.type {
            case .rightMouseDown, .rightMouseUp, .rightMouseDragged:
                return super.hitTest(point)
            case .leftMouseDown where event.modifierFlags.contains(.control):
                return super.hitTest(point)
            default:
                return nil
            }
        }

        override func rightMouseDown(with event: NSEvent) {
            onClick?(convert(event.locationInWindow, from: nil))
        }

        override func mouseDown(with event: NSEvent) {
            guard event.modifierFlags.contains(.control) else { return super.mouseDown(with: event) }
            onClick?(convert(event.locationInWindow, from: nil))
        }
    }

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onClick = onClick
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.onClick = onClick
    }
}

extension View {
    public func rootFrame(_ frame: Binding<CGRect>) -> some View {
        modifier(RootFrame(frame: frame))
    }

    /// Right-click position, reported in the overlay root's coordinates so it
    /// can be handed straight to `showContextMenu(at:)`.
    public func onRightClick(perform: @escaping (CGPoint) -> Void) -> some View {
        overlay(
            GeometryReader { geo in
                RightClickCatcher { local in
                    let origin = geo.frame(in: .named(SeriesOverlayHost.space)).origin
                    perform(CGPoint(x: origin.x + local.x, y: origin.y + local.y))
                }
            }
        )
    }
}
