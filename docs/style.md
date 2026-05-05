# UI Style

Standard tokens and shape conventions for the Zaparoo Launcher UI. Anything
not covered here defers to `Theme.qml` (colors, fonts) and `Sizing.qml`
(percentage helpers).

## Corner radius

One token, one value: `Sizing.cornerRadius` (`pctH(3.5)`). Every rounded-square
surface in the app uses it.

| Surface | Code |
|---|---|
| Tile card body | `radius: Sizing.cornerRadius` |
| Tile focus ring | `radius: Sizing.cornerRadius - root._outlineGap` |
| Settings row surface | `radius: Sizing.cornerRadius` |

The focus ring is computed from the token (not hardcoded to a smaller value)
so the ring stays concentric with the card if the token changes.

When adding a new rounded-square surface, use the token. Don't introduce a
second radius value — the visual language is one shape, one radius.

## Pills

Toggle controls (`SettingsField.qml` track + thumb) use `height/2` and
`width/2`. They're pills, not rounded squares — a deliberately different
shape for binary on/off controls (same convention as iOS toggles). They do
not use `Sizing.cornerRadius` and shouldn't be made to.

## Modal chrome

Every modal panel and the context menu use `Sizing.cornerRadius`. They join
the rounded-square family with tile cards, settings rows, and focus rings —
one shape, one radius across the app. `Modal.qml` is the canonical shell;
the first-run, commercial-notice, and log-upload modals all wrap it via
`kind: "shell"` rather than hand-rolling their own panel.

| Surface | Token |
|---|---|
| Background | `Theme.bgPanel` |
| Border | `2px`, `Theme.textPrimary` |
| Corner radius | `Sizing.cornerRadius` |
| Scrim | `#cc000000` |
| Column top margin | `Sizing.pctH(6)` |
| Column side margins | `Sizing.pctW(6)` |
| Column spacing | `Sizing.pctH(3)` |
| Title | `Sizing.fontSize(3.2)`, `Theme.textPrimary` |
| Body | `Sizing.fontSize(2.5)`, `Theme.textPrimary` |
| Button slot height | `Sizing.pctH(7)` |
| Button width | `Sizing.pctW(28)` |
| Button background | `Theme.bgBar` |
| Button border | `1px`, `Theme.borderMid` (focus: `2px`, `Theme.accent`) |
| Button radius | `Sizing.cornerRadius` |
| Button text | `Sizing.fontSize(2.5)`, `Theme.textPrimary` |

When adding a new modal, prefer extending `Modal.qml` (a new `kind`, or the
shell content slot) over a bespoke panel — the chrome should never need to
be hand-rolled twice.

## Tile aspect

| Surface | Aspect |
|---|---|
| Hub categories row | 1:1 (square, `cellHeight = cellWidth`) |
| Hub action row | 1:1 (mirrors categories row metrics) |
| Systems grid | Aspect driven by `PagedGrid` available height |
| Games grid | Aspect driven by `PagedGrid` available height |

The hub uses square tiles because the icons are simple silhouettes that read
fine at 1:1. Cover-art surfaces (systems, games) get taller cells from
`PagedGrid` because logos and box-art benefit from vertical room.

## True squircles aren't achievable

A super-ellipse curve needs `Shape` + `PathSvg` or shaders. The MiSTer build
runs Qt Quick's software adaptation — no GPU, no shaders, no `Shape`,
no `MultiEffect`. See `qml-gotchas.md`. The large `Rectangle.radius` value is
a circular-arc approximation; close enough at this scale that the lack of
super-ellipse curvature is invisible at typical viewing distances.

## Consistency rule

If a new surface has rounded corners, it picks `Sizing.cornerRadius` or it
joins the pill family. There is no third option. Inconsistent radii were the
problem this token was introduced to solve.
