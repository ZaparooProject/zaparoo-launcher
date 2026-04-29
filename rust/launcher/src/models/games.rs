// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0

use crate::models::{global_runtime, global_store};
use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::{QByteArray, QHash, QHashPair_i32_QByteArray, QModelIndex, QString, QVariant};
use std::pin::Pin;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use tokio::task::JoinHandle;
use tracing::warn;
use zaparoo_core::endpoints::media_search::MediaSearchEndpoint;
use zaparoo_core::endpoints::readers_write::ReadersWriteMutation;
use zaparoo_core::endpoints::run::RunMutation;
use zaparoo_core::media_types::{MediaItem, MediaSearchResult, ReadersWriteParams, RunParams};
use zaparoo_core::remote_resource::ResourceStatus;

const NAME_ROLE: i32 = 256 + 1;
const PATH_ROLE: i32 = 256 + 2;
const ZAP_SCRIPT_ROLE: i32 = 256 + 3;
const SYSTEM_ID_ROLE: i32 = 256 + 4;
// Until per-game cover art lands, game tiles reuse the parent system
// logo. The shared Tile delegate looks up `coverKey`, so expose the
// same value under that role name.
const COVER_KEY_ROLE: i32 = 256 + 5;

#[derive(Default)]
pub struct GamesModelRust {
    items: Vec<MediaItem>,
    count: i32,
    loading: bool,
    error_message: QString,
    has_next_page: bool,
    current_system_id: QString,
    selected_index: i32,
    card_write_pending: bool,
    card_write_error: QString,
    // Cancellation handle for the QML-bridge watcher of the currently
    // selected system. The `RemoteResource` itself lives in the store's
    // cache (keyed by system id), so a re-subscribe to a previously
    // selected system reuses the cached entry and skips the RPC.
    // Aborting the watcher stops it from enqueuing *more* callbacks,
    // but cannot drain ones already on the Qt event loop — `seq` below
    // is what makes those stale callbacks no-ops.
    watcher: Option<JoinHandle<()>>,
    // Monotonic ticket bumped on each `set_system` call. The watcher's
    // queued closure captures the ticket value at spawn time and bails
    // if `seq` has advanced — closing the window where a callback
    // queued by the old system's watcher runs on the Qt thread after
    // the new system's state has already been applied.
    seq: Arc<AtomicU64>,
    // Invalidates stale card-write completions after the user cancels or
    // starts another write before the previous RPC returns.
    card_write_seq: Arc<AtomicU64>,
}

#[cxx_qt::bridge]
pub mod ffi {
    unsafe extern "C++" {
        include!("model_includes.h");

        #[allow(non_snake_case, reason = "Qt class names are PascalCase")]
        type QAbstractListModel;

        type QModelIndex = cxx_qt_lib::QModelIndex;
        type QVariant = cxx_qt_lib::QVariant;
        type QHash_i32_QByteArray = cxx_qt_lib::QHash<cxx_qt_lib::QHashPair_i32_QByteArray>;
        type QByteArray = cxx_qt_lib::QByteArray;
        type QString = cxx_qt_lib::QString;
    }

    unsafe extern "RustQt" {
        #[qobject]
        #[base = QAbstractListModel]
        #[qml_element]
        #[qml_singleton]
        #[qproperty(i32, count)]
        #[qproperty(bool, loading)]
        #[qproperty(QString, error_message)]
        #[qproperty(bool, has_next_page)]
        #[qproperty(QString, current_system_id)]
        #[qproperty(bool, card_write_pending)]
        #[qproperty(QString, card_write_error)]
        type GamesModel = super::GamesModelRust;

        #[qinvokable]
        fn set_system(self: Pin<&mut GamesModel>, system_id: QString);

        #[qinvokable]
        fn launch_at(self: Pin<&mut GamesModel>, index: i32);

        #[qinvokable]
        fn write_card_at(self: Pin<&mut GamesModel>, index: i32);

        #[qinvokable]
        fn cancel_card_write(self: Pin<&mut GamesModel>);

        #[qinvokable]
        fn name_at(self: &GamesModel, index: i32) -> QString;

        #[qinvokable]
        fn path_at(self: &GamesModel, index: i32) -> QString;

        #[qinvokable]
        fn index_for_game_path(self: &GamesModel, path: &QString) -> i32;

        #[qinvokable]
        fn set_selected_index(self: Pin<&mut GamesModel>, index: i32);

        #[inherit]
        #[cxx_name = "beginResetModel"]
        fn begin_reset_model(self: Pin<&mut GamesModel>);

        #[inherit]
        #[cxx_name = "endResetModel"]
        fn end_reset_model(self: Pin<&mut GamesModel>);

        #[cxx_name = "rowCount"]
        fn row_count(self: &GamesModel, parent: &QModelIndex) -> i32;
        fn data(self: &GamesModel, index: &QModelIndex, role: i32) -> QVariant;
        #[cxx_name = "roleNames"]
        fn role_names(self: &GamesModel) -> QHash_i32_QByteArray;
    }

