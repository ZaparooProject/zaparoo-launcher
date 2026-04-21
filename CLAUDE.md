# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

**Desktop build:**
```bash
cmake -S . -B build && cmake --build build
./build/bin/zaparoo-launcher
```

**ARM32 / MiSTer build** (requires Docker, cross-compiles natively without emulation):
```bash
./scripts/build-arm32.sh       # first run builds toolchain (~45 min); subsequent runs < 1 min
# Output: output/zaparoo-launcher
```

**Deploy desktop build with bundled Qt libs** (LGPL compliance):
```bash
./packaging/deploy-desktop.sh
# Output: deploy/zaparoo-launcher/ with binary, Qt .so files, and run.sh wrapper
```

**Run on framebuffer** (MiSTer or any Linux without X/Wayland):
```bash
QT_QPA_PLATFORM=linuxfb QT_QUICK_BACKEND=software ./build/bin/zaparoo-launcher
```

**Run tests:**
```bash
ctest --test-dir build --output-on-failure
```

**Run all linters (clang-format check + clang-tidy + qmllint):**
```bash
cmake --build build --target lint
```

**Run individual linters:**
```bash
cmake --build build --target format-check   # clang-format dry-run on all C++
cmake --build build --target tidy           # clang-tidy static analysis
cmake --build build --target all_qmllint    # QML linting only
```

**Auto-format C++ files:**
```bash
clang-format -i src/**/*.{cpp,h} tests/**/*.cpp
```

## Architecture

See `docs/architecture.md` for the full module diagram. Summary:

- `src/app/main.cpp` — thin entry point (~40 lines): sets app metadata, installs logger, loads fonts, calls `engine.loadFromModule("Zaparoo.App", "Main")`.
- `src/core/` — pure C++ library (`zaparoo_core`): `Config`, `Logger`, `PlatformPaths`, `ZaparooClient`. No Qt Quick dependency; unit-testable without a window.
- `src/ui/theme/` — `Zaparoo.Theme` QML module: `Theme.qml` (colors, font families) and `Sizing.qml` (resolution helpers). Singletons.
- `src/ui/components/` — `Zaparoo.Ui` QML module: `Carousel`, `Starfield`, `FpsCounter`, `MenuBar`, `SelectionDots`, `CrtOverlay`.
- `src/ui/app/` — `Zaparoo.App` QML module: `Main.qml` — the root window that wires the components.

Resources (fonts, images) are embedded in the `Zaparoo.App` module and accessed as `qrc:/qt/qml/Zaparoo/App/resources/...`.

## Hard Constraints

**Software rendering only.** MiSTer has no GPU. Never use: shaders, `LinearGradient`,
`RadialGradient`, `DropShadow`, `Glow`, `OpacityMask`, `MultiEffect`,
`Qt5Compat.GraphicalEffects`. Stick to `Rectangle`, `Image`, `Text`, `Repeater`,
`NumberAnimation`, `ColorAnimation`. The "Basic" `QQuickStyle` is also mandatory for
this reason.

**Resolution-agnostic layout.** The UI runs from 240p (CRT) to 1080p. Use
`Sizing.pctH()`, `Sizing.pctW()`, `Sizing.fontSize()` (from `Zaparoo.Theme`) for all
sizing. Scale element counts with resolution (e.g. `Sizing.visibleCovers`, the starfield
`Repeater` model). Never use hardcoded pixel sizes in new code.

**Dynamic Qt linking for desktop.** `BUILD_SHARED_LIBS ON` is the default and required for
LGPL compliance. Don't switch to static Qt for desktop builds. (The ARM32 Docker build uses
static Qt by necessity — that's handled via `qt-cmake` inside `Dockerfile.arm32`.)

**Watch the FPS counter.** `src/ui/components/FpsCounter.qml` renders a live FPS readout
(green ≥55, yellow ≥30, red <30). When changing visuals, check it stays green at 720p+ and
doesn't degrade at 240p.

**Qt minimum version is 6.7.** No Qt5 compatibility code. No `#if QT_VERSION` guards.

## QML Module URIs

| Module | URI | What's in it |
|---|---|---|
| `src/ui/theme/` | `Zaparoo.Theme` | `Theme`, `Sizing` singletons |
| `src/ui/components/` | `Zaparoo.Ui` | Reusable components |
| `src/ui/app/` | `Zaparoo.App` | `Main.qml` + embedded assets |

Import them as `import Zaparoo.Theme`, `import Zaparoo.Ui`, etc.

## MiSTer Deployment

The binary is deployed to `/media/fat/Scripts/zaparoo-launcher` on the device. The
`packaging/mister/Zaparoo_Launcher_<res>p.sh` scripts are MiSTer-side launchers that use
`vmode` to set the framebuffer resolution, then run the binary with `QT_QPA_PLATFORM=linuxfb`.
Update all resolution scripts together if the deploy path or environment variables change.

The ARM32 Docker build uses gcc-arm-10.2-2020.11 targeting glibc 2.31, with Qt 6.7.2 built
from source inside `Dockerfile.toolchain`. The prebuilt base image is tagged locally as
`zaparoo/qt6-arm32-mister:6.7.2`.

## Code Quality Rules

**Always run `cmake --build build --target lint` after editing any C++ or QML file.**
Zero warnings is the required bar — never leave a warning unresolved.

**Always run `ctest --test-dir build --output-on-failure` after any change that could affect
runtime behaviour.**

When adding or modifying QML:
- Run `cmake --build build --target all_qmllint` and fix every warning before moving on.
- Typed properties (`list<string>`, `list<url>`, `int`, `real`) beat `var` — qmllint can't
  reason about `QVariant`.
- Any QML file with a `Repeater` delegate needs `pragma ComponentBehavior: Bound` and
  `required property int index` (plus `required property string modelData` when iterating
  a list model).

When adding or modifying C++:
- Run `cmake --build build --target format-check`. If it fails, run
  `clang-format -i <files>` to fix.
- Run `cmake --build build --target tidy` and fix any warnings in `src/` files. Warnings
  in Qt-generated or third-party headers can be ignored.

## Tooling Config

- `.clang-format` — C++ style (LLVM-based, 100 col limit)
- `.clang-tidy` — static analysis (bugprone-*, modernize-*, performance-*, readability-*)
- `.qmllint.ini` — QML linting categories
- `.qmlformat.ini` — QML formatter settings
- `.cmake-format.yaml` — CMake formatting
- `.pre-commit-config.yaml` — git hooks for all of the above
- `.editorconfig` — editor whitespace baseline

`compile_commands.json` is always generated in `build/` (no extra cmake flag needed) and
is used by both clang-tidy and clangd for IDE integration.
