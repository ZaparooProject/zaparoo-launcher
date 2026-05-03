// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//
// `Browse.GamesModel` — directory-aware, cumulative paged browse over
// Zaparoo Core's `media.browse` endpoint.
//
// Two paths into the model:
//
//   * `set_system(id)` — entry from SystemsScreen accept. Issues
//     `media.browse({systems: [id]})` (system-scoped roots). When the
//     scoped roots collapse to a single folder entry, we auto-navigate
//     into that folder so the user never sees a 1-item list — most
//     systems have one root and showing it standalone would be empty
//     ceremony.
//
//   * `set_path(path)` — entry from a folder accept inside the games
//     screen. Issues `media.browse({path, systems: [current_system]})`.
//     No auto-navigation; explicit folder navigation is treated as
//     intent.
//
// `fetch_more()` advances pagination without resetting the model:
// `begin_insert_rows` appends entries from the next cursor onto the
// existing vec. Cursor lives in the model, not in the endpoint cache
// key, because cursor-paged follow-ups bypass the cache (one entry per
// cursor would defeat the cache).
//
// `seq` discipline: bumped on every `set_system` / `set_path`, read
// (not bumped) by `fetch_more`. Late callbacks whose ticket doesn't
// match `seq` are dropped — the standard cure for Qt-thread races
// when the user spams direction-arrow + Accept across a model swap.

use crate::media_image_cache::{global_media_image_cache, MediaImageCache, MediaKey};
use crate::models::{global_runtime, global_store};
use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::{
    QByteArray, QHash, QHashPair_i32_QByteArray, QList, QModelIndex, QString, QVariant,
};
use std::collections::HashSet;
use std::pin::Pin;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::broadcast::error::RecvError;
use tokio::task::JoinHandle;
use tracing::{info, warn};
use zaparoo_core::client::ClientError;
use zaparoo_core::endpoints::media_browse::{BrowseArgs, MediaBrowseEndpoint};
use zaparoo_core::endpoints::readers_write::ReadersWriteMutation;
use zaparoo_core::endpoints::run::RunMutation;
use zaparoo_core::media_types::{
    BrowseEntry, MediaBrowseParams, MediaBrowseResult, ReadersWriteParams, RunParams,
};
use zaparoo_core::platform::{self, Platform};
use zaparoo_core::remote_resource::ResourceStatus;

const NAME_ROLE: i32 = 256 + 1;
const PATH_ROLE: i32 = 256 + 2;
const ZAP_SCRIPT_ROLE: i32 = 256 + 3;
const SYSTEM_ID_ROLE: i32 = 256 + 4;
// Folder tiles always use `icons/Folder`. Media tiles default to
// `icons/File` and switch to `media-image/<encoded>` once the in-memory
// media image cache has bytes for `(systemId, path)`;
// Resources.coverUrl() rewrites the `media-image/` prefix to
// `image://media-image/<encoded>` so the QQuickImageProvider serves the
// bytes from RAM.
const COVER_KEY_ROLE: i32 = 256 + 5;
const ENTRY_TYPE_ROLE: i32 = 256 + 6;
const FILE_COUNT_ROLE: i32 = 256 + 7;

// Default API page size before QML binds the model's `page_size` to the
// grid's `pageSize`. 15 = 5 columns × 3 rows, the desktop default. The
// test harness sees this until it overrides explicitly. Server cap is
// 1000; grid page sizes top out at ~30 so we stay well inside bounds.
const DEFAULT_PAGE_SIZE: i32 = 15;

#[allow(
    clippy::struct_excessive_bools,
    reason = "the bools are independent qproperties surfaced to QML; collapsing them \
              into an enum would force the QML side to read a single state property \
              and re-derive each flag locally, which is exactly the work the bridge \
              avoids"
)]
pub struct GamesModelRust {
    entries: Vec<BrowseEntry>,
    count: i32,
    loading: bool,
    loading_more: bool,
    error_message: QString,
    has_next_page: bool,
    // Files-only count from Core (`BrowseFileCount`). Combined with
    // `dir_count` to compute total entries for the page denominator —
    // dirs are returned only on page 1 and always before files, so
    // `dir_count + total_files` is exact, not an estimate.
    total_files: i32,
    // Count of leading directory entries seen on page 1. Set once when
    // page 1 lands and never touched on cursor follow-ups (Core never
    // returns directories on follow-up pages).
    dir_count: i32,
    // API page size, bound to the QML grid's `pageSize` so the API page
    // matches the visual page exactly — no mid-page "Loading more…"
    // pause on the user's first scroll past row 0.
    page_size: i32,
    current_system_id: QString,
    current_path: QString,
    next_cursor: Option<String>,
    card_write_pending: bool,
    card_write_error: QString,
    // Watcher for the current initial-page subscription. Aborted on
    // every path swap so the prior watcher stops enqueuing callbacks
    // for the old `BrowseArgs`. Callbacks already in the Qt queue are
    // disarmed by `seq` rather than by the abort.
    watcher: Option<JoinHandle<()>>,
    // Bumped on every `set_system` / `set_path`. Read but NOT bumped
    // by `fetch_more` — cursor-driven follow-ups are part of the same
    // path's load and should keep the same ticket.
    seq: Arc<AtomicU64>,
    // True only for `set_system`-driven initial loads. The single-root
    // auto-nav case is the only place we want to skip the rendered
    // intermediate state, so the flag is consumed by the apply
    // function and reset once the decision has been made.
    auto_nav_eligible: bool,
    // Invalidates stale card-write completions after the user cancels
    // or starts another write before the previous RPC returns.
    card_write_seq: Arc<AtomicU64>,
    // Long-lived bridge from `media_image_cache` broadcast updates onto Qt
    // `dataChanged(coverKey)` emits. Spun up lazily on the first
    // `start_initial_browse` so the model singleton owns exactly one
    // subscriber for the whole process lifetime.
    cover_subscription: Option<JoinHandle<()>>,
    // Keys whose first-paint we're still waiting on. While non-empty we
    // hold `loading = true` so the screen-flip overlay covers the gap
    // between "page rendered with glyphs" and "covers cached". Drained
    // by `notify_cover_update` as each cover lands; force-cleared by
    // the gate timer or a subsequent `start_initial_browse`.
    pending_first_paint_keys: HashSet<MediaKey>,
    // Safety timer that force-releases the cover gate after a bounded
    // delay, so a stalled bulk RPC can't park the user on `Loading…`
    // forever.
    cover_gate_timer: Option<JoinHandle<()>>,
    // Bumped on every cover-gate arm and on every `start_initial_browse`.
    // The timer's queued closure compares against the current value and
    // bails on a mismatch — necessary because aborting the JoinHandle
    // doesn't cancel a callback that was already queued onto the Qt
    // thread between sleep-completion and abort.
    cover_gate_seq: Arc<AtomicU64>,
}