    impl cxx_qt::Threading for GamesModel {}
}

impl ffi::GamesModel {
    fn row_count(&self, parent: &QModelIndex) -> i32 {
        if parent.is_valid() {
            0
        } else {
            self.count
        }
    }

    fn data(&self, index: &QModelIndex, role: i32) -> QVariant {
        if !index.is_valid() || index.row() < 0 || index.row() >= self.count {
            return QVariant::default();
        }
        let item = &self.items[index.row() as usize];
        match role {
            NAME_ROLE => QVariant::from(&QString::from(item.name.as_str())),
            PATH_ROLE => QVariant::from(&QString::from(item.path.as_str())),
            ZAP_SCRIPT_ROLE => QVariant::from(&QString::from(item.zap_script.as_str())),
            SYSTEM_ID_ROLE => QVariant::from(&QString::from(item.system.id.as_str())),
            COVER_KEY_ROLE => {
                // Relative path under `resources/images/` (no extension).
                // Tile resolves the PNG via `images/<coverKey>.png` so all
                // models share one URL builder.
                QVariant::from(&QString::from(
                    format!("systems/{}", item.system.id).as_str(),
                ))
            }
            _ => QVariant::default(),
        }
    }

    fn role_names(&self) -> QHash<QHashPair_i32_QByteArray> {
        let mut h = QHash::<QHashPair_i32_QByteArray>::default();
        h.insert(NAME_ROLE, QByteArray::from("name"));
        h.insert(PATH_ROLE, QByteArray::from("path"));
        h.insert(ZAP_SCRIPT_ROLE, QByteArray::from("zapScript"));
        h.insert(SYSTEM_ID_ROLE, QByteArray::from("systemId"));
        h.insert(COVER_KEY_ROLE, QByteArray::from("coverKey"));
        h
    }

    fn set_system(mut self: Pin<&mut Self>, system_id: QString) {
        let sid = system_id.to_string();
        if sid == self.current_system_id.to_string() && !self.items.is_empty() {
            return;
        }

        // User-visible reset happens synchronously so QML sees fresh
        // state immediately, before the resource has even spun up.
        // Crucially, drop the prior system's rows here too — otherwise
        // the games grid keeps painting (and accepting input on) games
        // from the system the user just navigated away from until the
        // new system's fetch resolves.
        self.as_mut().set_current_system_id(system_id);
        self.as_mut().set_loading(true);
        self.as_mut().set_error_message(QString::default());
        self.as_mut().set_has_next_page(false);
        if !self.items.is_empty() {
            self.as_mut().begin_reset_model();
            self.as_mut().rust_mut().items.clear();
            self.as_mut().rust_mut().count = 0;
            self.as_mut().rust_mut().selected_index = -1;
            self.as_mut().end_reset_model();
            self.as_mut().count_changed();
        }

        // Abort the old watcher so it stops enqueuing further callbacks.
        // Any callback already on the Qt event loop is still pending —
        // the `seq` ticket below is what discards those stale ones.
        if let Some(handle) = self.as_mut().rust_mut().watcher.take() {
            handle.abort();
        }

        // Bump the ticket *before* spawning. The new watcher captures
        // this value; any earlier-watcher callback still in the Qt
        // queue captured the previous ticket and will bail when it sees
        // the mismatch.
        let seq = self.rust().seq.clone();
        let ticket = seq.fetch_add(1, Ordering::SeqCst) + 1;

        // Per-arg subscribe: the store keys its cache by system id, so
        // toggling between systems reuses cached resources and only
        // pays the RPC cost on first sight.
        let resource = global_store().subscribe::<MediaSearchEndpoint>(sid);
        let mut status_rx = resource.subscribe();

        // Sync-seed runs inline on the Qt thread, so it cannot race a
        // queued callback (Qt won't pump events until set_system
        // returns). No ticket check needed here.
        let snapshot = status_rx.borrow_and_update().clone();
        apply_status(self.as_mut(), snapshot);

        let qt_thread = self.qt_thread();
        let handle = global_runtime().spawn(async move {
            while status_rx.changed().await.is_ok() {
                let snapshot = status_rx.borrow_and_update().clone();
                let seq_for_closure = seq.clone();
                let _ = qt_thread.queue(move |model| {
                    if seq_for_closure.load(Ordering::SeqCst) != ticket {
                        return;
                    }
                    apply_status(model, snapshot);
                });
            }
        });
        self.as_mut().rust_mut().watcher = Some(handle);
    }

