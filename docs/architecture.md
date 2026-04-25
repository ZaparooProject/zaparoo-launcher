# Architecture

## Module graph

```
src/app/main.cpp
  launcher (executable)
    │   Thin C++ entry point: constructs QGuiApplication + QQmlApplicationEngine,
    │   installs Qt message handler, calls zaparoo_rust_init() from the Rust staticlib.
    │
    ├── rust/launcher/  [zaparoo_launcher_rs staticlib]
    │     ├── src/lib.rs
    │     │     zaparoo_rust_init()      — tokio runtime, logger, WebSocket client,
    │     │                               Store, model globals
    │     │     zaparoo_rust_post_qt_start() — post-engine hooks
    │     │     zaparoo_log_qt()         — Qt message handler sink → tracing registry
    │     │
    │     ├── src/bind.rs
    │     │     `bind_to_endpoint!` macro — emits the cxx_qt::Initialize
    │     │     impl for QML singletons (sync seed + qt_thread watcher).
    │     │
    │     ├── src/mister_runtime.rs
    │     │     Pre-Qt setup on ARM32: vmode resolution switch, zaparoo.sh start.
    │     │     Compiled on all platforms; MiSTer-specific calls are gated by cfg.
    │     │
    │     ├── src/models/  [Zaparoo.Browse QML module via cxx-qt 0.7]
    │     │     AppStatus, CategoriesModel, SystemsModel, GamesModel,
    │     │     AppState, HubState, GamesState, Input, BrowseModel.
    │     │     All registered via build.rs QmlModule.
    │     │
    │
    ├── rust/zaparoo-core/  [non-Qt Rust crate]
    │     client.rs           — WebSocket JSON-RPC 2.0 (tokio-tungstenite)
    │     remote_resource.rs  — RemoteResource<T>/ResourceStatus<T>
    │     store/              — Endpoint, Mutation, Tag, Store cache
    │     endpoints/          — CatalogEndpoint, MediaSearchEndpoint, RunMutation
    │     systems_catalog.rs  — CatalogData payload + by-category filter
    │     input_actions.rs    — action names + Qt key-code mapping
    │     persist.rs          — write-through persisted UI state
    │     config.rs           — TOML config (launcher.toml)
    │     logger.rs           — tracing-subscriber: stderr + JSONL file sinks
    │     runtime.rs          — Runtime enum: what device the launcher runs on
    │     platform.rs         — Platform enum: what Zaparoo Core is running on
    │     platform_paths.rs   — log/config paths routed through runtime
    │     media_types.rs      — file-extension → media-type lookup
    │
    └── src/ui/app/  [Zaparoo.App QML module]
          Main.qml          — runtime router: input, persistence, transitions
          MainLayout.qml    — designer-editable visual tree
          │
          ├── src/ui/screens/  [Zaparoo.Screens QML module]
          │     ScreenManager.qml, HubScreen.qml, GamesScreen.qml
          │
          ├── src/ui/components/  [Zaparoo.Ui QML module]
          │     Carousel.qml, CoverDelegate.qml, TextTileDelegate.qml,
          │     FpsCounter.qml
          │
          └── src/ui/theme/  [Zaparoo.Theme QML module]
                Sizing.qml  — pctH/pctW/fontSize singletons
                Theme.qml   — colors and font-family constants
```

## QML module URIs

| Target | URI | Load path |
|---|---|---|
| zaparoo_launcher_rs (plugin) | `Zaparoo.Browse` | `qrc:/qt/qml/Zaparoo/Browse/` |
| zaparoo_ui_app | `Zaparoo.App` | `qrc:/qt/qml/Zaparoo/App/` |
| zaparoo_ui_screens | `Zaparoo.Screens` | `qrc:/qt/qml/Zaparoo/Screens/` |
| zaparoo_ui_components | `Zaparoo.Ui` | `qrc:/qt/qml/Zaparoo/Ui/` |
| zaparoo_ui_theme | `Zaparoo.Theme` | `qrc:/qt/qml/Zaparoo/Theme/` |

`engine.loadFromModule("Zaparoo.App", "Main")` is the only entry point. Keep
`qrc:/` strings out of the rest of the app.

## Key constraints

- **Software rendering only.** MiSTer has no GPU. Do not use shaders,
  `LinearGradient`, `RadialGradient`, `DropShadow`, `Glow`, `OpacityMask`,
  `MultiEffect`, or `Qt5Compat.GraphicalEffects`. Use `Rectangle`, `Image`,
  `Text`, `Repeater`, `NumberAnimation`, and `ColorAnimation`.

- **Resolution-agnostic layout.** The UI runs from 240p CRT output to 1080p.
  Use `Sizing.pctH()`, `Sizing.pctW()`, and `Sizing.fontSize()` for
  dimensions. Do not hardcode pixel values.

- **FPS counter is always on.** When changing visuals, keep it green (≥55 FPS)
  at 720p+ and above 30 FPS at 240p.

- **Dynamic Qt on desktop, static Qt on MiSTer.** `BUILD_SHARED_LIBS=ON` is
  the default for LGPL-compliant desktop distribution. The ARM32 Docker build
  passes `-DBUILD_SHARED_LIBS=OFF` through the Qt CMake toolchain.

## Runtime vs Platform

The launcher tracks two separate facts. Do not collapse them; that is how old
runtime/platform bugs come back.

| Concept | Source of truth | Question answered |
|---|---|---|
| **Runtime** | `zaparoo_core::runtime::current()` (filesystem-cached) | What device is the **launcher binary** running on? |
| **Platform** | `zaparoo_core::platform::subscribe()` (from `version` RPC) | What OS/device is **Zaparoo Core** running on? |

