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
