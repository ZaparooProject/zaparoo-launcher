// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//
// `Browse.RecentsModel` — flat list of recently-played media, surfaced
// from Core's `media.history` endpoint.
//
// Two paths into the model:
//
//   * `bind_to_endpoint!` seeds page 1 from `MediaHistoryEndpoint` so
//     a screen flip into Recents has data on the first paint when the
//     resource is already `Ready`. The fixed args (`limit = 25`, no
//     `systems` filter) match what the UI requests; if a future filter
//     is added, switch to a per-arg pattern like `GamesModel`.
//
//   * `fetch_more()` — cursor-driven follow-ups bypass the cache and
//     call `Client::media_history` directly, just like games. The
//     model owns the cursor, the in-flight `loading_more` debounce,
//     and the seq ticket that disarms stale callbacks.
//
// History is flat (no folder navigation, no auto-nav) so this model
// stays a fraction of the size of `GamesModel`. Card-write isn't wired
// here yet — recents launches by `run`-ing the entry's launcher route.

use crate::models::{global_runtime, global_store};
use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::{QByteArray, QHash, QHashPair_i32_QByteArray, QModelIndex, QString, QVariant};
use std::pin::Pin;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use tracing::warn;
use zaparoo_core::client::ClientError;
use zaparoo_core::endpoints::media_history::{HistoryArgs, MediaHistoryEndpoint};
use zaparoo_core::endpoints::run::RunMutation;
use zaparoo_core::media_types::{
    MediaHistoryEntry, MediaHistoryParams, MediaHistoryResult, RunParams,
};
use zaparoo_core::remote_resource::ResourceStatus;

const NAME_ROLE: i32 = 256 + 1;
const PATH_ROLE: i32 = 256 + 2;
const SYSTEM_ID_ROLE: i32 = 256 + 3;
const COVER_KEY_ROLE: i32 = 256 + 4;
const LAUNCHER_ID_ROLE: i32 = 256 + 5;

// Page size for the initial load and every cursor follow-up. Core caps
// `limit` at 100; history rows are tiny (one tile + one caption per row)
// so 25 fills several screens of the recents grid without stressing the
// over-the-wire payload. Bumping this only saves a round trip — it
// doesn't change the UI cap.
const PAGE_SIZE: u32 = 25;

#[derive(Default)]
pub struct RecentsModelRust {
    entries: Vec<MediaHistoryEntry>,
    count: i32,
    loading: bool,
    loading_more: bool,
    error_message: QString,
    has_next_page: bool,
    next_cursor: Option<String>,
    // Bumped whenever the cursor chain is reset by an initial
    // `apply_state` so any in-flight `fetch_more` callback can detect
    // its append no longer belongs to the current chain.
    seq: Arc<AtomicU64>,
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
        #[qproperty(bool, loading_more)]
        #[qproperty(QString, error_message)]
        #[qproperty(bool, has_next_page)]
        type RecentsModel = super::RecentsModelRust;

        #[qinvokable]
        fn fetch_more(self: Pin<&mut RecentsModel>);

        #[qinvokable]
        fn launch_at(self: Pin<&mut RecentsModel>, index: i32);

        #[qinvokable]
        fn name_at(self: &RecentsModel, index: i32) -> QString;

        #[qinvokable]
        fn path_at(self: &RecentsModel, index: i32) -> QString;

        #[qinvokable]
        fn index_for_path(self: &RecentsModel, path: &QString) -> i32;

        #[inherit]
        #[cxx_name = "beginResetModel"]
        fn begin_reset_model(self: Pin<&mut RecentsModel>);

        #[inherit]
        #[cxx_name = "endResetModel"]
        fn end_reset_model(self: Pin<&mut RecentsModel>);

        #[inherit]
        #[cxx_name = "beginInsertRows"]
        fn begin_insert_rows(
            self: Pin<&mut RecentsModel>,
            parent: &QModelIndex,
            first: i32,
            last: i32,
        );

        #[inherit]
        #[cxx_name = "endInsertRows"]
        fn end_insert_rows(self: Pin<&mut RecentsModel>);

        #[cxx_name = "rowCount"]
        fn row_count(self: &RecentsModel, parent: &QModelIndex) -> i32;
        fn data(self: &RecentsModel, index: &QModelIndex, role: i32) -> QVariant;
        #[cxx_name = "roleNames"]
        fn role_names(self: &RecentsModel) -> QHash_i32_QByteArray;
    }

    impl cxx_qt::Threading for RecentsModel {}
    impl cxx_qt::Initialize for RecentsModel {}
}