    fn launch_at(self: Pin<&mut Self>, index: i32) {
        if index < 0 || index >= self.count {
            return;
        }
        let item = &self.items[index as usize];
        if item.zap_script.is_empty() {
            return;
        }
        let text = item.zap_script.clone();
        let name = item.name.clone();
        let store = global_store();
        global_runtime().spawn(async move {
            if let Err(e) = store.run_mutation::<RunMutation>(RunParams { text }).await {
                warn!("run failed for {name}: {}", e.message);
            }
        });
    }

    fn write_card_at(mut self: Pin<&mut Self>, index: i32) {
        if index < 0 || index >= self.count {
            self.as_mut()
                .set_card_write_error(QString::from("invalid selection"));
            self.as_mut().set_card_write_pending(false);
            return;
        }
        let item = &self.items[index as usize];
        if item.zap_script.is_empty() {
            self.as_mut()
                .set_card_write_error(QString::from("missing zap script"));
            self.as_mut().set_card_write_pending(false);
            return;
        }
        let text = item.zap_script.clone();
        let name = item.name.clone();
        let store = global_store();
        let seq = self.rust().card_write_seq.clone();
        let ticket = seq.fetch_add(1, Ordering::SeqCst) + 1;
        self.as_mut().set_card_write_error(QString::default());
        self.as_mut().set_card_write_pending(true);
        let qt_thread = self.qt_thread();
        global_runtime().spawn(async move {
            let result = store
                .run_mutation::<ReadersWriteMutation>(ReadersWriteParams { text })
                .await;
            let _ = qt_thread.queue(move |mut model| {
                if seq.load(Ordering::SeqCst) != ticket {
                    return;
                }
                let error = match result {
                    Ok(()) => QString::default(),
                    Err(e) => {
                        warn!("card write failed for {name}: {}", e.message);
                        QString::from(e.message.as_str())
                    }
                };
                model.as_mut().set_card_write_error(error);
                model.as_mut().set_card_write_pending(false);
            });
        });
    }

    fn cancel_card_write(mut self: Pin<&mut Self>) {
        self.as_mut()
            .rust()
            .card_write_seq
            .fetch_add(1, Ordering::SeqCst);
        if !self.card_write_error.is_empty() {
            self.as_mut().set_card_write_error(QString::default());
        }
        if self.card_write_pending {
            self.as_mut().set_card_write_pending(false);
        }
    }

    fn name_at(&self, index: i32) -> QString {
        if index < 0 || index >= self.count {
            return QString::default();
        }
        QString::from(self.items[index as usize].name.as_str())
    }

    fn path_at(&self, index: i32) -> QString {
        if index < 0 || index >= self.count {
            return QString::default();
        }
        QString::from(self.items[index as usize].path.as_str())
    }

