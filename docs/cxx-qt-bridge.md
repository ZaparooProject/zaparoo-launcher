# cxx-qt Bridge Gotchas

Read this when writing Rust QML models via cxx-qt 0.7 in
`rust/launcher/src/models/`.

- **`cxx = "1"` must be a direct dependency.** The `#[cxx_qt::bridge]` macro
  expands to `#[cxx::bridge]`. Rust resolves proc-macro attributes in the
  calling crate's scope, so `cxx` must appear in that crate's `[dependencies]`.
  A transitive dep through `cxx-qt` is not sufficient.

- **`#[qproperty(T, snake_case_name)]` auto-converts to camelCase** on the Qt
  and QML side. `#[qproperty(bool, has_next_page)]` → accessible as
  `hasNextPage` in QML.

- **User-defined `#[qinvokable]` methods are exposed with their Rust name**
  (snake_case). QML calls them as `model.set_system(id)` etc. Add
  `#[cxx_name = "..."]` only when you need camelCase (e.g. to match a Qt
  base-class virtual like `rowCount`, `roleNames`, `beginResetModel`).

- **cxx-qt plugin class name** for a `Zaparoo.Browse` module is
  `Zaparoo_Browse_plugin` (not `Zaparoo_BrowsePlugin`). Use
  `Q_IMPORT_QML_PLUGIN(Zaparoo_Browse_plugin)` in the C++ entry point.

- **Bind QML singletons to data through `bind_to_endpoint!`.** QML
  singletons are constructed *after* `init_globals` runs, which is
  *after* the WebSocket task has very likely already advanced past
  `Idle`/`Disconnected`. If you only spawn an async watcher inside
  `initialize()`, the QObject's `Default::default()` placeholder values
  are visible to the first frame.

  The macro at `rust/launcher/src/bind.rs` emits the entire
  `cxx_qt::Initialize` impl: it subscribes the singleton to the
  store-cached `RemoteResource<E::Output>` for the chosen endpoint,
  reads the current `ResourceStatus` *synchronously* before returning,
  and only then spawns the qt_thread watcher for subsequent updates.
  The seed bug is closed structurally — there is no place left to
  forget it.

  ```rust
  // models/app_status.rs — full bridge for the AppStatus banner.
  crate::bind_to_endpoint! {
      for ffi::AppStatus,
      endpoint = CatalogEndpoint,
      args = (),
      select = project,       // fn(&ResourceStatus<CatalogData>) -> Projected
      apply  = apply_state,   // fn(Pin<&mut Self>, Projected)
  }
  ```

  `select` and `apply` are free functions (not closures) so they're
  `Copy` and reusable across the sync seed and the async loop. For
  per-arg endpoints (e.g. `MediaSearchEndpoint`, keyed by system id),
  drive `Store::subscribe` directly from a `#[qinvokable]` and abort
  the previous watcher's `JoinHandle` before installing the new one
  (see `models/games.rs`).

  Use `tokio::sync::watch` for any state a `RemoteResource` exposes;
  `tokio::sync::broadcast` drops messages sent before a receiver
  subscribes and so loses the seed value entirely (see the CLAUDE.md
  "broadcast vs watch" note).
