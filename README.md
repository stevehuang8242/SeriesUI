# SeriesUI

The design language shared by **Gloss**, **Minute** and **ClaudeNotch**.

The three apps had independently arrived at most of the same palette — the
lineage runs ClaudeNotch → Gloss → Minute — but each had kept its own copy, so
improvements stopped travelling. ClaudeNotch worked out a light-mode contrast
compensation the other two never got; Minute added a `note` text role after
discovering that setting a paragraph in `micro` produces a slab of fat round
grey, and Gloss still had that paragraph. This package is the one copy.

## What is shared, and what is not

**Shared: the vocabulary.** Colours, the type scale, control shapes, the two
easings, and the *schema* of the three user preferences.

**Not shared: the values.** Each app stores its own appearance, typeface and
text size, and picks its own defaults. The apps have genuinely different
physical constraints — ClaudeNotch's bar is hardware-sized and wraps a black
notch, Gloss's card sits beside the text you are reading, Minute's window is
where you spend an hour — so someone who wants Large in a reading tool does not
thereby want Large in an ambient gauge. What the shared schema buys is that
"Large" is *one size* across the series, and that the third typeface is never
Rounded in one app and Mono in another.

Storage is per-app for free: the apps have distinct bundle identifiers, so the
same key in each one's `UserDefaults.standard` is already isolated. There is no
shared suite and no cross-app sync.

```swift
// Each app, once, at startup:
let preferences = SeriesPreferences(
    store: UserDefaults.standard,
    defaultAppearance: .system,          // ClaudeNotch passes .dark
    legacyKeys: .init(appearance: "panelAppearance", …)  // read once, so nobody's choice resets
)

// Root of every window and panel:
MyView().seriesStyle(preferences)
```

`seriesStyle` puts the theme, the scale and the typeface in the environment, so
a change restyles everything live — including the settings screen that made it,
which is what lets a settings screen be its own preview. Gloss previously
resolved its theme once at window-open time into a stored property, and
switching to Light did nothing until the window was closed and reopened.

## Contents

| | |
|---|---|
| `SeriesTheme` | ink, fills, four surfaces, semantic colour, aurora |
| `SeriesTextRole` / `scaledFont` | `micro · note · meta · header · body · reading · display` |
| `SeriesAppearance` / `SeriesTypeface` / `SeriesTextScale` | the preference schema |
| `SeriesRadius` / `SeriesControl` / `SeriesMotion` / `SeriesCardShadow` | shape, size, timing |
| `Card` / `SettingRow` | the grammar of a settings screen |
| `SegmentedRail` / `SeriesDropdown` / `InkField` / `InkSwitch` / `InkCheckbox` / `UnderlineTabs` | inputs |
| `InkButton` / `IconButton` / `PillButton` | actions |
| `SeriesOverlayRoot` / `SeriesMenuRequest` / `SeriesDialogRequest` | menus and dialogs, drawn in the window |
| `SeriesListRow` / `SeriesTextEditor` / `SeriesEmptyState` | lists and long-form editing |
| `StatusDot` / `ShimmerText` / `MarqueeText` / `InlineNote` / `Hairline` | indicators |

Wrap a window's content in `SeriesOverlayRoot` to give it menus and dialogs.
`SeriesDropdown` needs one — it draws its popup there rather than opening a
system menu, and without a host it renders dimmed rather than looking live and
ignoring clicks.

### Destructive actions come in two weights

`.danger` is solid negative and belongs to the moment of commitment — the
confirm button inside a destructive dialog. The affordance that merely OPENS
that dialog takes `.dangerGhost`: negative label, transparent ground. A solid
red block sitting permanently in a toolbar shouts before anything has been
decided, and leaves nothing louder for the actual commitment.

### Three rules worth knowing before adding anything

**All text is one ink at varying strength.** There is no second text colour.
Recessed labels go through `theme.text(_:)`, never `ink.opacity(_:)` — the
former applies the light-mode contrast ramp, the latter loses the label on
white.

**The perceptual corrections do not all point the same way.** `fill(_:)` halves
its alpha on light (nothing glows on a light ground); `textAlpha(_:)` raises it
(charcoal-on-white loses contrast fast where white-on-black is thickened by
halation); `weight(_:)` steps down one notch. Getting one of these backwards is
the usual cause of a light mode that looks "washed out" or "too heavy".

**Nothing repeats forever.** A persistent `repeatForever` animation leaks into
sibling layout on these panels. Live indicators are clock-driven through
`TimelineView` — see `StatusDot` and `ShimmerText`.

## Open questions

**Icons.** Components take SF Symbol names. Minute draws its own 37 glyphs, on
the grounds that SF Symbols are the system's handwriting and are recognised
instantly as such — a fair argument, and the largest remaining visual
difference between the apps. Every component renders its icon in exactly one
place, so swapping the layer is a change inside this package.

**The prose.** Minute's `docs/design-language.md` is the fullest write-up of
this language and still lives in Minute's repository, which makes the newest
app the de facto owner of the series. It belongs here, with a section per app
for the deliberate deviations.

## Consumers

Currently a path dependency (`.package(path: "../SeriesUI")`), so a fresh clone
of a consuming app alone will not build. Publish this and switch them to a URL
before any of them ships to other people.

- **Gloss** — fully migrated: every window and panel
- **Minute** — not yet migrated; has the richest local implementation (`App/DesignSystem.swift`, `App/Controls.swift`, `App/Overlay.swift` — the last of which this package's overlay layer was ported from)
- **ClaudeNotch** — not yet migrated; source of `textAlpha` and the data palette

### A build note

Gloss consumes this by path, and SwiftPM's incremental build does not always
notice a NEW file in a path dependency — the consumer keeps compiling against
the previously emitted module and reports `cannot find X in scope` for something
that plainly exists. `swift package clean` in the consumer fixes it. Worth
knowing before spending twenty minutes on a spelling.