    fn index_for_game_path(&self, path: &QString) -> i32 {
        position_of_game_path(&self.items, &path.to_string())
    }

    fn set_selected_index(mut self: Pin<&mut Self>, index: i32) {
        self.as_mut().rust_mut().selected_index = index;
    }
}

/// Find `needle` in `items` with case-sensitive path equality. Returns
/// position as i32, or -1 if not found / empty needle. Filesystem
/// paths are case-sensitive on Linux (and the launcher's `MiSTer`
/// target), so a case-insensitive lookup would mask a real upstream
/// path drift. Pulled out of `index_for_game_path` for testability.
fn position_of_game_path(items: &[MediaItem], needle: &str) -> i32 {
    if needle.is_empty() {
        return -1;
    }
    items
        .iter()
        .position(|item| item.path == needle)
        .map_or(-1, |i| i as i32)
}

/// Pure projection of a `ResourceStatus<MediaSearchResult>` onto the
/// shape `apply_status` writes into the model. Splitting the match
/// out as a free function lets the four arms be unit-tested without
/// a Qt event loop — `apply_status` itself only touches `QObject`
/// setters, which need a live `Pin<&mut ffi::GamesModel>` and so are
/// only reachable from the bridge.
#[derive(Debug)]
enum Projection {
    /// `Idle`/`Loading` collapse to the same view: spinner on, no
    /// error, no pagination indicator. Items are not touched.
    Pending,
    /// Successful fetch — items replace the model rows wholesale.
    Ready {
        items: Vec<MediaItem>,
        count: i32,
        has_next_page: bool,
    },
    /// Both `retrying` and terminal errors map here; the UI treats
    /// them the same (banner + clear loading state).
    Errored { message: String },
}

fn project_status(status: ResourceStatus<MediaSearchResult>) -> Projection {
    match status {
        ResourceStatus::Idle | ResourceStatus::Loading => Projection::Pending,
        ResourceStatus::Ready(result) => {
            let has_next_page = result.has_next_page();
            let count = result.results.len() as i32;
            Projection::Ready {
                items: result.results,
                count,
                has_next_page,
            }
        }
        ResourceStatus::Errored { message, .. } => Projection::Errored { message },
    }
}