crate::bind_to_endpoint! {
    for ffi::RecentsModel,
    endpoint = MediaHistoryEndpoint,
    args = HistoryArgs::new(Vec::new(), PAGE_SIZE),
    select = project,
    apply = apply_state,
}

/// Snapshot of a single page that `apply_state` can write onto the
/// model. Carried by value so the closure is `Send + 'static` for the
/// `qt_thread` queue.
type PageSnapshot = (Vec<MediaHistoryEntry>, bool, Option<String>);

/// Project the resource status onto an `(Option<PageSnapshot>, error)`
/// tuple. `Idle`/`Loading` map to the same `(None, "")` shape so the
/// apply path can decide on its own whether to show the spinner.
fn project(status: &ResourceStatus<MediaHistoryResult>) -> (Option<PageSnapshot>, String) {
    match status {
        ResourceStatus::Ready(data) => (
            Some((
                data.entries.clone(),
                data.has_next_page(),
                data.next_cursor(),
            )),
            String::new(),
        ),
        ResourceStatus::Errored { message, .. } => (None, message.clone()),
        ResourceStatus::Idle | ResourceStatus::Loading => (None, String::new()),
    }
}

fn apply_state(
    mut model: Pin<&mut ffi::RecentsModel>,
    (data, err): (Option<PageSnapshot>, String),
) {
    if let Some((entries, has_next_page, next_cursor)) = data {
        // A fresh initial page resets the cursor chain — bump `seq` so
        // any in-flight `fetch_more` sees a stale ticket and bails.
        model.as_mut().rust_mut().seq.fetch_add(1, Ordering::SeqCst);
        let count = i32::try_from(entries.len()).unwrap_or(i32::MAX);
        model.as_mut().begin_reset_model();
        model.as_mut().rust_mut().entries = entries;
        model.as_mut().rust_mut().count = count;
        model.as_mut().rust_mut().next_cursor = next_cursor;
        model.as_mut().end_reset_model();
        model.as_mut().count_changed();
        if model.has_next_page != has_next_page {
            model.as_mut().set_has_next_page(has_next_page);
        }
        if model.loading {
            model.as_mut().set_loading(false);
        }
        if model.loading_more {
            model.as_mut().set_loading_more(false);
        }
        // Look-ahead prefetch: warm page 2 so the first scroll past the
        // initial page doesn't surface a "Loading more…" cue. `fetch_more`
        // is itself guarded by `has_next_page` and `loading_more`.
        if has_next_page {
            model.as_mut().fetch_more();
        }
    } else if err.is_empty() {
        // Pending (Idle/Loading): show the spinner; don't touch entries.
        // Disarm pagination so a grid scroll during a refetch doesn't
        // fire `fetch_more` against a stale cursor — `has_next_page`
        // is re-set when Ready lands.
        if !model.loading {
            model.as_mut().set_loading(true);
        }
        if model.has_next_page {
            model.as_mut().set_has_next_page(false);
        }
    } else {
        if model.loading {
            model.as_mut().set_loading(false);
        }
        if model.has_next_page {
            model.as_mut().set_has_next_page(false);
        }
    }
    let qerr = QString::from(err.as_str());
    if model.error_message != qerr {
        model.as_mut().set_error_message(qerr);
    }
}

