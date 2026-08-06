import AppKit
import SwiftUI

/// The series palette.
///
/// Assembled from what the three apps had each worked out separately, keeping
/// the best version of each: ClaudeNotch's light-mode contrast compensation
/// (`textAlpha`), Minute's four-surface ladder, Gloss's aurora and card chrome.
/// Every colour in every app comes from here.
///
/// **All text is one ink at varying strength — there is no second text colour.**
/// All fills go through `fill(_:)`. That is what lets a theme flip restyle a
/// whole surface coherently rather than leaving stragglers behind.
///
/// The two grounds are perceptually asymmetric, so light mode is not a 1:1
/// remap of the dark values. Three corrections, and they do not all point the
/// same way:
///
/// - `fill(_:)` HALVES the alpha — nothing glows on a light ground, so the same
///   alpha reads as a much heavier block.
/// - `textAlpha(_:)` RAISES it — white-on-black is thickened by halation and
///   stays legible when faded; charcoal-on-white loses contrast fast.
/// - `weight(_:)` steps DOWN one notch — dark-on-light carries more visual mass.
public struct SeriesTheme: Equatable, Sendable {
    /// What the user chose, kept so a settings screen can show the selection
    /// (including `system`, which `scheme` alone cannot express).
    public var appearance: SeriesAppearance
    /// What that resolves to right now. Everything visual keys off this.
    public var scheme: ColorScheme

    public init(appearance: SeriesAppearance = .dark, scheme: ColorScheme? = nil) {
        self.appearance = appearance
        self.scheme = scheme ?? (appearance == .light ? .light : .dark)
    }

    private var isDark: Bool { scheme == .dark }

    // MARK: - Ink

    /// Primary text colour; every label derives from it via opacity. Light mode
    /// is Notion's warm charcoal rather than dead black — full-strength labels
    /// land softer, and every derived grey inherits the warm cast.
    public var ink: Color {
        isDark ? .white : Color(red: 0x37 / 255, green: 0x35 / 255, blue: 0x2F / 255)
    }

    /// Fill for chips, pills and hover washes, given the alpha tuned for dark.
    public func fill(_ darkOpacity: Double) -> Color {
        ink.opacity(isDark ? darkOpacity : darkOpacity / 2)
    }

    /// Text alpha, given the value tuned for dark.
    ///
    /// The recessed labels that read fine at 0.35 / 0.45 / 0.55 on black land at
    /// 1.98:1 / 2.49:1 / 3.20:1 on white. Light mode maps them up to
    /// 0.60 / 0.62 / 0.70 (3.65:1 / 3.86:1 / 4.84:1), interpolating in between;
    /// 0.75 and up (5.6:1+) pass through unchanged.
    ///
    /// The two lower tiers stay under AA's 4.5:1 by design: reaching it needs
    /// ~0.68, which is the primary tier, at which point nothing is recessed at
    /// all. The hierarchy still reads through size and weight.
    public func textAlpha(_ darkAlpha: Double) -> Double {
        guard !isDark else { return darkAlpha }
        let ramp: [(dark: Double, light: Double)] = [
            (0, 0), (0.35, 0.60), (0.45, 0.62), (0.55, 0.70), (0.75, 0.75), (1, 1),
        ]
        guard let above = ramp.firstIndex(where: { $0.dark >= darkAlpha }) else { return darkAlpha }
        guard above > 0 else { return ramp[0].light }
        let (lo, hi) = (ramp[above - 1], ramp[above])
        let t = (darkAlpha - lo.dark) / (hi.dark - lo.dark)
        return lo.light + t * (hi.light - lo.light)
    }

    /// Text at a derived strength. Every recessed label goes through this
    /// rather than `ink.opacity(_:)` directly, or light mode quietly loses it.
    public func text(_ darkAlpha: Double) -> Color {
        ink.opacity(textAlpha(darkAlpha))
    }

    /// Weight for text, given the weight tuned for dark.
    public func weight(_ weight: Font.Weight) -> Font.Weight {
        guard !isDark else { return weight }
        switch weight {
        case .bold: return .semibold
        case .semibold: return .medium
        case .medium: return .regular
        default: return weight
        }
    }

    // MARK: - Surfaces

    /// Content ground. The menu-bar panels use the same colour, so a panel and
    /// a window are visibly the same material.
    public var canvas: Color {
        isDark ? .black : .white
    }

    /// Title bars, sidebars, toolbars — one step up from the canvas.
    public var chrome: Color {
        isDark
            ? Color(red: 0x0D / 255, green: 0x0D / 255, blue: 0x0F / 255)
            : Color(red: 0xFB / 255, green: 0xFA / 255, blue: 0xF9 / 255)
    }

    /// Dialogs, menus, cards.
    public var raised: Color {
        isDark ? Color(red: 0x19 / 255, green: 0x19 / 255, blue: 0x1D / 255) : .white
    }

    /// Text fields, code blocks — anything that reads as cut into the surface.
    public var sunken: Color {
        isDark
            ? Color(red: 0x08 / 255, green: 0x08 / 255, blue: 0x0A / 255)
            : Color(red: 0xF3 / 255, green: 0xF1 / 255, blue: 0xEE / 255)
    }

    /// Behind a modal.
    public var scrim: Color {
        isDark ? Color.black.opacity(0.6) : ink.opacity(0.24)
    }

    /// Kept as the name the panels already use for their ground.
    public var panelBackground: Color { canvas }

    /// Matching scheme for the few system-styled controls left.
    public var colorScheme: ColorScheme { scheme }

