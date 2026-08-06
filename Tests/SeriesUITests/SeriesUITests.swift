import XCTest
import SwiftUI
@testable import SeriesUI

/// A store that lives in memory, so preference migration can be tested without
/// touching the running user's defaults.
private final class MemoryStore: SeriesPreferenceStore {
    var values: [String: String]

    init(_ values: [String: String] = [:]) {
        self.values = values
    }

    func string(forSeriesKey key: String) -> String? { values[key] }

    func setString(_ value: String?, forSeriesKey key: String) {
        values[key] = value
    }
}

final class TextScaleTests: XCTestCase {
    /// The point of the shared ladder: "Large" is one size across the series.
    func testMultipliersAreTheSeriesLadder() {
        XCTAssertEqual(SeriesTextScale.small.multiplier, 0.875)
        XCTAssertEqual(SeriesTextScale.standard.multiplier, 1.0)
        XCTAssertEqual(SeriesTextScale.large.multiplier, 1.15)
        XCTAssertEqual(SeriesTextScale.extraLarge.multiplier, 1.3)
    }

    func testApplyRoundsToWholePoints() {
        // 16 × 1.15 = 18.4, which would put adjacent roles on disagreeing
        // baselines.
        XCTAssertEqual(SeriesTextScale.large.apply(to: 16), 18)
        XCTAssertEqual(SeriesTextScale.standard.apply(to: 14), 14)
    }

    func testNearestSnapsAContinuousValue() {
        // ClaudeNotch's A−/A+ stored a free multiplier in 0.9…1.4.
        XCTAssertEqual(SeriesTextScale.nearest(to: 0.9), .small)
        XCTAssertEqual(SeriesTextScale.nearest(to: 1.0), .standard)
        XCTAssertEqual(SeriesTextScale.nearest(to: 1.4), .extraLarge)
    }

    func testSteppingClampsAtBothEnds() {
        XCTAssertEqual(SeriesTextScale.small.stepped(by: -1), .small)
        XCTAssertEqual(SeriesTextScale.extraLarge.stepped(by: 1), .extraLarge)
        XCTAssertEqual(SeriesTextScale.standard.stepped(by: 1), .large)
    }

    /// Larger settings must actually produce larger text, all the way up.
    func testTheScaleIsMonotonic() {
        var previous: CGFloat = 0
        for step in SeriesTextScale.allCases {
            let size = step.apply(to: SeriesTextRole.reading.size)
            XCTAssertGreaterThan(size, previous, "\(step.label) should exceed the step below it")
            previous = size
        }
    }

    /// Fractional sizes make adjacent roles' baselines disagree.
    func testEveryRoleLandsOnAWholePointAtEveryStep() {
        for step in SeriesTextScale.allCases {
            for role in SeriesTextRole.allCases {
                let size = step.apply(to: role.size)
                XCTAssertEqual(size, size.rounded(), "\(role) at \(step.label) → \(size)")
            }
        }
    }

    /// The relative hierarchy is what makes the scale readable; no multiplier
    /// may flatten two roles into the same size.
    func testTheHierarchySurvivesEveryStep() {
        for step in SeriesTextScale.allCases {
            let meta = step.apply(to: SeriesTextRole.meta.size)
            let reading = step.apply(to: SeriesTextRole.reading.size)
            let display = step.apply(to: SeriesTextRole.display.size)
            XCTAssertLessThan(meta, reading, step.label)
            XCTAssertLessThan(reading, display, step.label)
        }
    }
}

final class TextRoleTests: XCTestCase {
    /// `micro` is the only rounded role. A paragraph set in it — which is what
    /// Gloss did before `note` existed — reads as a slab of fat round grey.
    func testOnlyMicroIsRounded() {
        for role in SeriesTextRole.allCases {
            XCTAssertEqual(role.design == .rounded, role == .micro, "\(role)")
        }
    }

    /// `note` exists precisely to be `micro`'s size without its shout.
    func testNoteMatchesMicroInSizeButNotInVoice() {
        XCTAssertEqual(SeriesTextRole.note.size, SeriesTextRole.micro.size)
        XCTAssertEqual(SeriesTextRole.note.weight, .regular)
        XCTAssertEqual(SeriesTextRole.micro.weight, .bold)
    }

    /// Layout widths and type must scale together, or turning the size up
    /// truncates every label inside a fixed-width control.
    func testScaledWidthTracksTheSameFactorAsType() {
        for step in SeriesTextScale.allCases {
            XCTAssertEqual(scaledWidth(136, step), 136 * step.multiplier, accuracy: 0.001)
        }
    }
}

