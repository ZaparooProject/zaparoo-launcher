# Zaparoo Launcher — Designer Guide

This directory lets a UX designer open the launcher UI visually in
**Qt Design Studio**. Nothing under `design/` is compiled into the
launcher binary — it's a designer-only sidecar.

## Setup (one-time)

1. **Install Qt Design Studio.** Free, GPLv3. Fastest path: install
   via the Qt online installer (<https://www.qt.io/download-qt-installer>)
   and tick *Qt Design Studio*. Linux package managers sometimes ship
   it as `qt-design-studio`.
2. **Build the launcher once** from the repo root so the generated
   QML modules exist:

   ```sh
   just build
   ```

   This populates `build/qml/Zaparoo/{App,Ui,Theme}/` with the real
   QML files. Design Studio reads them directly from there. The
   `Zaparoo.Browse` module — backed by Rust — is replaced by mocks
   under `design/mocks/`.
3. **Open the project** in Qt Design Studio:

   ```text
   design/launcher.qmlproject
   ```

   The 2D view should render `MainPreview.qml` at 1280×720 with a
   populated categories/systems carousel drawn from the mock
   singletons. If carousels look empty, double-check step 2.

## Editable vs. off-limits files

| Path                            | Touch?                                                     |
| ------------------------------- | ---------------------------------------------------------- |
| `src/ui/theme/Theme.qml`        | Yes — colour & font constants.                             |
| `src/ui/theme/Sizing.qml`       | Logic tweaks only; ask first.                              |
| `src/ui/components/*.qml`       | Yes — delegates, carousel, FPS counter.                    |
| `src/ui/app/MainLayout.qml`     | Yes — screen layout, backgrounds, anchors.                 |
| `src/ui/app/Main.qml`           | **No.** Engineer-owned state machine. Flag changes.        |
| `design/mocks/**`               | No. Design-time stubs; edit only if engineering asks.      |
| `design/previews/MainPreview.qml` | Change preview canvas here; don't add real UI.           |

## Hard constraints — software rendering only

The launcher runs on MiSTer FPGA, which has **no GPU**. Anything that
needs a shader or effect crashes or renders as a grey box. Stick to
this palette:

Allowed:
`Rectangle`, `Image`, `Text`, `Repeater`, `Item`, `NumberAnimation`,
`ColorAnimation`, `Behavior`.

**Banned** — do not drag these from the Design Studio Components panel:

- `LinearGradient`, `RadialGradient`, `ConicalGradient`
- `DropShadow`, `Glow`, `InnerShadow`
- `OpacityMask`, `ColorOverlay`, `FastBlur`, `GaussianBlur`
- `MultiEffect`, anything from `Qt5Compat.GraphicalEffects`
- Qt Quick **Studio Components**: `Pie`, `Arc`, `Triangle`,
  `Regular Polygon`, `Star`, `Svg Path Item`
- Any shader‑backed effect

If an effect is essential, talk to an engineer first — there's often a
flat `Rectangle` / `Image` combo that gets you 80% of the way.

## Sizing — never hardcode pixels or element counts

The launcher scales from 240p (CRT) to 1080p. Use the helpers exposed
as the `Sizing` singleton (import `Zaparoo.Theme`) — never hardcode
pixel values or element counts:

- `Sizing.pctH(n)` — `n` percent of screen height.
- `Sizing.pctW(n)` — `n` percent of screen width.
- `Sizing.fontSize(n)` — percent-of-height font size, floored at 8 px.
- `Sizing.visibleCovers` — element count for carousels and similar
  repeaters; drops at very low resolutions to avoid crowding.

At the designer canvas of 1280×720, `Sizing.pctH(10)` previews as 72 px.

## Handing work back

1. Commit your changes to a branch (`design/<feature>`).
2. Open a PR, or hand the `.qml` diffs to an engineer.
3. Do not edit `CMakeLists.txt`, `.cpp`, `.rs`, or anything under
   `rust/` — those are engineering concerns.

## If the Design tab stays greyed out in Qt *Creator*

That's expected. Qt Creator 6+ ships its QML visual designer disabled
because it was superseded by Qt Design Studio. Open the project in
**Design Studio**, not Creator.

## Troubleshooting

- **Red error banners on `Zaparoo.Browse.*`** — `build/qml/` is
  missing or stale. Rerun `just build`.
- **Red error banners on `Zaparoo.Ui` / `Zaparoo.Theme`** — same
  cause; `just build` populates those too.
- **Carousel is empty** — the mock ListModels seed four entries; if
  all carousels are empty, `mocks/` isn't being resolved. Check that
  `importPaths` in `launcher.qmlproject` still lists `mocks` first.
- **"Cannot find type XYZ"** — probably a Qt Quick Studio Component.
  Don't use them; see the banned list above.