impl Default for GamesModelRust {
    fn default() -> Self {
        Self {
            entries: Vec::new(),
            count: 0,
            loading: false,
            loading_more: false,
            error_message: QString::default(),
            has_next_page: false,
            total_files: 0,
            dir_count: 0,
            page_size: DEFAULT_PAGE_SIZE,
            current_system_id: QString::default(),
            current_path: QString::default(),
            next_cursor: None,
            card_write_pending: false,
            card_write_error: QString::default(),
            watcher: None,
            seq: Arc::new(AtomicU64::new(0)),
            auto_nav_eligible: false,
            card_write_seq: Arc::new(AtomicU64::new(0)),
            cover_subscription: None,
            pending_first_paint_keys: HashSet::new(),
            cover_gate_timer: None,
            cover_gate_seq: Arc::new(AtomicU64::new(0)),
        }
    }
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
        type QList_i32 = cxx_qt_lib::QList<i32>;
    }

    unsafe extern "RustQt" {
        #[qobject]
        #[base = QAbstractListModel]
        #[qml_element]
        #[qml_singleton]
        #[qproperty(i32, count)]
        #[qproperty(bool, loading)]
        #[qproperty(bool, loading_more)]
        #[qproperty(QString, error_message)]
        #[qproperty(bool, has_next_page)]
        #[qproperty(i32, total_files)]
        #[qproperty(i32, dir_count)]
        #[qproperty(i32, page_size)]
        #[qproperty(QString, current_system_id)]
        #[qproperty(QString, current_path)]
        #[qproperty(bool, card_write_pending)]
        #[qproperty(QString, card_write_error)]
        type GamesModel = super::GamesModelRust;

        #[qinvokable]
        fn set_system(self: Pin<&mut GamesModel>, system_id: QString);

        #[qinvokable]
        fn set_path(self: Pin<&mut GamesModel>, path: &QString);

        #[qinvokable]
        fn fetch_more(self: Pin<&mut GamesModel>);

        #[qinvokable]
        fn launch_at(self: Pin<&mut GamesModel>, index: i32);

        #[qinvokable]
        fn launch_text_at(self: &GamesModel, index: i32) -> QString;

        #[qinvokable]
        fn write_card_at(self: Pin<&mut GamesModel>, index: i32);

        #[qinvokable]
        fn cancel_card_write(self: Pin<&mut GamesModel>);

        #[qinvokable]
        fn name_at(self: &GamesModel, index: i32) -> QString;

        #[qinvokable]
        fn path_at(self: &GamesModel, index: i32) -> QString;

        #[qinvokable]
        fn entry_type_at(self: &GamesModel, index: i32) -> QString;

        #[qinvokable]
        fn index_for_game_path(self: &GamesModel, path: &QString) -> i32;

        #[inherit]
        #[cxx_name = "beginResetModel"]
        fn begin_reset_model(self: Pin<&mut GamesModel>);

        #[inherit]
        #[cxx_name = "endResetModel"]
        fn end_reset_model(self: Pin<&mut GamesModel>);

        #[inherit]
        #[cxx_name = "beginInsertRows"]
        fn begin_insert_rows(
            self: Pin<&mut GamesModel>,
            parent: &QModelIndex,
            first: i32,
            last: i32,
        );

        #[inherit]
        #[cxx_name = "endInsertRows"]
        fn end_insert_rows(self: Pin<&mut GamesModel>);

        // Qt signal bound as a callable so the cover-cache bridge can
        // invoke it directly from the Qt thread when an async cover
        // fetch completes for a row that is already on screen.
        #[inherit]
        #[cxx_name = "dataChanged"]
        fn data_changed(
            self: Pin<&mut GamesModel>,
            top_left: &QModelIndex,
            bottom_right: &QModelIndex,
            roles: &QList_i32,
        );

        #[cxx_name = "rowCount"]
        fn row_count(self: &GamesModel, parent: &QModelIndex) -> i32;
        fn data(self: &GamesModel, index: &QModelIndex, role: i32) -> QVariant;
        #[cxx_name = "roleNames"]
        fn role_names(self: &GamesModel) -> QHash_i32_QByteArray;

        // Materialise a `QModelIndex` for `(row, column)` so the cover-
        // cache bridge can target individual rows in `dataChanged`.
        // Forwarded to the QAbstractListModel implementation.
        #[inherit]
        fn index(self: &GamesModel, row: i32, column: i32, parent: &QModelIndex) -> QModelIndex;
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
        let entry = &self.entries[index.row() as usize];
        match role {
            NAME_ROLE => QVariant::from(&QString::from(entry.name.as_str())),
            PATH_ROLE => QVariant::from(&QString::from(entry.path.as_str())),
            ZAP_SCRIPT_ROLE => QVariant::from(&QString::from(entry.zap_script.as_str())),
            SYSTEM_ID_ROLE => QVariant::from(&QString::from(entry_system_id(entry).as_str())),
            COVER_KEY_ROLE => QVariant::from(&QString::from(cover_key_for(entry).as_str())),
            ENTRY_TYPE_ROLE => QVariant::from(&QString::from(entry.entry_type.as_str())),
            FILE_COUNT_ROLE => QVariant::from(&i32::try_from(entry.file_count).unwrap_or(i32::MAX)),
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
        h.insert(ENTRY_TYPE_ROLE, QByteArray::from("entryType"));
        h.insert(FILE_COUNT_ROLE, QByteArray::from("fileCount"));
        h
    }

    fn set_system(mut self: Pin<&mut Self>, system_id: QString) {
        let sid = system_id.to_string();
        self.as_mut().set_current_system_id(system_id);
        // No-op short-circuit removed deliberately: SystemsScreen
        // accept always wants a "show me this system again" round
        // trip after Esc-back, even when the same system is current.
        // The Endpoint cache makes the repeat cheap (cached
        // `BrowseArgs` returns its existing `Ready` value
        // synchronously through the watcher's seed).
        let systems = if sid.is_empty() {
            Vec::new()
        } else {
            vec![sid]
        };
        self.start_initial_browse(String::new(), systems, true);
    }

    fn set_path(self: Pin<&mut Self>, path: &QString) {
        let p = path.to_string();
        let sid = self.current_system_id.to_string();
        let systems = if sid.is_empty() {
            Vec::new()
        } else {
            vec![sid]
        };
        self.start_initial_browse(p, systems, false);
    }

    fn fetch_more(mut self: Pin<&mut Self>) {
        // Debounce: PagedGrid fires `loadMoreRequested` once per page
        // turn, but a fast spinner on the last loaded page can fire
        // twice before the first follow-up returns. Both guards
        // matter: `loading_more` covers in-flight, `has_next_page`
        // covers terminal pages.
        if self.loading_more || !self.has_next_page {
            return;
        }
        let cursor = self.next_cursor.clone();
        let path = self.current_path.to_string();
        let sid = self.current_system_id.to_string();
        let systems = if sid.is_empty() {
            Vec::new()
        } else {
            vec![sid]
        };
        // Read the active ticket WITHOUT bumping it. `fetch_more`
        // continues the same path's load — only `set_system` /
        // `set_path` invalidate the prior cursor sequence.
        let seq = self.seq.clone();
        let ticket = seq.load(Ordering::SeqCst);
        let max_results = u32::try_from(self.page_size.max(1)).unwrap_or(u32::from(u16::MAX));
        self.as_mut().set_loading_more(true);
        let qt_thread = self.qt_thread();
        let store = global_store();
        // Capture the cursor we're advancing from. If `next_cursor`
        // differs by the time the response arrives (e.g. a watcher
        // refetch reset the chain via `apply_initial_page`), this
        // append no longer belongs to the current page chain and
        // would corrupt the freshly-reset entries.
        let expected_prev_cursor = cursor.clone();
        global_runtime().spawn(async move {
            let result = store
                .client()
                .media_browse(MediaBrowseParams {
                    path,
                    systems,
                    max_results: Some(max_results),
                    cursor,
                    letter: None,
                    sort: None,
                })
                .await;
            let _ = qt_thread.queue(move |model| {
                if seq.load(Ordering::SeqCst) != ticket {
                    return;
                }
                apply_append_page(model, result, expected_prev_cursor.as_deref());
            });
        });
    }

    fn launch_at(self: Pin<&mut Self>, index: i32) {
        if index < 0 || index >= self.count {
            return;
        }
        let entry = &self.entries[index as usize];
        if entry.zap_script.is_empty() {
            return;
        }
        let text = entry.zap_script.clone();
        let name = entry.name.clone();
        let store = global_store();
        global_runtime().spawn(async move {
            if let Err(e) = store.run_mutation::<RunMutation>(RunParams { text }).await {
                warn!("run failed for {name}: {}", e.message);
            }
        });
    }

    fn launch_text_at(&self, index: i32) -> QString {
        if index < 0 || index >= self.count {
            return QString::default();
        }
        QString::from(self.entries[index as usize].zap_script.as_str())
    }

    fn write_card_at(mut self: Pin<&mut Self>, index: i32) {
        if index < 0 || index >= self.count {
            self.as_mut()
                .set_card_write_error(QString::from("invalid selection"));
            self.as_mut().set_card_write_pending(false);
            return;
        }
        let entry = &self.entries[index as usize];
        if entry.zap_script.is_empty() {
            self.as_mut()
                .set_card_write_error(QString::from("missing zap script"));
            self.as_mut().set_card_write_pending(false);
            return;
        }
        let text = entry.zap_script.clone();
        let name = entry.name.clone();
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
        QString::from(self.entries[index as usize].name.as_str())
    }

    fn path_at(&self, index: i32) -> QString {
        if index < 0 || index >= self.count {
            return QString::default();
        }
        QString::from(self.entries[index as usize].path.as_str())
    }

    fn entry_type_at(&self, index: i32) -> QString {
        if index < 0 || index >= self.count {
            return QString::default();
        }
        QString::from(self.entries[index as usize].entry_type.as_str())
    }

    fn index_for_game_path(&self, path: &QString) -> i32 {
        position_of_game_path(&self.entries, &path.to_string())
    }

    /// Spin up the long-lived cover-cache subscriber on first use.
    /// Subsequent calls are no-ops — the model singleton owns exactly
    /// one subscriber for the whole process lifetime, decoupled from
    /// `seq` because cover updates are not tied to a particular browse
    /// path. Lagged broadcast frames are dropped silently; the
    /// `dataChanged` we'd otherwise emit is recoverable on the next
    /// scroll because `data()` re-reads the cache for every visible
    /// row's `coverKey`.
    fn ensure_cover_subscription(mut self: Pin<&mut Self>) {
        if self.cover_subscription.is_some() {
            return;
        }
        let cache = global_media_image_cache();
        let mut rx = cache.subscribe();
        let qt_thread = self.qt_thread();
        let handle = global_runtime().spawn(async move {
            loop {
                match rx.recv().await {
                    Ok(update) => {
                        let _ = qt_thread.queue(move |model| {
                            notify_cover_update(model, &update.key);
                        });
                    }
                    Err(RecvError::Lagged(_)) => {}
                    Err(RecvError::Closed) => break,
                }
            }
        });
        self.as_mut().rust_mut().cover_subscription = Some(handle);
    }

    /// Issue a fresh `media.browse` for `(path, systems)`. Bumps `seq`,
    /// aborts the prior watcher, clears entries via `beginResetModel`,
    /// subscribes to `MediaBrowseEndpoint`, and spawns a watcher whose
    /// queued callbacks bail unless the ticket still matches.
    ///
    /// `eligible_for_auto_nav` is set when this load came from
    /// `set_system`. The single-root auto-nav case in
    /// `apply_initial_page` consumes the flag to decide whether to skip
    /// rendering the 1-item roots list and dive straight into that
    /// root.
    fn start_initial_browse(
        mut self: Pin<&mut Self>,
        path: String,
        systems: Vec<String>,
        eligible_for_auto_nav: bool,
    ) {
        info!(
            ?path,
            ?systems,
            eligible_for_auto_nav,
            "games: start_initial_browse",
        );
        self.as_mut().ensure_cover_subscription();
        self.as_mut().set_current_path(QString::from(path.as_str()));
        self.as_mut().set_loading(true);
        self.as_mut().set_error_message(QString::default());
        self.as_mut().set_has_next_page(false);
        self.as_mut().set_loading_more(false);
        self.as_mut().rust_mut().auto_nav_eligible = eligible_for_auto_nav;
        self.as_mut().rust_mut().next_cursor = None;
        if !self.entries.is_empty() {
            self.as_mut().begin_reset_model();
            self.as_mut().rust_mut().entries.clear();
            self.as_mut().rust_mut().count = 0;
            self.as_mut().end_reset_model();
            self.as_mut().count_changed();
        }
        // Total-files counter resets too — the previous path's
        // denominator would be misleading until the new fetch lands.
        self.as_mut().set_total_files(0);
        // Same reasoning for dir_count: a stale value from the previous
        // browse target would misclassify which leading entries are
        // folders if the new fetch fails or stalls.
        self.as_mut().set_dir_count(0);

        if let Some(handle) = self.as_mut().rust_mut().watcher.take() {
            handle.abort();
        }
        // Tear down any cover gate left from the prior path. See
        // `reset_cover_gate` for the rationale; without this teardown
        // a stale timer callback could fire after the new path's
        // `set_loading(true)` and prematurely release its gate.
        reset_cover_gate(self.as_mut());

        let seq = self.rust().seq.clone();
        let ticket = seq.fetch_add(1, Ordering::SeqCst) + 1;

        let max_results = u32::try_from(self.page_size.max(1)).unwrap_or(u32::from(u16::MAX));
        let resource = global_store().subscribe::<MediaBrowseEndpoint>(BrowseArgs::new(
            path,
            systems,
            max_results,
        ));
        let mut status_rx = resource.subscribe();

        // Spawn the watcher BEFORE applying the sync seed. If
        // `apply_status` recurses into `start_initial_browse` (auto-nav
        // cascade on a single-folder result), the inner call's
        // `watcher.take().abort()` cleans up this handle correctly —
        // doing this in the other order leaks the inner watcher when
        // the outer call later overwrites `self.watcher`.
        let qt_thread = self.qt_thread();
        let snapshot = status_rx.borrow_and_update().clone();
        let seq_for_loop = seq.clone();
        let handle = global_runtime().spawn(async move {
            while status_rx.changed().await.is_ok() {
                let snapshot = status_rx.borrow_and_update().clone();
                let seq_for_closure = seq_for_loop.clone();
                let _ = qt_thread.queue(move |model| {
                    if seq_for_closure.load(Ordering::SeqCst) != ticket {
                        return;
                    }
                    apply_status(model, snapshot);
                });
            }
        });
        self.as_mut().rust_mut().watcher = Some(handle);

        // Sync seed runs inline on the Qt thread, so it cannot race a
        // queued callback (Qt won't pump events until set_system /
        // set_path returns). No ticket check needed; the value we read
        // is whichever the resource has right now.
        apply_status(self.as_mut(), snapshot);
    }
}

