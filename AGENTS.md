# Zaparoo Launcher Agent Guide

Zaparoo Launcher is a Qt/QML frontend for Zaparoo Core. It runs on desktop
Linux and on MiSTer FPGA (ARM32, Linux framebuffer, software rendering). The
MiSTer target is the hard constraint: assume no GPU, process kills without
notice, and a small ARM CPU.

Keep this file focused on commands, traps, and rules that are hard to infer
from the tree. Use the docs for longer explanations.

## Commands

Run every workflow from the repo root with `just`. Do not `cd rust/` and run
raw cargo as the default path; the justfile carries the expected environment.

| Task | Command |
|---|---|
| Desktop build | `just build` |
| Desktop run | `just run` |
| Dev run against mock Core | `just mock-core` in one terminal, `just run-dev` in another |
| Full test gate | `just test` |
| QML/C++ tests only | `just test-qml` |
| Rust tests only | `just test-rust` |
| Full lint gate | `just lint` |
| Rust lint only | `just lint-rust` |
| Format | `just fmt` |
| MiSTer ARM32 build | `just arm32` |
| Deploy to MiSTer | `just deploy-mister` |

`just --list` is the source of truth. `CMakePresets.json` and
`rust/.cargo/config.toml` are tuned for those recipes.

## Stack Facts

- Qt 6.7+ with Qt Quick, QuickControls2, QML, QuickTest, and LinguistTools.
- C++17 executable at `src/app/main.cpp`; Rust static library linked through
  Corrosion and cxx-qt.
- Rust workspace is under `rust/`, edition 2021, MSRV 1.90, cxx-qt 0.7.
- Desktop builds link Qt dynamically for LGPL compliance.
- MiSTer ARM32 builds use the Docker toolchain and static Qt.

## Always

- Keep comments and docs in American English.
- After editing C++, Rust, or QML, run `just lint`. Run `just test` when the
  change can affect runtime behavior.
- Keep user-visible state persistent. Selected screen, carousel positions,
  focus, settings, and similar state must be serialized to disk and restored
  before the first frame. MiSTer's wrapper can kill and relaunch the process at
  any time.
- Wrap user-visible QML strings in `qsTr()` and C++ strings in `tr()`. Use
  `%1`/`%2` placeholders for runtime values so translators can reorder text.
- Check `src/ui/components/FpsCounter.qml` after visual changes. It must stay
  green (>=55 FPS) at 720p+ and not fall red (<30 FPS) at 240p.

## Ask First

- Before adding or changing a `Client` method in
  `rust/zaparoo-core/src/client.rs`, check the upstream API docs:
  <https://zaparoo.org/docs/core/api/>. Method names, params, and return types
  must match Core.
- Before changing `Sizing.qml` behavior or the persisted state schema, confirm
  the migration/reset behavior.
- Before adding dependencies, changing CI, or touching license/trademark text,
  confirm the intended policy.

## Never

- Do not use shader-backed or GPU-dependent QML: `LinearGradient`,
  `RadialGradient`, `DropShadow`, `Glow`, `OpacityMask`, `MultiEffect`,
  `Qt5Compat.GraphicalEffects`, Qt Quick Studio shapes, or custom shaders.
  Stick to software-rendering-safe types such as `Rectangle`, `Image`, `Text`,
  `Repeater`, `Item`, `NumberAnimation`, and `ColorAnimation`.
- Do not hardcode pixel sizes or fixed element counts in UI. Use
  `Sizing.pctH()`, `Sizing.pctW()`, `Sizing.fontSize()`, and
  `Sizing.visibleCovers`.
- Do not add Qt5 compatibility code or `#if QT_VERSION` guards. This project is
  Qt 6.7+ only.
- Do not change `BUILD_SHARED_LIBS`. Desktop needs `ON`; the ARM32 toolchain
  sets static linking for MiSTer.
