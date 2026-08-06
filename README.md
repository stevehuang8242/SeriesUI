# SeriesUI

The design language shared by **Gloss**, **Minute** and **Brim**.

The three apps had independently arrived at most of the same palette — the
lineage runs Brim → Gloss → Minute — but each had kept its own copy, so
improvements stopped travelling. Brim worked out a light-mode contrast
compensation the other two never got; Minute added a `note` text role after
discovering that setting a paragraph in `micro` produces a slab of fat round
grey, and Gloss still had that paragraph. This package is the one copy.

## What is shared, and what is not

**Shared: the vocabulary.** Colours, the text ROLES, control shapes, the two
easings, and the *schema* of the three user preferences.

**Not shared: the values.** Each app stores its own appearance, typeface and
text size, picks its own defaults, and brings its own point sizes for the
shared roles (`SeriesTypeScale`). The apps have genuinely different
physical constraints — Brim's bar is hardware-sized and wraps a black
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
    defaultAppearance: .system,          // Brim passes .dark
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
| `SeriesTextRole` / `SeriesTypeScale` / `scaledFont` | `micro · note · meta · header · body · value · reading · display`, sized per app |
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

Public and resolved over HTTPS, while the three apps themselves are private.
It holds no secrets and no product logic, so being public costs nothing — and
it is what lets a clone, a new machine or a CI runner resolve it with no key
and no ssh-config entry. A private dependency behind a personal host alias
built on exactly one Mac, which is not a dependency, it is a local file.

Each pins `branch: "main"`. Tag this and move them to `.upToNextMinor(from:)`
when that stops being comfortable: "whatever main says today" is fine while one
person owns all four, and becomes a way for a change made for one app to arrive
unannounced in another.

All three, each adopting the layers that fit it:

- **Gloss** — fully migrated. Every window and panel, including the controls,
  the menus and the dialogs. Type scale `.reading`.
- **Brim** — palette, roles, preferences and the measuring helpers. Type scale
  `.compact`: its panel hangs off a hardware notch. Keeps its own panel
  components. This is where `textAlpha` and the data palette came from.
- **Minute** — palette, roles and preferences, reached through its own `T`
  façade so its fifteen view files did not have to change. Type scale
  `.reading`. Keeps its own control library and its 37 hand-drawn glyphs,
  which is the reason the icon question below is still open. Its
  `OverlayHost` is where this package's overlay layer came from, and both now
  measure against the same named coordinate space.

The pattern is worth stating: an app takes the layers where agreeing helps —
colour, roles, preference schema — and keeps the ones where its surface is
genuinely different. Nothing here requires taking all of it.

### A build note

SwiftPM's incremental build does not always notice a NEW file here — a consumer
keeps compiling against the previously emitted module and reports `cannot find X
in scope` for something that plainly exists. `swift package clean` in the
consumer fixes it. Worth knowing before spending twenty minutes on a spelling.