/// Resolve the system id role exposed to QML. Single-system entries
/// (media items, single-system roots/directories) populate `system_id`;
/// multi-system roots fall back to the first entry of `system_ids` so
/// the tile still has *a* logo to draw rather than a blank.
fn entry_system_id(entry: &BrowseEntry) -> String {
    if !entry.system_id.is_empty() {
        return entry.system_id.clone();
    }
    entry.system_ids.first().cloned().unwrap_or_default()
}

fn cover_key_for(entry: &BrowseEntry) -> String {
    if entry.is_folder() {
        return "icons/Folder".to_string();
    }
    let media_key = media_key_for(entry);
    let cache = global_media_image_cache();
    let cached = media_key.as_ref().is_some_and(|k| cache.is_cached(k));
    if !cached {
        // Miss-driven re-enqueue: when QML asks for the cover URL of
        // a media entry whose bytes aren't in the cache, kick a fetch
        // right here. This is the recovery path for entries that fell
        // out of the cache (LRU eviction, stale-enqueue truncation):
        // when the user scrolls back to a page whose covers are gone,
        // every re-bound tile asks for its `coverKey` again, hits this
        // branch, and re-enqueues. `MediaImageCache::enqueue` is
        // idempotent — already-pending / already-negative / already-
        // cached keys short-circuit — so spamming on every role-data
        // lookup is cheap. The negative-memo check here is a small
        // optimisation that skips the lock-then-short-circuit dance
        // for keys we've already learned have nothing to fetch.
        if let Some(k) = media_key.as_ref() {
            if !cache.is_negative(k) {
                cache.enqueue_with_media_id(k.clone(), entry.media_id);
            }
        }
    }
    cover_key_for_with(entry, media_key.as_ref(), cached)
}