impl ffi::RecentsModel {
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
            NAME_ROLE => QVariant::from(&QString::from(entry.media_name.as_str())),
            PATH_ROLE => QVariant::from(&QString::from(entry.media_path.as_str())),
            SYSTEM_ID_ROLE => QVariant::from(&QString::from(entry.system_id.as_str())),
            COVER_KEY_ROLE => QVariant::from(&QString::from(cover_key_for(entry).as_str())),
            LAUNCHER_ID_ROLE => QVariant::from(&QString::from(entry.launcher_id.as_str())),
            _ => QVariant::default(),
        }
    }

    fn role_names(&self) -> QHash<QHashPair_i32_QByteArray> {
        let mut h = QHash::<QHashPair_i32_QByteArray>::default();
        h.insert(NAME_ROLE, QByteArray::from("name"));
        h.insert(PATH_ROLE, QByteArray::from("path"));
        h.insert(SYSTEM_ID_ROLE, QByteArray::from("systemId"));
        h.insert(COVER_KEY_ROLE, QByteArray::from("coverKey"));
        h.insert(LAUNCHER_ID_ROLE, QByteArray::from("launcherId"));
        h
    }

    fn fetch_more(mut self: Pin<&mut Self>) {
        if self.loading_more || !self.has_next_page {
            return;
        }
        let cursor = self.next_cursor.clone();
        let expected_prev_cursor = cursor.clone();
        let seq = self.rust().seq.clone();
        let ticket = seq.load(Ordering::SeqCst);
        self.as_mut().set_loading_more(true);
        let qt_thread = self.qt_thread();
        let store = global_store();
        global_runtime().spawn(async move {
            let result = store
                .client()
                .media_history(MediaHistoryParams {
                    limit: Some(PAGE_SIZE),
                    cursor,
                    systems: Vec::new(),
                    fuzzy_system: Some(true),
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
        let text = launch_text_for(entry);
        if text.is_empty() {
            return;
        }
        let name = entry.media_name.clone();
        let store = global_store();
        global_runtime().spawn(async move {
            if let Err(e) = store.run_mutation::<RunMutation>(RunParams { text }).await {
                warn!("run failed for {name}: {}", e.message);
            }
        });
    }

    fn name_at(&self, index: i32) -> QString {
        if index < 0 || index >= self.count {
            return QString::default();
        }
        QString::from(self.entries[index as usize].media_name.as_str())
    }

    fn path_at(&self, index: i32) -> QString {
        if index < 0 || index >= self.count {
            return QString::default();
        }
        QString::from(self.entries[index as usize].media_path.as_str())
    }

    fn index_for_path(&self, path: &QString) -> i32 {
        position_of_path(&self.entries, &path.to_string())
    }
}

fn cover_key_for(entry: &MediaHistoryEntry) -> String {
    if entry.system_id.is_empty() {
        return "icons/File".to_string();
    }
    format!("systems/{}", entry.system_id)
}

/// Build the `text` payload sent to Core's `run` for a history entry.
/// History entries don't carry a synthesised `zap_script` (Core surfaces
/// only the raw fields), so reproduce the canonical
/// `**launch.system:<launcher>,<path>` shape that browse entries use.
/// Falls back to the bare `mediaPath` if `launcherId` is missing — Core
/// can usually still resolve a path-only launch.
fn launch_text_for(entry: &MediaHistoryEntry) -> String {
    if entry.launcher_id.is_empty() {
        return entry.media_path.clone();
    }
    if entry.media_path.is_empty() {
        return String::new();
    }
    format!("**launch.system:{},{}", entry.launcher_id, entry.media_path)
}

fn position_of_path(entries: &[MediaHistoryEntry], needle: &str) -> i32 {
    if needle.is_empty() {
        return -1;
    }
    entries
        .iter()
        .position(|e| e.media_path == needle)
        .map_or(-1, |i| i as i32)
}

fn apply_append_page(
    mut model: Pin<&mut ffi::RecentsModel>,
    result: Result<MediaHistoryResult, ClientError>,
    expected_prev_cursor: Option<&str>,
) {
    if model.next_cursor.as_deref() != expected_prev_cursor {
        if model.loading_more {
            model.as_mut().set_loading_more(false);
        }
        return;
    }
    match result {
        Ok(result) => {
            let has_next_page = result.has_next_page();
            let next_cursor = result.next_cursor();
            let new_count = i32::try_from(result.entries.len()).unwrap_or(i32::MAX - model.count);
            if new_count > 0 {
                let first = model.count;
                let last = first.saturating_add(new_count).saturating_sub(1);
                let parent = QModelIndex::default();
                model.as_mut().begin_insert_rows(&parent, first, last);
                model.as_mut().rust_mut().entries.extend(result.entries);
                model.as_mut().rust_mut().count = first.saturating_add(new_count);
                model.as_mut().end_insert_rows();
                model.as_mut().count_changed();
            }
            model.as_mut().rust_mut().next_cursor = next_cursor;
            model.as_mut().set_has_next_page(has_next_page);
            model.as_mut().set_loading_more(false);
        }
        Err(e) => {
            warn!("media.history follow-up page failed: {}", e.message);
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

    use super::{cover_key_for, launch_text_for, position_of_path, project};
    use zaparoo_core::media_types::{MediaHistoryEntry, MediaHistoryResult, Pagination};
    use zaparoo_core::remote_resource::ResourceStatus;

    fn entry(name: &str, path: &str, system_id: &str, launcher_id: &str) -> MediaHistoryEntry {
        MediaHistoryEntry {
            media_name: name.into(),
            media_path: path.into(),
            system_id: system_id.into(),
            launcher_id: launcher_id.into(),
            ..MediaHistoryEntry::default()
        }
    }

    #[test]
    fn cover_key_uses_system_folder_for_known_system() {
        let e = entry("smb", "/p/smb", "NES", "NES");
        assert_eq!(cover_key_for(&e), "systems/NES");
    }

    #[test]
    fn cover_key_falls_back_to_file_glyph_when_system_missing() {
        let e = entry("orphan", "/p/orphan", "", "");
        assert_eq!(cover_key_for(&e), "icons/File");
    }

    #[test]
    fn launch_text_prefers_launch_system_when_launcher_known() {
        let e = entry("smb", "/p/smb.nes", "NES", "NES");
        assert_eq!(launch_text_for(&e), "**launch.system:NES,/p/smb.nes");
    }

    #[test]
    fn launch_text_falls_back_to_path_when_launcher_missing() {
        let e = entry("smb", "/p/smb.nes", "NES", "");
        assert_eq!(launch_text_for(&e), "/p/smb.nes");
    }

    #[test]
    fn launch_text_is_empty_when_path_missing_and_launcher_present() {
        // A history row with a launcher id but no path is malformed —
        // running an empty path or a `**launch.system:NES,` would just
        // confuse Core. Empty here suppresses the run entirely.
        let e = entry("ghost", "", "NES", "NES");
        assert_eq!(launch_text_for(&e), "");
    }

    #[test]
    fn position_of_path_returns_index_on_match() {
        let entries = vec![
            entry("smb", "/p/smb", "NES", "NES"),
            entry("zelda", "/p/zelda", "NES", "NES"),
        ];
        assert_eq!(position_of_path(&entries, "/p/zelda"), 1);
    }

    #[test]
    fn position_of_path_empty_needle_returns_minus_one() {
        let entries = vec![entry("smb", "/p/smb", "NES", "NES")];
        assert_eq!(position_of_path(&entries, ""), -1);
    }

    #[test]
    fn position_of_path_missing_returns_minus_one() {
        let entries = vec![entry("smb", "/p/smb", "NES", "NES")];
        assert_eq!(position_of_path(&entries, "/missing"), -1);
    }

    #[test]
    fn project_idle_yields_empty_pending() {
        let (page, err) = project(&ResourceStatus::Idle);
        assert!(page.is_none());
        assert!(err.is_empty());
    }

    #[test]
    fn project_loading_yields_empty_pending() {
        let (page, err) = project(&ResourceStatus::Loading);
        assert!(page.is_none());
        assert!(err.is_empty());
    }

    #[test]
    fn project_ready_carries_entries_and_pagination() {
        let result = MediaHistoryResult {
            entries: vec![entry("smb", "/p/smb", "NES", "NES")],
            pagination: Some(Pagination {
                has_next_page: true,
                page_size: 25,
                next_cursor: Some("cursor-2".into()),
            }),
        };
        let (page, err) = project(&ResourceStatus::Ready(result));
        assert!(err.is_empty());
        let (entries, has_next, cursor) = page.expect("ready snapshot");
        assert_eq!(entries.len(), 1);
        assert_eq!(entries[0].media_path, "/p/smb");
        assert!(has_next);
        assert_eq!(cursor.as_deref(), Some("cursor-2"));
    }

    #[test]
    fn project_ready_without_pagination_disarms_next_page() {
        // Core docs say pagination is omitted when no entries are
        // returned. The projection must surface that as `has_next_page
        // = false` so the model disarms `fetch_more` instead of looping
        // on a stale cursor.
        let result = MediaHistoryResult::default();
        let (page, err) = project(&ResourceStatus::Ready(result));
        assert!(err.is_empty());
        let (entries, has_next, cursor) = page.expect("ready snapshot");
        assert!(entries.is_empty());
        assert!(!has_next);
        assert!(cursor.is_none());
    }

    #[test]
    fn project_errored_carries_message_with_no_snapshot() {
        let (page, err) = project(&ResourceStatus::Errored {
            message: "rpc kaboom".into(),
            retrying: true,
        });
        assert!(page.is_none());
        assert_eq!(err, "rpc kaboom");
    }
}
