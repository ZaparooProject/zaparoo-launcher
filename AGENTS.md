# Zaparoo Launcher — Agent Instructions

Zaparoo Launcher is a Qt/QML game launcher for Zaparoo Core. It targets two
environments: MiSTer FPGA (ARM32, Linux framebuffer, no GPU, software
rendering) and desktop Linux (x86_64, windowed). The hard rendering
constraint shapes every visual decision. See @docs/architecture.md for the
module graph and @docs/building.md for the full build matrix.

## Hard Constraints

**Software rendering only.** MiSTer has no GPU. Never use: shaders,
`LinearGradient`, `RadialGradient`, `DropShadow`, `Glow`, `OpacityMask`,
`MultiEffect`, `Qt5Compat.GraphicalEffects`. Stick to `Rectangle`, `Image`,
`Text`, `Repeater`, `NumberAnimation`, `ColorAnimation`. The "Basic"
`QQuickStyle` is mandatory for the same reason.

**Resolution-agnostic layout.** The UI runs from 240p (CRT) to 1080p. Use
`Sizing.pctH()`, `Sizing.pctW()`, `Sizing.fontSize()` for all dimensions.
Scale element counts with resolution (e.g. `Sizing.visibleCovers`). Never
hardcode pixel values.

**Qt 6.7+ only.** No Qt5 compatibility code. No `#if QT_VERSION` guards.

**Dynamic Qt on desktop; static on MiSTer.** `BUILD_SHARED_LIBS ON` is the
default and required for LGPL compliance on desktop. The ARM32 Docker build
uses static Qt — do not change this.

**Watch the FPS counter.** `src/ui/components/FpsCounter.qml` shows a live
FPS readout (green ≥55, yellow ≥30, red <30). When changing visuals, verify
it stays green at 720p+ and doesn't fall red at 240p.

**State is always serializable; the app is effectively stateless across runs.**
MiSTer launcher scripts kill and relaunch the binary freely. Design all
application state (selected game, carousel position, menu state, settings) so
it can be persisted to disk at any time and fully restored on the next launch.
On startup, load persisted state before the first frame paints — the relaunch
must feel instant to the user. Never hold in-memory-only state that would be
lost on kill.

## Commands

```bash
# Build and run (desktop)
cmake -S . -B build && cmake --build build
./build/bin/zaparoo-launcher

# Run on framebuffer
QT_QPA_PLATFORM=linuxfb QT_QUICK_BACKEND=software ./build/bin/zaparoo-launcher

# Tests
ctest --test-dir build --output-on-failure

# All linters (clang-format check + clang-tidy + qmllint)
cmake --build build --target lint

# Individual linters
cmake --build build --target format-check   # clang-format dry-run
cmake --build build --target tidy           # clang-tidy
cmake --build build --target all_qmllint    # QML linting

# Auto-format C++ (after tidy finds issues)
pre-commit run --all-files
```

For ARM32 / MiSTer builds and deploy bundle, see @docs/building.md.

## IMPORTANT: Repo Policy

After editing any C++ or QML file, ALWAYS run:
1. `cmake --build build --target lint` — zero warnings is the bar.
2. `ctest --test-dir build --output-on-failure` — if the change can affect
   runtime behaviour.

Never leave a lint warning or failing test unresolved.

## QML Gotchas

These pitfalls come up repeatedly; qmllint only catches them after you've
written the code:

- **Typed properties, not `var`.** Use `list<string>`, `list<url>`, `int`,
  `real` — `var` produces `QVariant` warnings and blocks AOT compilation.
- **`Repeater` delegates need `pragma ComponentBehavior: Bound`** at the top
  of the file. Add `required property int index` to the delegate, plus
  `required property string modelData` when the model is a list.
- **Nested delegate children** that reference the delegate's properties must
  qualify: give the delegate an `id` and use `id.modelData`, not bare
  `modelData`.
- **Singleton QML types** need both `pragma Singleton` in the `.qml` file
  and `set_source_files_properties(Foo.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)`
  in CMake, or qmllint will warn "not declared as singleton in qmldir".
- **Function type annotations required.** Add `: ParamType` parameters and
  `: ReturnType` return types to all functions in singleton `.qml` files.
- **`NumberAnimation on propName`** conflicts with `property T propName: value`.
  Drop the `: value` initialiser — the animation takes over immediately.

## Module Map

| Directory | URI | Contents |
|---|---|---|
| `src/ui/theme/` | `Zaparoo.Theme` | `Theme`, `Sizing` singletons |
| `src/ui/components/` | `Zaparoo.Ui` | `Carousel`, `Starfield`, `FpsCounter`, `MenuBar`, `SelectionDots`, `CrtOverlay` |
| `src/ui/app/` | `Zaparoo.App` | `Main.qml` + embedded fonts and images |
| `src/core/` | _(C++ only)_ | `Config`, `Logger`, `PlatformPaths`, `ZaparooClient` |

Import QML modules as `import Zaparoo.Theme`, `import Zaparoo.Ui`, etc.
Resources are embedded at `qrc:/qt/qml/Zaparoo/App/resources/...`.
`compile_commands.json` is always generated in `build/`; no extra CMake flag needed.

## Further Reading

- @docs/architecture.md — module graph, data-flow plan, LGPL notes
- @docs/building.md — full build matrix (ARM32 toolchain, deploy bundle, sanitizers)
- `src/LICENSES/` — Qt LGPL notices