/// Build the canonical `(systemId, path)` identifier for a media
/// entry. Returns `None` for entries the cache cannot key on (folder
/// roots, unattributed entries, browse roots without a path).
fn media_key_for(entry: &BrowseEntry) -> Option<MediaKey> {
    if entry.is_folder() || entry.path.is_empty() {
        return None;
    }
    let system_id = entry_system_id(entry);
    if system_id.is_empty() {
        return None;
    }
    Some(MediaKey::new(system_id, entry.path.clone()))
}

/// Pure helper for `cover_key_for`. Split out so tests can drive the
/// branches (folder, cached, uncached, unattributed) without spinning
/// up the global cover cache and its tokio runtime.
fn cover_key_for_with(entry: &BrowseEntry, key: Option<&MediaKey>, cached: bool) -> String {
    if entry.is_folder() {
        return "icons/Folder".to_string();
    }
    match key {
        Some(k) if cached => MediaImageCache::image_key_for(k),
        _ => "icons/File".to_string(),
    }
}

/// Schedule a cover fetch for every media entry with a non-empty
/// `(systemId, path)` pair. `MediaImageCache::enqueue` is idempotent — calls
/// for already-cached, already-pending, or negatively-memoised keys are
/// dropped — so spamming this from `apply_initial_page`/
/// `apply_append_page` is cheap.
///
/// Iterates `entries` in reverse so the LIFO fetch queue drains in
/// visual order: the last entry we push is `entries[0]`, which the
/// driver then pops first. Forward iteration starves the top of the
/// page — e.g. for a 10-tile page the driver lands rows 9..6 before
/// the user advances, leaving rows 0..3 (the most prominent slots)
/// showing the fallback icon.
///
/// Look-ahead prefetch (`apply_initial_page` → `fetch_more`) calls
/// this exactly the same way as the visible page does. Under Core's
/// serial `media.image` cadence (~one response per 250–400 ms) the
/// LIFO drain order ends up servicing page N+1 *between* page N's
/// first burst and its tail, so by the time the user navigates
/// forward, page N+1 is warm. See the doc comment on
/// `MediaImageCache::queue` for the full rationale on why a separate
/// "low priority" lane for look-ahead is the wrong knob.
fn enqueue_cover_fetches(entries: &[BrowseEntry]) {
    let cache = global_media_image_cache();
    let mut media_total = 0usize;
    let mut enqueued = 0usize;
    for entry in entries.iter().rev() {
        if entry.is_folder() {
            continue;
        }
        media_total += 1;
        if let Some(key) = media_key_for(entry) {
            enqueued += 1;
            cache.enqueue_with_media_id(key, entry.media_id);
        }
    }
    info!(
        media_total,
        enqueued, "media_image_cache: enqueue pass over media entries",
    );
}

/// Emit `dataChanged(coverKey)` for every row whose entry's
/// `(systemId, path)` matches `key`. Cheap walk of the current
/// `entries` vec — pages top out at a few hundred rows after look-
/// ahead, and the bridge runs only when the cover-cache fetch driver
/// delivers a result.
///
/// Also drains `pending_first_paint_keys`: each cover landing during
/// the gate's hold ticks the set down, and emptying the set releases
/// the gate so the screen-flip overlay clears.
fn notify_cover_update(mut model: Pin<&mut ffi::GamesModel>, key: &MediaKey) {
    let rows: Vec<i32> = model
        .entries
        .iter()
        .enumerate()
        .filter(|(_, e)| {
            !e.is_folder() && e.path == *key.path && entry_system_id(e) == *key.system_id
        })
        .filter_map(|(i, _)| i32::try_from(i).ok())
        .collect();
    if !rows.is_empty() {
        let mut roles = QList::<i32>::default();
        roles.append(COVER_KEY_ROLE);
        let parent = QModelIndex::default();
        for row in rows {
            let idx = model.index(row, 0, &parent);
            model.as_mut().data_changed(&idx, &idx, &roles);
        }
    }
    // Tick the gate's pending set down. `remove` returns false if the
    // key wasn't gated (broadcast events fire for every cache update,
    // including miss-recovery enqueues from `cover_key_for`); we only
    // try to release when a gated key was actually drained.
    let was_pending = model
        .as_mut()
        .rust_mut()
        .pending_first_paint_keys
        .remove(key);
    if was_pending && model.pending_first_paint_keys.is_empty() && model.loading {
        if let Some(handle) = model.as_mut().rust_mut().cover_gate_timer.take() {
            handle.abort();
        }
        // Bytes are cached, but QML's `MediaImageProvider` still has to
        // decode them. The hidden cover pre-warmer in `GamesScreen.qml`
        // dispatches all N requests at once and the provider's 4-worker
        // pool decodes them in ~75–150 ms; without this settle window
        // the gate flips `loading=false` ~80 ms after the last byte
        // lands and `gamesGrid` materialises before the last few
        // decodes complete, painting the procedural fallback over those
        // tiles for a frame or two. The settle uses the same seq-ticket
        // guard as the safety timer so a folder change cancels the
        // pending release.
        info!("games: cover gate bytes settled — entering decode-settle window");
        let seq = model.rust().cover_gate_seq.clone();
        let ticket = seq.fetch_add(1, Ordering::SeqCst) + 1;
        let qt_thread = model.qt_thread();
        let handle = global_runtime().spawn(async move {
            tokio::time::sleep(Duration::from_millis(200)).await;
            let _ = qt_thread.queue(move |mut model: Pin<&mut ffi::GamesModel>| {
                if seq.load(Ordering::SeqCst) != ticket {
                    return;
                }
                model.as_mut().rust_mut().cover_gate_timer = None;
                if model.loading {
                    info!("games: cover gate released after decode-settle window");
                    model.as_mut().set_loading(false);
                }
            });
        });
        model.as_mut().rust_mut().cover_gate_timer = Some(handle);
    }
}

/// Compute the set of media keys on the current page whose covers we
/// must wait on before releasing the cover gate. Folders, unattributed
/// entries, already-cached keys, and negatively-memoised keys are all
/// excluded. Pure helper so the gate's binning logic is unit-testable
/// without spinning up the global cache + tokio runtime.
fn compute_unresolved_keys<F, G>(
    entries: &[BrowseEntry],
    is_cached: F,
    is_negative: G,
) -> HashSet<MediaKey>
where
    F: Fn(&MediaKey) -> bool,
    G: Fn(&MediaKey) -> bool,
{
    entries
        .iter()
        .filter_map(media_key_for)
        .filter(|k| !is_cached(k) && !is_negative(k))
        .collect()
}

/// Abort any in-flight cover-gate timer, drop the waiting-keys set,
/// and bump `cover_gate_seq` so a callback that already queued onto
/// the Qt thread before the abort took effect sees a stale ticket and
/// bails. Used on every browse status edge that doesn't go on to call
/// `arm_cover_gate` itself (Pending, Errored, and the
/// `start_initial_browse` reset).
fn reset_cover_gate(mut model: Pin<&mut ffi::GamesModel>) {
    if let Some(handle) = model.as_mut().rust_mut().cover_gate_timer.take() {
        handle.abort();
    }
    model.as_mut().rust_mut().pending_first_paint_keys.clear();
    model.rust().cover_gate_seq.fetch_add(1, Ordering::SeqCst);
}

