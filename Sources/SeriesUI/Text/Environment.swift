import SwiftUI

// The theme and the two type preferences travel through the environment rather
// than being read from storage at each call site.
//
// This is what makes appearance changes land LIVE. Gloss used to resolve the
// theme once when a window opened, from `UserDefaults`, into a stored property
// — so switching to Light did nothing until the window was closed and reopened,
// and the settings window never restyled itself at all. An environment value
// re-evaluates every dependent view the moment it changes, which also means a
// settings screen is its own preview for free.

private struct SeriesThemeKey: EnvironmentKey {
    static let defaultValue = SeriesTheme()
}

private struct SeriesTextScaleKey: EnvironmentKey {
    static let defaultValue = SeriesTextScale.standard
}

private struct SeriesTypefaceKey: EnvironmentKey {
    static let defaultValue = SeriesTypeface.standard
}

extension EnvironmentValues {
    public var seriesTheme: SeriesTheme {
        get { self[SeriesThemeKey.self] }
        set { self[SeriesThemeKey.self] = newValue }
    }

    public var seriesTextScale: SeriesTextScale {
        get { self[SeriesTextScaleKey.self] }
        set { self[SeriesTextScaleKey.self] = newValue }
    }

    public var seriesTypeface: SeriesTypeface {
        get { self[SeriesTypefaceKey.self] }
        set { self[SeriesTypefaceKey.self] = newValue }
    }
}

private struct SeriesStyle: ViewModifier {
    @ObservedObject var preferences: SeriesPreferences
    let typeScale: SeriesTypeScale
    /// The ambient scheme, read from OUTSIDE this modifier — so when the user
    /// is on System and macOS flips, this changes and everything below
    /// re-renders. Writing `colorScheme` below does not disturb this read.
    @Environment(\.colorScheme) private var systemScheme

    func body(content: Content) -> some View {
        let theme = SeriesTheme(
            appearance: preferences.appearance,
            scheme: preferences.appearance.resolve(system: systemScheme)
        )
        content
            .environment(\.seriesTheme, theme)
            .environment(\.seriesTextScale, preferences.textScale)
            .environment(\.seriesTypeface, preferences.typeface)
            .environment(\.seriesTypeScale, typeScale)
            // The few system-drawn things left — text insertion points, menu
            // popups, `textSelection` highlights — follow the choice too.
            .environment(\.colorScheme, theme.scheme)
            .tint(theme.focus)
    }
}

extension View {
    /// Root of every window and panel in a series app. Everything below draws
    /// from the same theme, scale and typeface, and restyles live when any of
    /// the three changes.
    ///
    /// `typeScale` is the app's own point sizes for the shared roles — see
    /// `SeriesTypeScale`. It defaults to the reading sizes; a dense gauge
    /// passes `.compact`.
    public func seriesStyle(
        _ preferences: SeriesPreferences,
        typeScale: SeriesTypeScale = .reading
    ) -> some View {
        modifier(SeriesStyle(preferences: preferences, typeScale: typeScale))
    }
}