@MainActor
final class PreferenceMigrationTests: XCTestCase {
    /// Nobody's existing choice may be reset by the rename to the shared keys.
    func testAdoptsLegacyKeysOnce() {
        let store = MemoryStore(["panelAppearance": "light", "panelTypeface": "serif"])
        let prefs = SeriesPreferences(
            store: store,
            legacyKeys: .init(appearance: "panelAppearance", typeface: "panelTypeface")
        )
        XCTAssertEqual(prefs.appearance, .light)
        XCTAssertEqual(prefs.typeface, .serif)
    }

    /// Gloss's third typeface was Rounded and the series has no such option.
    /// It must land somewhere the enum can represent, not fall back to a
    /// default that silently ignores an explicit choice elsewhere.
    func testRoundedTypefaceMigratesToDefault() {
        let store = MemoryStore(["typeface": "rounded"])
        let prefs = SeriesPreferences(store: store)
        XCTAssertEqual(prefs.typeface, .standard)
    }

    /// Gloss stored the multiplier itself rather than a named step.
    func testLegacyMultiplierSnapsToAStep() {
        let store = MemoryStore(["textScale": "1.3"])
        let prefs = SeriesPreferences(store: store, legacyKeys: .init(textScaleMultiplier: "textScale"))
        XCTAssertEqual(prefs.textScale, .extraLarge)
    }

    /// A value already written in the new schema wins over the legacy key, so
    /// migration does not keep overwriting later choices.
    func testNewKeyWinsOverLegacy() {
        let store = MemoryStore(["appearance": "dark", "panelAppearance": "light"])
        let prefs = SeriesPreferences(
            store: store,
            legacyKeys: .init(appearance: "panelAppearance")
        )
        XCTAssertEqual(prefs.appearance, .dark)
    }

    /// Each app keeps its own default — ClaudeNotch wraps a black notch.
    func testDefaultIsTheHostAppsCall() {
        XCTAssertEqual(SeriesPreferences(store: MemoryStore()).appearance, .system)
        XCTAssertEqual(
            SeriesPreferences(store: MemoryStore(), defaultAppearance: .dark).appearance,
            .dark
        )
    }

    func testWritingPersistsTheRawValue() {
        let store = MemoryStore()
        let prefs = SeriesPreferences(store: store)
        prefs.textScale = .large
        XCTAssertEqual(store.values[SeriesPreferenceKey.textScale], "l")
    }
}

final class ThemeTests: XCTestCase {
    private let dark = SeriesTheme(appearance: .dark, scheme: .dark)
    private let light = SeriesTheme(appearance: .light, scheme: .light)

    /// The three perceptual corrections do NOT all point the same way. This is
    /// the property that keeps getting re-derived by hand in each app.
    func testFillGetsQuieterOnLightAndTextGetsStronger() {
        XCTAssertEqual(dark.textAlpha(0.45), 0.45)
        XCTAssertGreaterThan(light.textAlpha(0.45), 0.45, "recessed text must gain contrast on white")
        XCTAssertEqual(light.textAlpha(1), 1, "full-strength text passes through")
    }

    func testTextAlphaRampIsMonotonic() {
        var previous = -1.0
        for step in stride(from: 0.0, through: 1.0, by: 0.05) {
            let value = light.textAlpha(step)
            XCTAssertGreaterThanOrEqual(value, previous, "ramp inverted at \(step)")
            previous = value
        }
    }

    func testWeightStepsDownOnLightOnly() {
        XCTAssertEqual(dark.weight(.bold), .bold)
        XCTAssertEqual(light.weight(.bold), .semibold)
        XCTAssertEqual(light.weight(.medium), .regular)
    }

    /// Gold last, so it blends through warm coral next to pink instead of
    /// greying out beside blue.
    func testAuroraHasFourStopsInBothSchemes() {
        XCTAssertEqual(dark.aurora.count, 4)
        XCTAssertEqual(light.aurora.count, 4)
    }

    func testSystemAppearanceResolvesAgainstTheSystem() {
        XCTAssertEqual(SeriesAppearance.system.resolve(system: .light), .light)
        XCTAssertEqual(SeriesAppearance.system.resolve(system: .dark), .dark)
        XCTAssertEqual(SeriesAppearance.dark.resolve(system: .light), .dark)
    }

    /// nil is what an untouched `NSWindow.appearance` already means.
    func testSystemAppearanceHasNoNSAppearanceOverride() {
        XCTAssertNil(SeriesAppearance.system.nsAppearance)
        XCTAssertNotNil(SeriesAppearance.dark.nsAppearance)
    }
}

final class ShadowTests: XCTestCase {
    /// A borderless window paints its own shadow, so the room it needs has to
    /// be reserved or the Gaussian is sliced into a grey rectangle.
    func testMarginCoversTheVisibleTail() {
        XCTAssertEqual(SeriesCardShadow.panel.margin, (16 * 2.2 + 6).rounded(.up))
        XCTAssertGreaterThan(SeriesCardShadow.dialog.margin, SeriesCardShadow.notice.margin)
    }
}