/// Decide whether to hold `loading=true` until the page's covers are
/// cached, or release immediately. Called once per `apply_initial_page`.
///
/// - If every media entry is already cached or negatively-memoised
///   (folder-only page, or revisit), set loading=false right now —
///   there's nothing to wait on, the screen-flip overlay clears.
/// - Otherwise, store the unresolved set on the model, arm a 3 s safety
///   timer, and leave loading=true. `notify_cover_update` will drain
///   the set as covers land; whichever happens first (set empties or
///   timer fires) releases the gate.
///
/// The 3 s timeout is the fall-through: if the bulk RPC stalls, the
/// user sees `Loading…` for at most 3 s before the existing
/// "list with placeholders → covers pop in" behaviour resumes.
fn arm_cover_gate(mut model: Pin<&mut ffi::GamesModel>) {
    if let Some(handle) = model.as_mut().rust_mut().cover_gate_timer.take() {
        handle.abort();
    }
    let cache = global_media_image_cache();
    let unresolved = compute_unresolved_keys(
        &model.entries,
        |k| cache.is_cached(k),
        |k| cache.is_negative(k),
    );
    if unresolved.is_empty() {
        model.as_mut().rust_mut().pending_first_paint_keys.clear();
        if model.loading {
            model.as_mut().set_loading(false);
        }
        return;
    }
    info!(
        pending = unresolved.len(),
        "games: arm cover gate (holding loading until covers cached)"
    );
    model.as_mut().rust_mut().pending_first_paint_keys = unresolved;
    let seq = model.rust().cover_gate_seq.clone();
    let ticket = seq.fetch_add(1, Ordering::SeqCst) + 1;
    let qt_thread = model.qt_thread();
    let handle = global_runtime().spawn(async move {
        tokio::time::sleep(Duration::from_secs(3)).await;
        let _ = qt_thread.queue(move |model| {
            if seq.load(Ordering::SeqCst) != ticket {
                return;
            }
            release_cover_gate_after_timeout(model);
        });
    });
    model.as_mut().rust_mut().cover_gate_timer = Some(handle);
}

/// Force-release the cover gate from the safety timer. Called only via
/// the timer's queued callback after a seq-match check; the
/// notify-driven release path lives inline in `notify_cover_update`.
fn release_cover_gate_after_timeout(mut model: Pin<&mut ffi::GamesModel>) {
    let pending = model.pending_first_paint_keys.len();
    info!(pending, "games: cover gate timed out, releasing");
    model.as_mut().rust_mut().pending_first_paint_keys.clear();
    model.as_mut().rust_mut().cover_gate_timer = None;
    if model.loading {
        model.as_mut().set_loading(false);
    }
}

/// Find `needle` in `entries` with case-sensitive path equality.
fn position_of_game_path(entries: &[BrowseEntry], needle: &str) -> i32 {
    if needle.is_empty() {
        return -1;
    }
    entries
        .iter()
        .position(|e| e.path == needle)
        .map_or(-1, |i| i as i32)
}

/// Pure projection of a `ResourceStatus<MediaBrowseResult>` onto the
/// shape `apply_status` writes into the model. Pulled out so the
/// four arms can be unit-tested without a Qt event loop.
#[derive(Debug)]
enum Projection {
    /// `Idle`/`Loading` collapse to the same view: spinner on, no
    /// error. Items are not touched.
    Pending,
    /// Successful fetch; carries the raw result so the apply layer
    /// can decide whether to auto-nav into a single root.
    Ready(MediaBrowseResult),
    /// Both `retrying` and terminal errors map here; the UI treats
    /// them the same (banner + clear loading state).
    Errored { message: String },
}

fn project_status(status: ResourceStatus<MediaBrowseResult>) -> Projection {
    match status {
        ResourceStatus::Idle | ResourceStatus::Loading => Projection::Pending,
        ResourceStatus::Ready(result) => Projection::Ready(result),
        ResourceStatus::Errored { message, .. } => Projection::Errored { message },
    }
}

/// Auto-nav decision for the initial browse result. Pure so the
/// edge cases (single folder, single media, multi-root, empty) are
/// testable without a Qt environment.
#[derive(Debug, PartialEq, Eq)]
enum InitialAction {
    /// The result has exactly one folder entry and the load was
    /// `set_system`-eligible. Skip rendering and recurse into the
    /// single root's path.
    AutoNavigate { path: String },
    /// Render the result as the visible state.
    Apply,
}

fn decide_initial(
    result: &MediaBrowseResult,
    eligible_after_set_system: bool,
    platform: Option<&Platform>,
    current_path: &str,
) -> InitialAction {
    // On MiSTer, single-folder loads also flatten on `set_path`. MiSTer
    // collections often unzip into nested single-child folders; the
    // recursion in `apply_status` calls `start_initial_browse(... false)`
    // on the auto-nav target, so a chain of single-child folders
    // collapses all the way down on each navigation step.
    let mister_set_path_flatten = matches!(platform, Some(Platform::Mister));
    let single_entry_flatten = eligible_after_set_system || mister_set_path_flatten;
    if !single_entry_flatten || result.entries.len() != 1 {
        return InitialAction::Apply;
    }
    let entry = &result.entries[0];
    // Cycle guard: refuse to auto-nav into the path we're already on.
    // Prevents stack overflow if Core erroneously returns a folder
    // whose path equals the parent.
    if entry.is_folder() && !entry.path.is_empty() && entry.path != current_path {
        return InitialAction::AutoNavigate {
            path: entry.path.clone(),
        };
    }
    InitialAction::Apply
}

/// Pre-process a freshly-decoded `media.browse` page before storing it
/// in the model. Currently only used for the `MiSTer` leading-underscore
/// strip: `MiSTer` paths use `_PrefixedFolder` to control sort order in
/// the `MiSTer` menu, which is a layout artifact not user-facing intent.
/// Path stays untouched — launching/navigation still depend on the
/// original.
fn transform_entries(
    mut entries: Vec<BrowseEntry>,
    platform: Option<&Platform>,
) -> Vec<BrowseEntry> {
    if matches!(platform, Some(Platform::Mister)) {
        for entry in &mut entries {
            entry.name = display_name(&entry.name, platform).into_owned();
        }
    }
    entries
}

fn display_name<'a>(raw: &'a str, platform: Option<&Platform>) -> std::borrow::Cow<'a, str> {
    if matches!(platform, Some(Platform::Mister)) {
        if let Some(stripped) = raw.strip_prefix('_') {
            return std::borrow::Cow::Owned(stripped.to_string());
        }
    }
    std::borrow::Cow::Borrowed(raw)
}

fn leading_dir_count(entries: &[BrowseEntry]) -> i32 {
    let n = entries.iter().take_while(|e| e.is_folder()).count();
    i32::try_from(n).unwrap_or(i32::MAX)
}

