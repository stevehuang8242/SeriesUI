import SwiftUI

/// The radius ladder. New surfaces pick a RUNG, not a number, so the corners
/// of the series stay in a fixed relationship to each other.
public enum SeriesRadius {
    /// Large cards, dialogs, onboarding.
    public static let card: CGFloat = 14
    /// Menus, bubbles.
    public static let bubble: CGFloat = 12
    /// List rows, buttons, text fields.
    public static let row: CGFloat = 8
    /// Micro controls — checkboxes.
    public static let tiny: CGFloat = 5
}

/// Standard control heights. A settings row and a toolbar button that disagree
/// by 2pt read as a mistake nobody can name.
public enum SeriesControl {
    public static let height: CGFloat = 28
    public static let smallHeight: CGFloat = 22
    public static let menuBarHeight: CGFloat = 30
}

/// The whole series has exactly two easings and no springs.
///
/// Nothing repeats forever: a persistent `repeatForever` animation leaks into
/// sibling layout on these panels (learned in ClaudeNotch, the hard way). Live
/// indicators are clock-driven through `TimelineView` instead — see `StatusDot`
/// and `ShimmerText`.
public enum SeriesMotion {
    /// Something arriving.
    public static let expand = Animation.easeOut(duration: 0.18)
    /// Something leaving.
    public static let collapse = Animation.easeIn(duration: 0.32)
}

/// A card's drop shadow together with the transparent border it needs to fade
/// out inside.
///
/// Borderless windows set `hasShadow = false` and let SwiftUI paint the shadow,
/// which means any of it past the padding is sliced off at a hard edge — and a
/// sliced Gaussian reads as a grey rectangle drawn around the card. Measured
/// against white, a Gaussian at this radius is still faintly visible about 2.2×
/// the radius out, and the offset carries it further down; that sum is what has
/// to be reserved.
///
/// Overlays drawn INSIDE a window (a menu layer in the root ZStack) have
/// nothing to be clipped by and can use `shadow` without the margin.
public struct SeriesCardShadow: Sendable {
    public var radius: CGFloat
    public var offsetY: CGFloat

    public init(radius: CGFloat, offsetY: CGFloat) {
        self.radius = radius
        self.offsetY = offsetY
    }

    public var margin: CGFloat { (radius * 2.2 + abs(offsetY)).rounded(.up) }

    /// Picker and answer cards.
    public static let panel = SeriesCardShadow(radius: 16, offsetY: 6)
    /// The smaller toast, which sits closer to the ground.
    public static let notice = SeriesCardShadow(radius: 12, offsetY: 4)
    /// A dropped menu.
    public static let menu = SeriesCardShadow(radius: 22, offsetY: 10)
    /// A modal dialog.
    public static let dialog = SeriesCardShadow(radius: 30, offsetY: 14)
}

extension View {
    /// Draws the shadow and reserves its room in one move, so the two can never
    /// drift apart into a clipped edge.
    public func cardShadow(_ shadow: SeriesCardShadow, color: Color) -> some View {
        self.shadow(color: color, radius: shadow.radius, y: shadow.offsetY)
            .padding(shadow.margin)
    }

    /// Calls `action` with this view's size on layout changes, so AppKit window
    /// controllers can size their panels to follow SwiftUI content.
    public func onContentSize(_ action: @escaping @MainActor (CGSize) -> Void) -> some View {
        background(GeometryReader { geo in
            Color.clear
                .onAppear { action(geo.size) }
                .onChange(of: geo.size) { _, size in action(size) }
        })
    }
}
