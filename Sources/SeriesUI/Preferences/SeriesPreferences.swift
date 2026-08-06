import AppKit
import SwiftUI

// The three preferences every app in the series exposes.
//
// These are a SHARED SCHEMA, NOT SHARED STATE. Each app stores its own value:
// the apps have genuinely different physical constraints (ClaudeNotch's bar is
// hardware-sized and wraps a black notch; Gloss's card sits beside the text you
// are reading; Minute's window is where you spend an hour), so someone who
// wants Large in a reading tool does not thereby want Large in an ambient
// gauge. What is shared is the vocabulary — the same option names, in the same
// order, meaning the same thing — so "Large" is one size across the series and
// the third typeface is never Rounded in one app and Mono in another.
//
// Storage is per-app for free: the apps have distinct bundle identifiers, so
// the same key in each one's `UserDefaults.standard` is already isolated.

/// Light, dark, or whatever the system is doing.
///
/// ClaudeNotch shipped without `system` and Minute defaults to it; both stay
/// true here — the CASES are shared, the DEFAULT is each app's own call.
public enum SeriesAppearance: String, CaseIterable, Sendable, Identifiable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    /// Written the way macOS System Settings writes it — one word, no verb.
    /// "Follow system" / "Always light" would burst the segmented rail the
    /// moment the interface is in English (see docs/design-language.md).
    public var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    public var systemImage: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    /// What this choice resolves to right now, given what the system is doing.
    public func resolve(system: ColorScheme) -> ColorScheme {
        switch self {
        case .system: return system
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// The same, resolved against what macOS is doing at this moment.
    ///
    /// For chrome drawn OUTSIDE the styled subtree — a view that applies
    /// `seriesStyle` cannot also read the theme it just injected, since a
    /// modifier's environment reaches its children and not itself. Prefer
    /// `@Environment(\.seriesTheme)` wherever it is available: this resolves
    /// once rather than following a system flip live.
    @MainActor
    public func resolvedAgainstSystem() -> ColorScheme {
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return resolve(system: dark ? .dark : .light)
    }

    /// For AppKit surfaces that sit outside SwiftUI's environment — an
    /// `NSWindow`'s own appearance, a status-item view. nil means "follow the
    /// system", which is what an unset `NSWindow.appearance` already does.
    public var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

/// The typeface choice, which is a `Font.Design` and never a font family.
///
/// Enumerating installed families would let someone pick one with no CJK
/// coverage, and every family would need its sizes and line heights re-tuned.
/// All three designs ride the same system fallback chain, so mixed Chinese and
/// English keeps working (Minute's reasoning, adopted for the series).
public enum SeriesTypeface: String, CaseIterable, Sendable, Identifiable {
    case standard = "default"
    case serif
    case mono

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .standard: return "Default"
        case .serif: return "Serif"
        case .mono: return "Mono"
        }
    }

    /// nil keeps each text role's own design, so `micro` stays rounded.
    /// Choosing serif or mono overrides every role — otherwise the small caps
    /// labels stay rounded in serif mode and read as a missed edit.
    public var design: Font.Design? {
        switch self {
        case .standard: return nil
        case .serif: return .serif
        case .mono: return .monospaced
        }
    }
}

/// How large the whole type scale runs.
///
/// Named steps rather than a free slider: the roles are tuned relative to each
/// other and an arbitrary multiplier lets the hierarchy come apart. An app may
/// offer a SUBSET (`Minute` has no reason to go to Extra Large), but wherever a
/// step is offered it means the same multiplier.
public enum SeriesTextScale: String, CaseIterable, Sendable, Identifiable {
    case small = "s"
    case standard = "m"
    case large = "l"
    case extraLarge = "xl"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .small: return "Small"
        case .standard: return "Standard"
        case .large: return "Large"
        case .extraLarge: return "Extra Large"
        }
    }

    public var multiplier: Double {
        switch self {
        case .small: return 0.875
        case .standard: return 1.0
        case .large: return 1.15
        case .extraLarge: return 1.3
        }
    }

    /// Rounded to a whole point: SwiftUI will lay out at 18.4pt happily enough,
    /// but fractional sizes make the baselines of adjacent roles disagree.
    public func apply(to size: CGFloat) -> CGFloat {
        (size * multiplier).rounded()
    }

    /// Nearest step to a raw multiplier — for ClaudeNotch, which stored a
    /// continuous 0.9…1.4 from its A−/A+ buttons.
    public static func nearest(to multiplier: Double) -> SeriesTextScale {
        allCases.min { abs($0.multiplier - multiplier) < abs($1.multiplier - multiplier) } ?? .standard
    }

    /// One step along the ladder, clamped. Keeps A−/A+ affordances working
    /// against the shared steps rather than against a free multiplier.
    public func stepped(by delta: Int) -> SeriesTextScale {
        let all = Self.allCases
        guard let index = all.firstIndex(of: self) else { return self }
        let next = min(max(index + delta, 0), all.count - 1)
        return all[next]
    }
}