fn apply_status(mut model: Pin<&mut ffi::GamesModel>, status: ResourceStatus<MediaBrowseResult>) {
    match project_status(status) {
        Projection::Pending => {
            // A new browse round started (or a Ready→Pending refetch
            // is in flight). Abort any cover gate left from the
            // previous Ready so its safety-timer callback can't race
            // with the loading=true we're about to set and clear it
            // mid-load.
            reset_cover_gate(model.as_mut());
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
        Projection::Ready(result) => {
            let eligible = model.rust().auto_nav_eligible;
            // Eligibility is consumed by the first Ready that follows
            // an eligible load. A subsequent refetch (mutation
            // invalidation) on the same `BrowseArgs` should NOT
            // re-auto-nav — the user is already inside the auto-nav
            // target's path stack and wouldn't expect to be teleported
            // again.
            model.as_mut().rust_mut().auto_nav_eligible = false;
            let platform = platform::current();
            let current_path = model.current_path.to_string();
            info!(
                entries_len = result.entries.len(),
                total_files = result.total_files,
                eligible,
                ?current_path,
                "media.browse Ready",
            );
            match decide_initial(&result, eligible, platform.as_ref(), &current_path) {
                InitialAction::AutoNavigate { path } => {
                    info!(?path, "media.browse: auto-navigating into single folder");
                    let sid = model.current_system_id.to_string();
                    let systems = if sid.is_empty() {
                        Vec::new()
                    } else {
                        vec![sid]
                    };
                    // Recurse *without* eligibility — the auto-nav
                    // target's contents are the user's view, even if
                    // by happenstance they themselves contain a
                    // single folder.
                    model.as_mut().start_initial_browse(path, systems, false);
                }
                InitialAction::Apply => {
                    apply_initial_page(model, result);
                }
            }
        }
        Projection::Errored { message } => {
            warn!("media.browse errored: {message}");
            // Errored takes us out of Ready without going through
            // `arm_cover_gate`, so any timer left armed by the prior
            // Ready needs to be torn down explicitly.
            reset_cover_gate(model.as_mut());
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

fn apply_initial_page(mut model: Pin<&mut ffi::GamesModel>, result: MediaBrowseResult) {
    let has_next_page = result.has_next_page();
    let next_cursor = result.next_cursor();
    let total = i32::try_from(result.total_files).unwrap_or(i32::MAX);
    let platform = platform::current();
    let entries = transform_entries(result.entries, platform.as_ref());
    let dir_count = leading_dir_count(&entries);
    let count = i32::try_from(entries.len()).unwrap_or(i32::MAX);
    info!(
        count,
        dir_count, total, has_next_page, "games: apply_initial_page"
    );
    enqueue_cover_fetches(&entries);
    model.as_mut().begin_reset_model();
    model.as_mut().rust_mut().entries = entries;
    model.as_mut().rust_mut().count = count;
    model.as_mut().rust_mut().next_cursor = next_cursor;
    model.as_mut().end_reset_model();
    model.as_mut().count_changed();
    model.as_mut().set_dir_count(dir_count);
    model.as_mut().set_total_files(total);
    model.as_mut().set_has_next_page(has_next_page);
    // Decide whether to release `loading` immediately or hold it until
    // covers are cached. `arm_cover_gate` flips loading off itself when
    // the page has nothing to wait on (folder-only or fully-cached
    // revisit); otherwise it leaves loading=true and arms the timer.
    arm_cover_gate(model.as_mut());
    if !model.error_message.is_empty() {
        model.as_mut().set_error_message(QString::default());
    }
    // Look-ahead prefetch: keep the user one page ahead of the highlight
    // so a page advance never triggers a visible "Loading more…" pause.
    // `fetch_more` is itself guarded by `has_next_page` and
    // `loading_more`, so a no-op call is cheap and safe.
    //
    // Look-ahead intentionally enqueues onto the same LIFO queue as
    // the visible page at the same priority. Core serializes
    // `media.image` responses at ~one per 250–400 ms; with that
    // cadence, the LIFO drain order (newest-pushed pops first) ends
    // up servicing page N+1's covers *between* page N's first burst
    // and its tail. By the time the user navigates forward, page N+1
    // is warm, while the bottom couple of tiles on page N — which
    // the user is least likely to dwell on before paginating —
    // continue to land in the background. Treating look-ahead as a
    // low-priority lane that drains *after* the visible page strictly
    // worsens this: page N then consumes the entire serial throughput
    // before page N+1 begins, which is exactly what shipped briefly
    // and looked like "covers loading slowly one at a time" with the
    // next page no longer instant on navigate. See the doc comment on
    // `MediaImageCache::queue` for the full rationale.
    if has_next_page && !model.loading_more {
        model.as_mut().fetch_more();
    }
}

fn apply_append_page(
    mut model: Pin<&mut ffi::GamesModel>,
    result: Result<MediaBrowseResult, ClientError>,
    expected_prev_cursor: Option<&str>,
) {
    // Cursor-chain check: if the model's `next_cursor` no longer
    // matches the cursor this append was advancing from, an
    // intervening `apply_initial_page` reset the chain. Appending
    // here would splice rows from the old chain onto the new one.
    if model.next_cursor.as_deref() != expected_prev_cursor {
        // Clear the in-flight cue so the UI doesn't get stuck.
        if model.loading_more {
            model.as_mut().set_loading_more(false);
        }
        return;
    }
    match result {
        Ok(result) => {
            let has_next_page = result.has_next_page();
            let next_cursor = result.next_cursor();
            let platform = platform::current();
            let entries = transform_entries(result.entries, platform.as_ref());
            let new_count = i32::try_from(entries.len()).unwrap_or(i32::MAX - model.count);
            enqueue_cover_fetches(&entries);
            if new_count > 0 {
                let first = model.count;
                let last = first.saturating_add(new_count).saturating_sub(1);
                let parent = QModelIndex::default();
                model.as_mut().begin_insert_rows(&parent, first, last);
                model.as_mut().rust_mut().entries.extend(entries);
                model.as_mut().rust_mut().count = first.saturating_add(new_count);
                model.as_mut().end_insert_rows();
                model.as_mut().count_changed();
            }
            model.as_mut().rust_mut().next_cursor = next_cursor;
            model.as_mut().set_has_next_page(has_next_page);
            // total_files isn't strictly required to update — Core
            // returns the same value for every page of the same path —
            // but Core may revise it under us if files appear/disappear
            // between cursor advances; keep it fresh.
            let total = i32::try_from(result.total_files).unwrap_or(i32::MAX);
            if model.total_files != total {
                model.as_mut().set_total_files(total);
            }
            // dir_count intentionally not touched: Core only returns
            // directory entries on page 1 (cursor == nil).
            model.as_mut().set_loading_more(false);
            // No auto-prefetch here. apply_initial_page pre-warms
            // page 2 once; subsequent pages are driven by the grid's
            // onLoadMoreRequested as the user scrolls. Chaining a
            // fetch_more here turned the look-ahead into a self-driving
            // cascade that downloaded every page back-to-back, tripping
            // Core's WebSocket rate limit on huge folders (Arcade).
        }
        Err(e) => {
            warn!("media.browse follow-up page failed: {}", e.message);
            // Surface the error so the user sees the cause; clearing
            // `loading_more` means the cue disappears even though the
            // fetch failed.
            model
                .as_mut()
                .set_error_message(QString::from(e.message.as_str()));
            model.as_mut().set_loading_more(false);
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

    use super::{
        compute_unresolved_keys, cover_key_for_with, decide_initial, display_name, entry_system_id,
        leading_dir_count, media_key_for, position_of_game_path, project_status, transform_entries,
        InitialAction, Projection,
    };
    use crate::media_image_cache::{MediaImageCache, MediaKey};
    use std::collections::HashSet;
    use zaparoo_core::media_types::{BrowseEntry, MediaBrowseResult, Pagination};
    use zaparoo_core::platform::Platform;
    use zaparoo_core::remote_resource::ResourceStatus;

    fn folder(name: &str, path: &str) -> BrowseEntry {
        BrowseEntry {
            name: name.into(),
            path: path.into(),
            entry_type: "directory".into(),
            ..BrowseEntry::default()
        }
    }

    fn root(name: &str, path: &str, system_id: &str) -> BrowseEntry {
        BrowseEntry {
            name: name.into(),
            path: path.into(),
            entry_type: "root".into(),
            system_id: system_id.into(),
            system_ids: vec![system_id.into()],
            ..BrowseEntry::default()
        }
    }

    fn media(name: &str, path: &str, system_id: &str) -> BrowseEntry {
        BrowseEntry {
            name: name.into(),
            path: path.into(),
            entry_type: "media".into(),
            system_id: system_id.into(),
            zap_script: format!("@{system_id}/{name}"),
            ..BrowseEntry::default()
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
    fn ready_carries_full_result() {
        let result = MediaBrowseResult {
            path: "/games/NES".into(),
            entries: vec![media("smb", "/games/NES/smb.nes", "NES")],
            total_files: 1,
            pagination: None,
        };
        match project_status(ResourceStatus::Ready(result)) {
            Projection::Ready(r) => {
                assert_eq!(r.entries.len(), 1);
                assert_eq!(r.total_files, 1);
            }
            other => panic!("expected Ready, got {other:?}"),
        }
    }

    #[test]
    fn errored_propagates_message() {
        match project_status(ResourceStatus::Errored {
            message: "rpc kaboom".into(),
            retrying: true,
        }) {
            Projection::Errored { message } => assert_eq!(message, "rpc kaboom"),
            other => panic!("expected Errored, got {other:?}"),
        }
    }

    #[test]
    fn decide_initial_with_single_root_eligible_returns_auto_nav() {
        let result = MediaBrowseResult {
            entries: vec![root("NES", "/roms/NES", "NES")],
            ..MediaBrowseResult::default()
        };
        assert_eq!(
            decide_initial(&result, true, None, ""),
            InitialAction::AutoNavigate {
                path: "/roms/NES".into()
            }
        );
    }

    #[test]
    fn decide_initial_with_single_directory_eligible_returns_auto_nav() {
        let result = MediaBrowseResult {
            entries: vec![folder("Games", "/roms/Shared/Games")],
            ..MediaBrowseResult::default()
        };
        assert_eq!(
            decide_initial(&result, true, None, ""),
            InitialAction::AutoNavigate {
                path: "/roms/Shared/Games".into()
            }
        );
    }

    #[test]
    fn decide_initial_with_single_folder_not_eligible_renders_as_apply_off_mister() {
        // `set_path`-driven loads must not auto-nav off MiSTer — the
        // user is explicitly navigating through folders and would lose
        // orientation otherwise.
        let result = MediaBrowseResult {
            entries: vec![folder("Sub", "/x/Sub")],
            ..MediaBrowseResult::default()
        };
        assert_eq!(
            decide_initial(&result, false, Some(&Platform::Linux), ""),
            InitialAction::Apply,
        );
        assert_eq!(
            decide_initial(&result, false, None, ""),
            InitialAction::Apply,
        );
    }

    #[test]
    fn decide_initial_with_single_folder_not_eligible_flattens_on_mister() {
        // On MiSTer, a `set_path` load that returns exactly one folder
        // also flattens — collections often unzip into nested
        // single-child folders.
        let result = MediaBrowseResult {
            entries: vec![folder("Sub", "/x/Sub")],
            ..MediaBrowseResult::default()
        };
        assert_eq!(
            decide_initial(&result, false, Some(&Platform::Mister), ""),
            InitialAction::AutoNavigate {
                path: "/x/Sub".into()
            },
        );
    }

    #[test]
    fn decide_initial_refuses_to_auto_nav_into_same_path() {
        // Cycle guard: if Core returns a folder whose path equals the
        // current browse path, recursing would loop forever (the cache
        // returns the same Ready). Render as-is instead.
        let result = MediaBrowseResult {
            entries: vec![folder("Self", "/x/Sub")],
            ..MediaBrowseResult::default()
        };
        assert_eq!(
            decide_initial(&result, false, Some(&Platform::Mister), "/x/Sub"),
            InitialAction::Apply,
        );
        assert_eq!(
            decide_initial(&result, true, None, "/x/Sub"),
            InitialAction::Apply,
        );
    }

    #[test]
    fn decide_initial_with_multi_root_returns_apply() {
        let result = MediaBrowseResult {
            entries: vec![
                root("primary", "/roms/A", "NES"),
                root("backup", "/roms/B", "NES"),
            ],
            ..MediaBrowseResult::default()
        };
        assert_eq!(
            decide_initial(&result, true, None, ""),
            InitialAction::Apply
        );
    }

    #[test]
    fn decide_initial_with_empty_returns_apply() {
        let result = MediaBrowseResult::default();
        assert_eq!(
            decide_initial(&result, true, None, ""),
            InitialAction::Apply
        );
    }

    #[test]
    fn decide_initial_with_single_media_returns_apply() {
        // A system with exactly one ROM at the root shouldn't be
        // treated as a folder; auto-nav into a media entry would
        // make no sense.
        let result = MediaBrowseResult {
            entries: vec![media("only", "/p/only", "NES")],
            ..MediaBrowseResult::default()
        };
        assert_eq!(
            decide_initial(&result, true, None, ""),
            InitialAction::Apply
        );
    }

    #[test]
    fn decide_initial_with_single_root_blank_path_renders_as_apply() {
        // A root with no `path` cannot be navigated into. Rather than
        // recurse infinitely on a malformed payload, render the entry
        // as-is and let the user see something usable.
        let result = MediaBrowseResult {
            entries: vec![root("ghost", "", "NES")],
            ..MediaBrowseResult::default()
        };
        assert_eq!(
            decide_initial(&result, true, None, ""),
            InitialAction::Apply
        );
    }

    #[test]
    fn display_name_strips_single_leading_underscore_on_mister() {
        assert_eq!(
            display_name("_Arcade", Some(&Platform::Mister)).as_ref(),
            "Arcade",
        );
    }

    #[test]
    fn display_name_only_strips_one_underscore_on_mister() {
        assert_eq!(
            display_name("__deep", Some(&Platform::Mister)).as_ref(),
            "_deep",
        );
    }

    #[test]
    fn display_name_preserves_off_mister() {
        assert_eq!(
            display_name("_Arcade", Some(&Platform::Linux)).as_ref(),
            "_Arcade",
        );
        assert_eq!(display_name("_Arcade", None).as_ref(), "_Arcade");
    }

    #[test]
    fn transform_entries_strips_underscore_only_on_mister() {
        let entries = vec![folder("_Arcade", "/A"), media("_smb", "/A/_smb", "NES")];
        let on_mister = transform_entries(entries.clone(), Some(&Platform::Mister));
        assert_eq!(on_mister[0].name, "Arcade");
        assert_eq!(on_mister[1].name, "smb");
        // Path is left alone.
        assert_eq!(on_mister[0].path, "/A");
        assert_eq!(on_mister[1].path, "/A/_smb");

        let off_mister = transform_entries(entries, Some(&Platform::Linux));
        assert_eq!(off_mister[0].name, "_Arcade");
        assert_eq!(off_mister[1].name, "_smb");
    }

    #[test]
    fn leading_dir_count_counts_only_leading_folders() {
        let entries = vec![
            folder("a", "/a"),
            folder("b", "/b"),
            media("smb", "/smb", "NES"),
            // A folder appearing after files would be a Core bug —
            // the API contract is dirs-then-files. We don't count it.
            folder("c", "/c"),
        ];
        assert_eq!(leading_dir_count(&entries), 2);
    }

    #[test]
    fn leading_dir_count_zero_when_first_is_media() {
        let entries = vec![media("smb", "/smb", "NES"), media("zelda", "/z", "NES")];
        assert_eq!(leading_dir_count(&entries), 0);
    }

    #[test]
    fn leading_dir_count_zero_on_empty() {
        assert_eq!(leading_dir_count(&[]), 0);
    }

    #[test]
    fn entry_system_id_prefers_singular_field() {
        let entry = BrowseEntry {
            system_id: "SNES".into(),
            system_ids: vec!["SNES".into(), "Stub".into()],
            ..BrowseEntry::default()
        };
        assert_eq!(entry_system_id(&entry), "SNES");
    }

    #[test]
    fn entry_system_id_falls_back_to_first_of_system_ids_for_multi_system_root() {
        let entry = BrowseEntry {
            system_id: String::new(),
            system_ids: vec!["NES".into(), "FDS".into()],
            ..BrowseEntry::default()
        };
        assert_eq!(entry_system_id(&entry), "NES");
    }

    #[test]
    fn cover_key_for_folder_returns_folder_icon() {
        let entry = folder("Games", "/x");
        assert_eq!(cover_key_for_with(&entry, None, false), "icons/Folder");
        // Folders never carry a cached cover, but explicit assertion
        // documents that even if a cache hit somehow surfaced for a
        // folder key we keep the folder glyph.
        let stale_key = MediaKey::new("NES", "/x");
        assert_eq!(
            cover_key_for_with(&entry, Some(&stale_key), true),
            "icons/Folder"
        );
    }

    #[test]
    fn cover_key_for_media_without_cache_returns_file_icon() {
        let entry = media("smb", "/p/smb", "NES");
        let key = media_key_for(&entry).expect("media has key");
        assert_eq!(cover_key_for_with(&entry, Some(&key), false), "icons/File");
    }

    #[test]
    fn cover_key_for_media_with_cache_returns_media_image_key() {
        let entry = media("smb", "/p/smb", "NES");
        let key = media_key_for(&entry).expect("media has key");
        let expected = MediaImageCache::image_key_for(&key);
        assert_eq!(cover_key_for_with(&entry, Some(&key), true), expected);
        assert!(expected.starts_with("media-image/"));
    }

    #[test]
    fn cover_key_for_unattributed_media_returns_file_icon() {
        let entry = BrowseEntry {
            entry_type: "media".into(),
            ..BrowseEntry::default()
        };
        // No system id and no path → no MediaKey.
        assert!(media_key_for(&entry).is_none());
        assert_eq!(cover_key_for_with(&entry, None, false), "icons/File");
    }

    #[test]
    fn media_key_for_skips_folders_and_unattributed_entries() {
        assert!(media_key_for(&folder("Games", "/x")).is_none());
        assert!(media_key_for(&root("NES", "/roms/NES", "NES")).is_none());
        let unattributed = BrowseEntry {
            entry_type: "media".into(),
            path: "/p".into(),
            ..BrowseEntry::default()
        };
        assert!(media_key_for(&unattributed).is_none());
        let pathless = BrowseEntry {
            entry_type: "media".into(),
            system_id: "NES".into(),
            ..BrowseEntry::default()
        };
        assert!(media_key_for(&pathless).is_none());
        let key = media_key_for(&media("smb", "/p/smb", "NES")).expect("ok");
        assert_eq!(key.system_id.as_ref(), "NES");
        assert_eq!(key.path.as_ref(), "/p/smb");
    }

    #[test]
    fn position_of_game_path_returns_index_on_case_exact_match() {
        let entries = vec![
            media("smb", "/p/smb", "NES"),
            media("zelda", "/p/zelda", "NES"),
        ];
        assert_eq!(position_of_game_path(&entries, "/p/zelda"), 1);
    }

    #[test]
    fn position_of_game_path_is_case_sensitive() {
        let entries = vec![media("smb", "/p/smb", "NES")];
        assert_eq!(position_of_game_path(&entries, "/P/SMB"), -1);
        assert_eq!(position_of_game_path(&entries, "/p/SMB"), -1);
    }

    #[test]
    fn position_of_game_path_empty_needle_returns_minus_one() {
        let entries = vec![media("smb", "/p/smb", "NES")];
        assert_eq!(position_of_game_path(&entries, ""), -1);
    }

    #[test]
    fn position_of_game_path_missing_returns_minus_one() {
        let entries = vec![media("smb", "/p/smb", "NES")];
        assert_eq!(position_of_game_path(&entries, "/p/missing"), -1);
    }

    #[test]
    fn position_of_directory_path_returns_index() {
        // The path stack restore pulls indices for directory entries
        // too, not just media; guard against future regressions
        // accidentally narrowing this to media-only.
        let entries = vec![folder("A", "/x/A"), folder("B", "/x/B")];
        assert_eq!(position_of_game_path(&entries, "/x/B"), 1);
    }

    #[test]
    fn pagination_helpers_carry_cursor_through() {
        let result = MediaBrowseResult {
            pagination: Some(Pagination {
                has_next_page: true,
                page_size: 100,
                next_cursor: Some("c".into()),
            }),
            ..MediaBrowseResult::default()
        };
        assert!(result.has_next_page());
        assert_eq!(result.next_cursor(), Some("c".into()));
    }

    #[test]
    fn pagination_helpers_default_to_no_more_pages() {
        let result = MediaBrowseResult::default();
        assert!(!result.has_next_page());
        assert_eq!(result.next_cursor(), None);
    }

    #[test]
    fn compute_unresolved_keys_folder_only_page_returns_empty() {
        let entries = vec![folder("Games", "/x/Games"), folder("Saves", "/x/Saves")];
        let unresolved = compute_unresolved_keys(&entries, |_| false, |_| false);
        assert!(unresolved.is_empty());
    }

    #[test]
    fn compute_unresolved_keys_all_cached_returns_empty() {
        let entries = vec![
            media("smb", "/p/smb", "NES"),
            media("zelda", "/p/zelda", "NES"),
        ];
        let unresolved = compute_unresolved_keys(&entries, |_| true, |_| false);
        assert!(unresolved.is_empty());
    }

    #[test]
    fn compute_unresolved_keys_mixed_returns_only_uncached() {
        let cached_path = "/p/smb";
        let entries = vec![
            media("smb", cached_path, "NES"),
            media("zelda", "/p/zelda", "NES"),
            folder("Saves", "/p/Saves"),
        ];
        let unresolved =
            compute_unresolved_keys(&entries, |k| k.path.as_ref() == cached_path, |_| false);
        let expected: HashSet<MediaKey> = [MediaKey::new("NES", "/p/zelda")].into_iter().collect();
        assert_eq!(unresolved, expected);
    }

    #[test]
    fn compute_unresolved_keys_excludes_negative_memo() {
        // Negative-memoised keys are "Core said no image" — gate must
        // not wait on them, otherwise the gate stays armed until the
        // safety timer fires every time.
        let negative_path = "/p/no-image";
        let entries = vec![
            media("smb", "/p/smb", "NES"),
            media("orphan", negative_path, "NES"),
        ];
        let unresolved =
            compute_unresolved_keys(&entries, |_| false, |k| k.path.as_ref() == negative_path);
        let expected: HashSet<MediaKey> = [MediaKey::new("NES", "/p/smb")].into_iter().collect();
        assert_eq!(unresolved, expected);
    }

    #[test]
    fn compute_unresolved_keys_skips_unattributed_entries() {
        // Browse entries without enough info to key on — folder, root,
        // unattributed media — never produce a MediaKey, so the gate
        // doesn't wait on them.
        let entries = vec![
            folder("Games", "/x/Games"),
            root("NES", "/roms/NES", "NES"),
            BrowseEntry {
                entry_type: "media".into(),
                ..BrowseEntry::default()
            },
        ];
        let unresolved = compute_unresolved_keys(&entries, |_| false, |_| false);
        assert!(unresolved.is_empty());
    }
}
