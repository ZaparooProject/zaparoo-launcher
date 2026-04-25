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
    │     │     AppStatus, CategoriesModel, SystemsModel, GamesModel
    │     │     (BrowseModel and per-screen state singletons).
    │     │     All registered via build.rs QmlModule.
    │     │
    │     └── rust/zaparoo-core/  [non-Qt Rust crate]
    │           client.rs           — WebSocket JSON-RPC 2.0 (tokio-tungstenite)
    │           remote_resource.rs  — RemoteResource<T>/ResourceStatus<T>
    │           store/              — Endpoint, Mutation, Tag, Store cache
    │           endpoints/          — CatalogEndpoint, MediaSearchEndpoint, RunMutation
    │           systems_catalog.rs  — CatalogData payload + by-category filter
    │           config.rs           — TOML config (launcher.toml)
    │           logger.rs           — tracing-subscriber: stderr + JSONL file sinks
    │           runtime.rs          — Runtime enum: what device the launcher runs on
    │           platform.rs         — Platform enum: what Zaparoo Core is running on
    │           platform_paths.rs   — log/config paths routed through runtime
    │           media_types.rs      — file-extension → media-type lookup
    │
    └── src/ui/app/  [Zaparoo.App QML module]
          Main.qml
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

## Runtime vs Platform

Two orthogonal facts the launcher reasons about. Keep them separate —
gating the wrong one reintroduces bugs the split was designed to prevent.

| Concept | Source of truth | Question answered |
|---|---|---|
| **Runtime** | `zaparoo_core::runtime::current()` (filesystem-cached) | What device is the **launcher binary** running on? |
| **Platform** | `zaparoo_core::platform::subscribe()` (from `version` RPC) | What OS/device is **Zaparoo Core** running on? |

`Runtime == Mister` does **not** imply `Platform == Mister`. The launcher
can run on a desktop while talking to Core on a MiSTer on the network,
or vice-versa.

### When to use which

- **Runtime gate** — "this code path behaves differently depending on
  the launcher's host device." Read `runtime::current()`. Prefer runtime
  gating for behavior.
- **Build-time cfg `#[cfg(zaparoo_runtime = "mister")]`** — reserve for
  code that genuinely should not compile into desktop binaries (system
  calls, MiSTer-only dependencies). Currently only `mister_runtime.rs`
  uses this. Set by `ZAPAROO_RUNTIME=mister` in `cmake/ZaparooRust.cmake`
  for static-Qt (ARM32) builds.
- **Platform gate** — "this feature depends on what Core supports."
  Subscribe to `platform::subscribe()`; treat `None` as "unknown — don't
  enable platform-specific features until the first `version` RPC
  completes." Never gate on `Platform` from C++/QML directly; route the
  decision through Rust and expose a QML property.

**Never gate runtime behavior on `Platform`, never gate Core
assumptions on `Runtime`.** They are independent.

## LGPL compliance

Qt is used under LGPLv3. The desktop binary links Qt dynamically, so end
users can replace the bundled Qt libraries. The MiSTer ARM32 binary is
statically linked; object files are available on request per LGPL §4(d)(1).
License texts live in `src/LICENSES/`.

## Rust → QML data flow

The data layer is RTK-Query-shaped: a single `Store` owns the
`Client`, hands out shared `RemoteResource<T>`s keyed by
`(endpoint NAME, args hash)`, and routes mutations through to the
same client. QML singletons subscribe by binding to an `Endpoint`;
the macro at `rust/launcher/src/bind.rs` emits the entire bridge
(sync seed + qt_thread watcher + property apply).

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

`RemoteResource<T>` collapses the connection FSM and per-fetch state
into a single `ResourceStatus<T>`: `Idle`, `Loading`, `Ready(T)`,
`Errored { message, retrying }`. Every binding seeds itself
synchronously from the *current* status before spawning the watcher,
which closes the MiSTer "screen never updates if Core connects before
QML loads" race.

Qt message handler (`qInstallMessageHandler`) forwards all Qt log output
to `zaparoo_log_qt()` in the Rust staticlib, which routes it through the
same tracing registry. All log output (Rust + Qt) ends up in the same
sinks: stderr and `launcher.log`.

### Navigation state (Main.qml)

```
activeScreen: "hub" | "games"
hubFocus:     "categories" | "systems"
```

- **hub + categories**: categoriesCarousel centered; Left/Right cycle categories;
  Enter calls `SystemsModel.set_category()` and shifts hubFocus to "systems";
  Escape quits.
- **hub + systems**: categoriesCarousel swoops to top; systemsCarousel fades in
  below; Enter calls `GamesModel.set_system()` and sets activeScreen to "games";
  Escape returns to categories.
- **games**: gamesCarousel visible; Enter calls `GamesModel.launch_at()`;
  Escape returns to hub (hubFocus preserved).