- Do not publish state with `tokio::sync::broadcast` when late subscribers need
  the current value. Use `tokio::sync::watch` for state and reserve broadcast
  for lossy events.
- Do not inline a `watch::Sender::borrow()` or any read guard in an `if let`,
  `match`, or `while let` scrutinee when the body writes to the same channel or
  lock. Bind the read in an inner scope first:
  `let next = { let cur = tx.borrow(); fsm.step(&cur) };`.
- Do not leave lint warnings, failing tests, or untranslated user-facing text
  behind.

## Project Map

| Path | Purpose |
|---|---|
| `src/app/main.cpp` | Thin Qt entry point, translator install, QML engine, Qt log bridge |
| `src/ui/app/Main.qml` | Runtime router: input, persistence orchestration, screen transitions |
| `src/ui/app/MainLayout.qml` | Designer-editable visual tree |
| `src/ui/screens/` | `Zaparoo.Screens`: `ScreenManager`, `HubScreen`, `GamesScreen` |
| `src/ui/components/` | `Zaparoo.Ui`: carousel, delegates, FPS counter |
| `src/ui/theme/` | `Zaparoo.Theme`: `Theme`, `Sizing` singletons |
| `rust/launcher/src/models/` | `Zaparoo.Browse` cxx-qt singletons and models |
| `rust/launcher/src/bind.rs` | Endpoint-to-QML binding macro with synchronous seed |
| `rust/zaparoo-core/src/client.rs` | WebSocket JSON-RPC client for Zaparoo Core |
| `rust/zaparoo-core/src/store/` | Endpoint cache, tags, mutations, invalidation |
| `rust/zaparoo-core/src/persist.rs` | Atomic persisted UI state |
| `rust/zaparoo-core/src/platform_paths.rs` | Config, log, and state paths per runtime |

QML module URIs are `Zaparoo.App`, `Zaparoo.Screens`, `Zaparoo.Ui`,
`Zaparoo.Theme`, and `Zaparoo.Browse`. Resources are embedded under
`qrc:/qt/qml/Zaparoo/App/resources/...`. `compile_commands.json` is generated
in `build/` by default.

## Runtime Notes

- `Runtime` answers where the launcher binary is running. `Platform` answers
  where Zaparoo Core is running. Do not collapse them.
- Desktop config: `~/.config/zaparoo/launcher.toml`.
- Desktop state: `~/.config/zaparoo/state.toml`.
- Desktop log: `~/.local/share/zaparoo/logs/launcher.log`.
- MiSTer config: `/media/fat/zaparoo/launcher.toml`.
- MiSTer state/log: `/tmp/zaparoo/state.toml`, `/tmp/zaparoo/launcher.log`.
- `ZAPAROO_CORE_ENDPOINT` overrides `[core] endpoint`; `ZAPAROO_STATE_FILE`
  redirects state for tests and ad-hoc runs.
- Debug logging is enabled with `[logging] debug = true` or `ZAPAROO_DEBUG=1`.

## MiSTer Deploy

`just deploy-mister` reads `MISTER_IP` from `.env`, builds the ARM32 binary,
copies it to `/media/fat/zaparoo/launcher`, restarts `/media/fat/MiSTer_Zaparoo`,
and clears `/tmp/zaparoo/launcher.log`.

`/media/fat/MiSTer_Zaparoo` is the integration binary shipped with MiSTer. It
starts our `launcher`; do not replace that flow with a new wrapper script.

## Further Reading

- `docs/architecture.md` — module graph, data flow, runtime/platform split
- `docs/building.md` — build matrix, ARM32 toolchain, deploy bundle
- `docs/qml-gotchas.md` — QML issues qmllint often catches late
- `docs/cxx-qt-bridge.md` — cxx-qt 0.7 bridge constraints
- `docs/translations.md` — `qsTr()`/`tr()` pipeline and locale catalogs
- `design/README.md` — Qt Design Studio workflow and designer boundaries
- `src/LICENSES/` — Qt LGPL notices
