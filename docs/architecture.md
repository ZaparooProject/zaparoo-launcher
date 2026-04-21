# Architecture

## Module graph

```
src/app/
  zaparoo-launcher (executable)
    ├── src/core/
    │     zaparoo_core (static lib)
    │     Qt6::Core only — no Quick dependency, unit-testable
    │
    └── src/ui/app/  [Zaparoo.App QML module]
          Main.qml
          ├── src/ui/components/  [Zaparoo.Ui QML module]
          │     Carousel.qml, Starfield.qml, FpsCounter.qml,
          │     MenuBar.qml, SelectionDots.qml, CrtOverlay.qml
          │
          └── src/ui/theme/  [Zaparoo.Theme QML module]
                Sizing.qml  — pctH/pctW/fontSize singletons
                Theme.qml   — colors and font-family constants
```

## QML module URIs

| Target | URI | Load path |
|---|---|---|
| zaparoo_ui_app | `Zaparoo.App` | `qrc:/qt/qml/Zaparoo/App/` |
| zaparoo_ui_components | `Zaparoo.Ui` | `qrc:/qt/qml/Zaparoo/Ui/` |
| zaparoo_ui_theme | `Zaparoo.Theme` | `qrc:/qt/qml/Zaparoo/Theme/` |

`engine.loadFromModule("Zaparoo.App", "Main")` is the sole entry point.
No `qrc:/` strings anywhere else.

## Key constraints

- **Software rendering only.** MiSTer has no GPU. Never use shaders,
  `LinearGradient`, `RadialGradient`, `DropShadow`, `Glow`, `OpacityMask`,
  `MultiEffect`, or `Qt5Compat.GraphicalEffects`. Stick to `Rectangle`,
  `Image`, `Text`, `Repeater`, `NumberAnimation`, `ColorAnimation`.

- **Resolution-agnostic layout.** Runs from 240p (CRT) to 1080p. Use
  `Sizing.pctH()`, `Sizing.pctW()`, `Sizing.fontSize()` for all
  dimensions. Never hardcode pixel values.

- **FPS counter is always on.** Check it stays green (≥55 FPS) at 720p+
  and doesn't fall below 30 at 240p when changing visuals.

- **Dynamic Qt on desktop, static Qt on MiSTer.** `BUILD_SHARED_LIBS=ON`
  is the default (LGPL compliance for distribution). The ARM32 Docker
  build passes `-DBUILD_SHARED_LIBS=OFF` via the Qt CMake toolchain.

## LGPL compliance

Qt is used under LGPLv3. The desktop binary links Qt dynamically — end
users may replace the bundled Qt libraries. The MiSTer ARM32 binary is
statically linked; object files are available on request per LGPL §4(d)(1).
License texts live in `src/LICENSES/`.

## Future C++ → QML data flow

When `ZaparooClient` gains a transport implementation, the data flow
will be:

```
ZaparooClient (signals) → QML context property or model
                        ↓
                  Carousel.qml (displays games)
```

`src/core/` classes are all `QObject` subclasses so they can be exposed to
QML via `setContextProperty` or `QML_ELEMENT` registration.