/// Apply a freshly-derived `Projection` to the model. Centralising
/// the writes here is what closes the original "lost
/// `has_next_page` reset on the error path" bug — every arm passes
/// through one place.
fn apply_status(mut model: Pin<&mut ffi::GamesModel>, status: ResourceStatus<MediaSearchResult>) {
    match project_status(status) {
        Projection::Pending => {
            if !model.loading {
                model.as_mut().set_loading(true);
            }
            if !model.error_message.is_empty() {
                model.as_mut().set_error_message(QString::default());
            }
            if model.has_next_page {
                model.as_mut().set_has_next_page(false);
            }
        }
        Projection::Ready {
            items,
            count,
            has_next_page,
        } => {
            if has_next_page {
                let sid = model.current_system_id.to_string();
                warn!("games list for {sid} has >100 results; only first page shown");
            }
            model.as_mut().begin_reset_model();
            model.as_mut().rust_mut().items = items;
            model.as_mut().rust_mut().count = count;
            model.as_mut().end_reset_model();
            model.as_mut().count_changed();
            model.as_mut().set_has_next_page(has_next_page);
            if model.loading {
                model.as_mut().set_loading(false);
            }
            if !model.error_message.is_empty() {
                model.as_mut().set_error_message(QString::default());
            }
        }
        Projection::Errored { message } => {
            let qstr = QString::from(message.as_str());
            if model.error_message != qstr {
                model.as_mut().set_error_message(qstr);
            }
            if model.loading {
                model.as_mut().set_loading(false);
            }
            if model.has_next_page {
                model.as_mut().set_has_next_page(false);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    #![allow(
        clippy::expect_used,
        clippy::unwrap_used,
        clippy::panic,
        reason = "tests should fail-fast on unexpected errors"
    )]

    use super::{position_of_game_path, project_status, Projection};
    use zaparoo_core::media_types::{MediaItem, MediaSearchResult, Pagination, SystemRef};
    use zaparoo_core::remote_resource::ResourceStatus;

    fn item(name: &str, system_id: &str) -> MediaItem {
        MediaItem {
            name: name.into(),
            path: format!("/p/{name}"),
            zap_script: format!("@{system_id}/{name}"),
            system: SystemRef {
                id: system_id.into(),
            },
            tags: Vec::new(),
        }
    }

    #[test]
    fn idle_projects_to_pending() {
        match project_status(ResourceStatus::Idle) {
            Projection::Pending => {}
            other => panic!("expected Pending, got {other:?}"),
        }
    }

    #[test]
    fn loading_projects_to_pending() {
        match project_status(ResourceStatus::Loading) {
            Projection::Pending => {}
            other => panic!("expected Pending, got {other:?}"),
        }
    }

    #[test]
    fn ready_with_results_projects_count_and_items() {
        let result = MediaSearchResult {
            results: vec![item("smb", "NES"), item("zelda", "NES")],
            pagination: Pagination::default(),
        };
        match project_status(ResourceStatus::Ready(result)) {
            Projection::Ready {
                items,
                count,
                has_next_page,
            } => {
                assert_eq!(count, 2);
                assert_eq!(items.len(), 2);
                assert_eq!(items[0].name, "smb");
                assert!(!has_next_page);
            }
            other => panic!("expected Ready, got {other:?}"),
        }
    }

    #[test]
    fn ready_empty_results_projects_zero_count() {
        let result = MediaSearchResult::default();
        match project_status(ResourceStatus::Ready(result)) {
            Projection::Ready {
                items,
                count,
                has_next_page,
            } => {
                assert_eq!(count, 0);
                assert!(items.is_empty());
                assert!(!has_next_page);
            }
            other => panic!("expected Ready, got {other:?}"),
        }
    }

    #[test]
    fn ready_with_pagination_propagates_has_next_page() {
        let result = MediaSearchResult {
            results: vec![item("smb", "NES")],
            pagination: Pagination {
                has_next_page: true,
                page_size: 100,
                next_cursor: Some("c".into()),
            },
        };
        match project_status(ResourceStatus::Ready(result)) {
            Projection::Ready { has_next_page, .. } => assert!(has_next_page),
            other => panic!("expected Ready, got {other:?}"),
        }
    }

    #[test]
    fn errored_with_retrying_propagates_message() {
        match project_status(ResourceStatus::Errored {
            message: "rpc kaboom".into(),
            retrying: true,
        }) {
            Projection::Errored { message } => assert_eq!(message, "rpc kaboom"),
            other => panic!("expected Errored, got {other:?}"),
        }
    }

    #[test]
    fn errored_without_retrying_propagates_message() {
        match project_status(ResourceStatus::Errored {
            message: "connection refused".into(),
            retrying: false,
        }) {
            Projection::Errored { message } => assert_eq!(message, "connection refused"),
            other => panic!("expected Errored, got {other:?}"),
        }
    }

    #[test]
    fn position_of_game_path_returns_index_on_case_exact_match() {
        let items = vec![item("smb", "NES"), item("zelda", "NES")];
        assert_eq!(position_of_game_path(&items, "/p/zelda"), 1);
    }

    #[test]
    fn position_of_game_path_is_case_sensitive() {
        let items = vec![item("smb", "NES")];
        // GamesState.game_path is persisted as the exact upstream path
        // and the launcher's targets (Linux desktop, MiSTer) are
        // case-sensitive filesystems; case-insensitive lookup would
        // silently match a different file.
        assert_eq!(position_of_game_path(&items, "/P/SMB"), -1);
        assert_eq!(position_of_game_path(&items, "/p/SMB"), -1);
    }

    #[test]
    fn position_of_game_path_empty_needle_returns_minus_one() {
        let items = vec![item("smb", "NES")];
        assert_eq!(position_of_game_path(&items, ""), -1);
    }

    #[test]
    fn position_of_game_path_missing_returns_minus_one() {
        let items = vec![item("smb", "NES")];
        assert_eq!(position_of_game_path(&items, "/p/missing"), -1);
    }
}
