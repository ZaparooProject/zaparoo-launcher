# Zaparoo Launcher — Agent Instructions

Zaparoo Launcher is a Qt/QML game launcher for Zaparoo Core. It targets two
environments: MiSTer FPGA (ARM32, Linux framebuffer, no GPU, software
rendering) and desktop Linux (x86_64, windowed). The hard rendering
constraint shapes every visual decision. See @docs/architecture.md for the
module graph and @docs/building.md for the full build matrix.

## Constraints

### NEVER

- Use shaders, `LinearGradient`, `RadialGradient`, `DropShadow`, `Glow`,
  `OpacityMask`, `MultiEffect`, `Qt5Compat.GraphicalEffects`, or any other
  GPU-dependent QML type. MiSTer renders in software on a framebuffer.
  Stick to `Rectangle`, `Image`, `Text`, `Repeater`, `NumberAnimation`,
  `ColorAnimation`. "Basic" `QQuickStyle` is mandatory.
- Hardcode pixel values. The UI runs 240p (CRT) → 1080p; use
  `Sizing.pctH()`, `Sizing.pctW()`, `Sizing.fontSize()`, and
  `Sizing.visibleCovers` for every dimension and element count.
- Add Qt5 compatibility code or `#if QT_VERSION` guards. Qt 6.7+ only.
- Change `BUILD_SHARED_LIBS` — `ON` on desktop is required for LGPL
  compliance; `OFF` on ARM32/MiSTer is set by the Docker toolchain.
- Hold in-memory-only application state. MiSTer's launcher script kills
  and relaunches the binary freely; every piece of user-visible state
  (selected game, carousel position, menu state, settings) must be
  serializable to disk and restored before the first frame paints.
- Leave a lint warning or failing test unresolved.
- `cd rust/` or invoke raw cmake/cargo. Drive every workflow from the
  repo root via `just`.
- Write a bare English literal in QML (or a `tr()`-less literal in C++)
  for anything the user might read. Wrap it in `qsTr()` and pass runtime
  values via `%1`/`%2` so translators can reorder — e.g. `qsTr("%1
  FPS").arg(fps)`, not `qsTr("FPS: ") + fps`. Enum tags, QRC URLs, log
  strings, and other non-user-facing literals stay bare. See
  @docs/translations.md for the full pipeline.
- Use `tokio::sync::broadcast` to publish *state* (connection state,
  catalog status, anything a subscriber needs to know the current
  value of). Broadcast channels silently drop messages sent before a
  receiver subscribes, so a late subscriber — e.g. a QML singleton
  whose `initialize()` runs after the WebSocket task has already sent
  `Connecting` → `Connected` — sees nothing and sits on its hardcoded
  initial value forever. Use `tokio::sync::watch` for state: it
  retains the latest value, and subscribers seed via `borrow()` then
  await `changed()`. Reserve `broadcast` for fan-out of *events*
  where missing the early ones is acceptable.

### ASK

- Before adding or changing a `Client` method in
  `rust/zaparoo-core/src/client.rs` — cross-check
  https://zaparoo.org/docs/core/api/ first. Method names, param shapes,
  and return types must match upstream.

### ALWAYS

- Write comments and documentation in American English.
- After editing any C++, Rust, or QML file: run `just lint` (zero
  warnings is the bar) and `just test` if the change can affect runtime
  behavior.
- Watch `src/ui/components/FpsCounter.qml` when changing visuals —
  it must stay green (≥55) at 720p+ and not fall red (<30) at 240p.

## Commands

Run `just --list` for the full menu. The `justfile` is the source of
truth — `.cargo/config.toml` and `CMakePresets.json` are tuned to it.

    just build | run                   desktop cmake + run
    just test | test-qml | test-rust   ctest + cargo nextest
    just lint | lint-cpp | lint-rust   clang-format/tidy + qmllint +
                                       rustfmt + clippy + cargo-deny
    just fmt                           pre-commit + cargo fmt
    just arm32 | deploy-mister         cross-build + SCP to MiSTer

## Deploy to MiSTer

`./scripts/deploy-mister.sh` — reads `MISTER_IP` from a `.env` in the
project root (create with `echo 'MISTER_IP=<ip>' > .env`). Non-obvious
context: `/media/fat/MiSTer_Zaparoo` is a pre-existing integration binary
shipped with MiSTer that is responsible for launching our `launcher`; the
deploy script restarts it, which picks up the newly-SCP'd binary
automatically. User-editable resolution and endpoint overrides live at
`/media/fat/zaparoo/launcher.toml` (example in @docs/building.md).

## Module Map

| Directory | URI | Contents |
|---|---|---|
| `src/ui/theme/` | `Zaparoo.Theme` | `Theme`, `Sizing` singletons |
| `src/ui/components/` | `Zaparoo.Ui` | `Carousel`, `CoverDelegate`, `TextTileDelegate`, `FpsCounter` |
| `src/ui/app/` | `Zaparoo.App` | `Main.qml` + embedded fonts and images |
| `rust/launcher/src/models/` | `Zaparoo.Browse` | `CategoriesModel`, `SystemsModel`, `GamesModel`, `BrowseModel` (dormant) — Rust QML singletons via cxx-qt |
| `rust/zaparoo-core/` | — | `client`, `config`, `logger`, `systems_catalog`, `media_types`, `platform_paths` (no Qt dependency) |

Import QML modules as `import Zaparoo.Theme`, `import Zaparoo.Ui`, etc.
Resources are embedded at `qrc:/qt/qml/Zaparoo/App/resources/...`.
`compile_commands.json` is generated in `build/` unconditionally.

## Logging

Use `tracing::{info,debug,warn,error}!` in Rust. Two sinks write
simultaneously: stderr (RFC-3339 human-readable) and JSONL file at
`platform_paths::log_file_path()` — `/tmp/zaparoo/launcher.log` on MiSTer,
`~/.local/share/zaparoo/logs/launcher.log` on desktop. Qt messages route
through `zaparoo_log_qt` (`rust/launcher/src/lib.rs`) with `target="qt"`,
so Qt warnings land in the same file.

Debug level is filtered out by default. Enable with `[logging] debug =
true` in `launcher.toml`, or `ZAPAROO_DEBUG=1` env var (takes effect
before config loads, useful for debugging startup).

## Further Reading

- @docs/architecture.md — module graph, data-flow, LGPL notes
- @docs/building.md — full build matrix, ARM32 toolchain, sanitizers, deploy bundle
- @docs/qml-gotchas.md — QML pitfalls qmllint only catches post-hoc (read when writing QML)
- @docs/cxx-qt-bridge.md — cxx-qt 0.7 bridge gotchas (read when editing Rust QML models)
- @docs/translations.md — `qsTr()` pipeline, adding locales, build-time mechanics
- `src/LICENSES/` — Qt LGPL notices