`Runtime == Mister` does **not** imply `Platform == Mister`. The launcher
can run on a desktop while talking to Core on a MiSTer on the network,
or vice-versa.

### When to use which

- **Runtime gate** — use this when the launcher's host device changes the
  behavior. Read `runtime::current()`. Prefer runtime gating for behavior.
- **Build-time cfg `#[cfg(zaparoo_runtime = "mister")]`** — use this only for
  code that should not compile into desktop binaries: system calls,
  MiSTer-only dependencies, and similar. Currently only `mister_runtime.rs`
  uses it. `ZAPAROO_RUNTIME=mister` is set in `cmake/ZaparooRust.cmake` for
  static-Qt ARM32 builds.
- **Platform gate** — use this when a feature depends on what Core supports.
  Subscribe to `platform::subscribe()` and treat `None` as unknown; do not
  enable platform-specific behavior until the first `version` RPC completes.
  Do not gate on `Platform` directly from C++ or QML. Route the decision
  through Rust and expose a QML property.

**Never gate runtime behavior on `Platform`, never gate Core
assumptions on `Runtime`.** They are independent.

## LGPL compliance

Qt is used under LGPLv3. The desktop binary links Qt dynamically, so end
users can replace the bundled Qt libraries. The MiSTer ARM32 binary is
statically linked; object files are available on request per LGPL §4(d)(1).
License texts live in `src/LICENSES/`.

## Rust → QML data flow

The data layer follows the RTK Query shape. A single `Store` owns the `Client`,
hands out shared `RemoteResource<T>` values keyed by `(endpoint NAME, args
hash)`, and routes mutations through the same client. QML singletons subscribe
by binding to an `Endpoint`; `rust/launcher/src/bind.rs` emits the bridge code
for the sync seed, the `qt_thread` watcher, and the property apply step.

```
zaparoo_rust_init()
    │
    ├── logger::install()          — tracing-subscriber (stderr + JSONL file)
    ├── Config::load()             — launcher.toml
    ├── tokio::Runtime::new()      — multi-thread executor
    ├── Client::new(endpoint)      — WebSocket JSON-RPC, auto-reconnects
    └── Store::new(client, runtime)
          │
          │   subscribe::<E>(args) → Arc<RemoteResource<E::Output>>
          │     ─ keyed cache: identical args reuse the same Arc
          │     ─ per-entry watcher updates `provides` on each Ready
          │
          │   run_mutation::<M>(args) → invalidates matching tags,
          │     each refetch pulses Notify on its RemoteResource
          │
          ├── CatalogEndpoint           Args = ()        provides: any("Catalog")
          │     └── bound by AppStatus, CategoriesModel, SystemsModel
          │           via `bind_to_endpoint!`
          │
          ├── MediaSearchEndpoint       Args = SystemId  provides: specific("MediaSearch", id)
          │     └── GamesModel::set_system subscribes per-system; the
          │         store keys cache entries by id so re-selecting a
          │         system reuses its cached resource without re-fetching
          │
          └── RunMutation               Args = RunParams  invalidates: ()
                └── GamesModel::launch_at → store.run_mutation::<RunMutation>
                      Today no tags are invalidated; future
                      NowPlayingEndpoint can opt in by adding its tag.
```

`RemoteResource<T>` combines the connection FSM and per-fetch state into one
`ResourceStatus<T>`: `Idle`, `Loading`, `Ready(T)`, or
`Errored { message, retrying }`. Each binding reads the current status
synchronously before it spawns the watcher. That closes the MiSTer race where
Core can connect before QML loads and the first screen never updates.

The Qt message handler (`qInstallMessageHandler`) forwards Qt log output to
`zaparoo_log_qt()` in the Rust staticlib. From there it goes through the same
tracing registry as Rust logs. Both end up in stderr and `launcher.log`.

### Navigation state

`Main.qml` extends `MainLayout.qml`. The layout owns the visual tree; `Main.qml`
owns the runtime wiring: key translation, screen transitions, and persistence.
Screens live under `Zaparoo.Screens` so they can be tested without embedding the
whole application shell.

```
ScreenManager.activeScreen: "hub" | "games"
HubScreen.section:          "categories" | "systems"
```

Persisted state is split across Rust-backed QML singletons:

| Singleton | Stored fields | Owner |
|---|---|---|
| `Browse.AppState` | `active_screen` | cross-screen route |
| `Browse.HubState` | `focus`, `category`, `system_id` | hub screen selection |
| `Browse.GamesState` | `system_id`, `game_path` | games screen selection |

State is loaded before the first QML frame and written through on user actions.
That is deliberate: MiSTer's parent process can kill and relaunch the launcher
without warning.

- **hub + categories**: `HubScreen` shows the categories carousel. Left/Right
  cycles categories; Enter calls `SystemsModel.set_category()` and switches
  `HubScreen.section` to `"systems"`; Escape quits.
- **hub + systems**: the categories carousel moves to the top and systems fade
  in below. Enter calls `GamesModel.set_system()` and requests the games screen;
  Escape returns to categories.
- **games**: `GamesScreen` shows the games carousel. Enter calls
  `GamesModel.launch_at()`; Escape requests the hub screen, preserving hub
  focus.

Model reset handlers in `Main.qml` restore saved carousel indices as catalog
data arrives. Missing IDs fall back to index 0 without erasing the saved value
from disk, so a temporary catalog gap does not destroy the user's last
selection.