// MARK: - Storage

/// Where a host app keeps its preferences. `UserDefaults` covers Gloss and
/// ClaudeNotch; Minute keeps a JSON config it also reads from a CLI, so it
/// supplies its own conformance rather than being made to move.
public protocol SeriesPreferenceStore: AnyObject {
    func string(forSeriesKey key: String) -> String?
    func setString(_ value: String?, forSeriesKey key: String)
}

extension UserDefaults: SeriesPreferenceStore {
    public func string(forSeriesKey key: String) -> String? { string(forKey: key) }

    public func setString(_ value: String?, forSeriesKey key: String) {
        if let value { set(value, forKey: key) } else { removeObject(forKey: key) }
    }
}

/// The keys, identical across the series so a preference is recognisable from
/// one app's defaults dump to the next.
public enum SeriesPreferenceKey {
    public static let appearance = "appearance"
    public static let typeface = "typeface"
    public static let textScale = "textScale"
}

/// The live preference values, observable so every surface restyles the moment
/// one changes — the settings screen included, which is what makes it its own
/// preview.
@MainActor
public final class SeriesPreferences: ObservableObject {
    private let store: SeriesPreferenceStore

    @Published public var appearance: SeriesAppearance {
        didSet { store.setString(appearance.rawValue, forSeriesKey: SeriesPreferenceKey.appearance) }
    }

    @Published public var typeface: SeriesTypeface {
        didSet { store.setString(typeface.rawValue, forSeriesKey: SeriesPreferenceKey.typeface) }
    }

    @Published public var textScale: SeriesTextScale {
        didSet { store.setString(textScale.rawValue, forSeriesKey: SeriesPreferenceKey.textScale) }
    }

    /// - Parameters:
    ///   - defaultAppearance: each app's own call. ClaudeNotch wraps a black
    ///     notch and has reason to start dark; Minute follows the system.
    ///   - legacyKeys: keys this app wrote before adopting the shared schema.
    ///     Read once, so nobody's existing choice is reset by the migration.
    public init(
        store: SeriesPreferenceStore,
        defaultAppearance: SeriesAppearance = .system,
        defaultTypeface: SeriesTypeface = .standard,
        defaultTextScale: SeriesTextScale = .standard,
        legacyKeys: LegacyKeys = LegacyKeys()
    ) {
        self.store = store

        let appearanceRaw = store.string(forSeriesKey: SeriesPreferenceKey.appearance)
            ?? legacyKeys.appearance.flatMap { store.string(forSeriesKey: $0) }
        appearance = appearanceRaw.flatMap(SeriesAppearance.init(rawValue:)) ?? defaultAppearance

        let typefaceRaw = store.string(forSeriesKey: SeriesPreferenceKey.typeface)
            ?? legacyKeys.typeface.flatMap { store.string(forSeriesKey: $0) }
        typeface = typefaceRaw.flatMap(Self.migratedTypeface(from:)) ?? defaultTypeface

        let scaleRaw = store.string(forSeriesKey: SeriesPreferenceKey.textScale)
        if let scale = scaleRaw.flatMap(SeriesTextScale.init(rawValue:)) {
            textScale = scale
        } else if let legacy = legacyKeys.textScaleMultiplier.flatMap({ store.string(forSeriesKey: $0) }),
                  let multiplier = Double(legacy), multiplier > 0 {
            // Gloss stored the multiplier itself, ClaudeNotch a continuous
            // value from its A−/A+ buttons. Both land on the nearest step.
            textScale = .nearest(to: multiplier)
        } else {
            textScale = defaultTextScale
        }
    }

    /// Gloss's third typeface was Rounded, Minute's is Mono, and the series
    /// only gets one. Rounded loses — it is already the `micro` role's design,
    /// so as a global override it flattened the one place rounded meant
    /// something. Anyone who had it lands on Default rather than on a value
    /// the enum cannot represent.
    private static func migratedTypeface(from raw: String) -> SeriesTypeface? {
        if raw == "rounded" { return .standard }
        return SeriesTypeface(rawValue: raw)
    }

    /// Pre-schema key names, per app.
    public struct LegacyKeys: Sendable {
        public var appearance: String?
        public var typeface: String?
        public var textScaleMultiplier: String?

        public init(
            appearance: String? = nil,
            typeface: String? = nil,
            textScaleMultiplier: String? = nil
        ) {
            self.appearance = appearance
            self.typeface = typeface
            self.textScaleMultiplier = textScaleMultiplier
        }
    }
}