    // MARK: - Lines and shadow

    /// Dividers inside a surface. Always drawn as a 1pt `Rectangle`, never
    /// `Divider()`, which carries its own inset and colour.
    public var hairline: Color { ink.opacity(isDark ? 0.12 : 0.08) }

    public var cardBorder: Color { ink.opacity(isDark ? 0.14 : 0.05) }

    /// A window's outline — a very light grey in BOTH modes: on the black panel
    /// it reads as a fine light line, on the white one as a soft edge. Solid, so
    /// it never disappears into the ground the way ink-opacity borders did.
    public var windowBorder: Color { Color(white: 0.85) }

    /// Drop shadow for a floating card, drawn in SwiftUI. The system window
    /// shadow is disabled on these: WindowServer adds a hard ~1px rim at the
    /// window edge, which reads as a black border around a light card.
    public var cardShadow: Color {
        Color.black.opacity(isDark ? 0.38 : 0.18)
    }

    // MARK: - Semantic colour

    /// The system palette is tuned for dark grounds — on white it reads
    /// fluorescent — so light mode swaps in Notion-toned equivalents.
    public var positive: Color {
        isDark ? .green : Color(red: 0x44 / 255, green: 0x83 / 255, blue: 0x61 / 255)
    }
    public var caution: Color {
        isDark ? .orange : Color(red: 0xCB / 255, green: 0x7B / 255, blue: 0x37 / 255)
    }
    public var negative: Color {
        isDark ? .red : Color(red: 0xC4 / 255, green: 0x55 / 255, blue: 0x4D / 255)
    }

    /// Hover for a SOLID semantic button: the same hue darkened, never the same
    /// hue faded. Red is high-chroma; fading it toward the ground drops the
    /// chroma and it reads as dusty brick rather than as danger. Solid buttons
    /// always hover darker.
    public var negativeDeep: Color {
        isDark
            ? Color(red: 0xE0 / 255, green: 0x34 / 255, blue: 0x2A / 255)
            : Color(red: 0xAC / 255, green: 0x4B / 255, blue: 0x44 / 255)
    }

    /// Attention without alarm — thinking, or a decision waiting on the user.
    /// Far enough from the running green to tell two 6pt dots apart.
    public var thinkingPurple: Color { aurora[1] }

    /// Focus and selection. The series has no accent colour; emphasis is
    /// borrowed from the aurora.
    public var focus: Color { thinkingPurple }

    /// The quietest mark a surface can carry — idle, reviewed, gone stale. The
    /// dark value on white is 1.60:1, which is absent rather than quiet, so
    /// light mode gets its own (2.81:1).
    public var idleDot: Color { ink.opacity(isDark ? 0.25 : 0.5) }

    // MARK: - Aurora

    /// The series' signature asset: blue → purple → pink → gold.
    ///
    /// Gold sits at the trailing end ONLY. Next to pink it blends through warm
    /// coral; next to blue or purple it would grey out (near-complements).
    /// Amber-gold rather than pure yellow, so it survives a white card.
    public var aurora: [Color] {
        isDark
            ? [
                Color(red: 0x39 / 255, green: 0x87 / 255, blue: 0xE5 / 255),
                Color(red: 0x90 / 255, green: 0x85 / 255, blue: 0xE9 / 255),
                Color(red: 0xF2 / 255, green: 0x6C / 255, blue: 0xB8 / 255),
                Color(red: 0xF2 / 255, green: 0xC1 / 255, blue: 0x4E / 255),
            ]
            : [
                Color(red: 0x33 / 255, green: 0x7E / 255, blue: 0xA9 / 255),
                Color(red: 0x90 / 255, green: 0x65 / 255, blue: 0xB0 / 255),
                Color(red: 0xB0 / 255, green: 0x55 / 255, blue: 0x85 / 255),
                Color(red: 0xCB / 255, green: 0x91 / 255, blue: 0x2F / 255),
            ]
    }

    public var auroraGradient: LinearGradient {
        LinearGradient(colors: aurora, startPoint: .leading, endPoint: .trailing)
    }

    // MARK: - Selection

    /// Selected chip in a pick-one row. Dark mode brightens the fill; light
    /// mode inverts to a charcoal chip, segmented-control style, so selection
    /// never competes with the idle greys.
    public var selectedChipFill: Color { isDark ? ink.opacity(0.22) : ink }
    /// White in both modes: dark ink at full strength IS white, and the
    /// inverted light chip is charcoal, so its label is white too.
    public var selectedChipText: Color { .white }

    // MARK: - Categorical data

    /// Palette for data displays. Deliberately NOT reused for status: green,
    /// orange and purple already mean state, and a second meaning for the same
    /// hue makes a data row read as a status.
    public var dataBlue: Color { aurora[0] }
    public var dataPurple: Color { aurora[1] }
    public var dataGold: Color {
        isDark ? Color(red: 0xC9 / 255, green: 0x85 / 255, blue: 0x00 / 255) : aurora[3]
    }
    public var dataGreen: Color {
        isDark ? Color(red: 0x19 / 255, green: 0x9E / 255, blue: 0x70 / 255) : positive
    }
    public var dataTeal: Color {
        isDark ? .mint : Color(red: 0x3A / 255, green: 0x8E / 255, blue: 0x86 / 255)
    }
    public var dataGray: Color {
        isDark ? .gray : Color(red: 0x78 / 255, green: 0x77 / 255, blue: 0x74 / 255)
    }
}
