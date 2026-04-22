# Architecture

## Module graph

```
src/app/
  launcher (executable)
    ├── MiSterRuntime.cpp/.h
    │     Pre-Qt setup: sets linuxfb env vars, calls vmode, starts zaparoo.sh.
    │     Compiled only on ZAPAROO_MISTER (ARM32 static Qt); stubs on desktop.
    │
    ├── src/core/
    │     zaparoo_core (static lib)
    │     Qt6::Core, Qt6::Qml, Qt6::WebSockets
    │     Exposes Zaparoo.Browse QML module (BrowseModel singleton)
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
| zaparoo_core (plugin) | `Zaparoo.Browse` | `qrc:/qt/qml/Zaparoo/Browse/` |
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

## C++ → QML data flow

```
ZaparooClient (WebSocket JSON-RPC 2.0)
    ↓  mediaBrowse() / run() callbacks
BrowseModel (QAbstractListModel + QML_SINGLETON, Zaparoo.Browse)
    ↓  model roles + Q_INVOKABLE methods
Carousel.qml / Main.qml
```

`BrowseModel` is a `QML_SINGLETON` registered via `QML_ELEMENT`. The
singleton instance must be set via `BrowseModel::setInstance()` before the
QML engine is created. See `src/app/main.cpp` for the wiring.
