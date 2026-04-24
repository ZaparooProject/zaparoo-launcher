// Zaparoo Launcher
// Copyright (c) 2026 The Zaparoo Project Contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::{QByteArray, QHash, QHashPair_i32_QByteArray, QModelIndex, QString, QVariant};
use std::pin::Pin;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use zaparoo_core::media_types::{MediaItem, MediaSearchParams, RunParams};

const NAME_ROLE: i32 = 256 + 1;
const PATH_ROLE: i32 = 256 + 2;
const ZAP_SCRIPT_ROLE: i32 = 256 + 3;
const SYSTEM_ID_ROLE: i32 = 256 + 4;

pub struct GamesModelRust {
    items: Vec<MediaItem>,
    count: i32,
    loading: bool,
    error_message: QString,
    has_next_page: bool,
    current_system_id: QString,
    selected_index: i32,
    seq: Arc<AtomicU64>,
}

impl Default for GamesModelRust {
    fn default() -> Self {
        Self {
            items: Vec::new(),
            count: 0,
            loading: false,
            error_message: QString::default(),
            has_next_page: false,
            current_system_id: QString::default(),
            selected_index: 0,
            seq: Arc::new(AtomicU64::new(0)),
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
        type GamesModel = super::GamesModelRust;

        #[qinvokable]
        fn set_system(self: Pin<&mut GamesModel>, system_id: QString);

        #[qinvokable]
        fn launch_at(self: Pin<&mut GamesModel>, index: i32);

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
            _ => QVariant::default(),
        }
    }

    fn role_names(&self) -> QHash<QHashPair_i32_QByteArray> {
        let mut h = QHash::<QHashPair_i32_QByteArray>::default();
        h.insert(NAME_ROLE, QByteArray::from("name"));
        h.insert(PATH_ROLE, QByteArray::from("path"));
        h.insert(ZAP_SCRIPT_ROLE, QByteArray::from("zapScript"));
        h.insert(SYSTEM_ID_ROLE, QByteArray::from("systemId"));
        h
    }

    fn set_system(mut self: Pin<&mut Self>, system_id: QString) {
        use crate::models::{global_client, global_runtime};
        use tracing::warn;

        let sid = system_id.to_string();
        if sid == self.current_system_id.to_string() && !self.items.is_empty() {
            return;
        }

        self.as_mut().set_current_system_id(system_id);
        self.as_mut().set_loading(true);
        self.as_mut().set_error_message(QString::default());

        let seq = self.rust().seq.clone();
        let ticket = seq.fetch_add(1, Ordering::SeqCst) + 1;
        let client = global_client();
        let qt_thread = self.qt_thread();

        global_runtime().spawn(async move {
            let result = client
                .media_search(MediaSearchParams {
                    systems: vec![sid.clone()],
                    max_results: 100,
                })
                .await;

            let _ = qt_thread.queue(move |mut model| {
                if seq.load(Ordering::SeqCst) != ticket {
                    return;
                }
                model.as_mut().set_loading(false);
                match result {
                    Ok(r) => {
                        if r.has_next_page {
                            warn!("games list for {sid} has >100 results; only first page shown");
                        }
                        let count = r.results.len() as i32;
                        model.as_mut().begin_reset_model();
                        model.as_mut().rust_mut().items = r.results;
                        model.as_mut().rust_mut().count = count;
                        model.as_mut().end_reset_model();
                        model.as_mut().count_changed();
                        model.as_mut().set_has_next_page(r.has_next_page);
                    }
                    Err(e) => {
                        model
                            .as_mut()
                            .set_error_message(QString::from(e.message.as_str()));
                    }
                }
            });
        });
    }

    fn launch_at(self: Pin<&mut Self>, index: i32) {
        use crate::models::{global_client, global_runtime};
        use tracing::warn;

        if index < 0 || index >= self.count {
            return;
        }
        let item = &self.items[index as usize];
        if item.zap_script.is_empty() {
            return;
        }
        let text = item.zap_script.clone();
        let name = item.name.clone();
        let client = global_client();
        global_runtime().spawn(async move {
            if let Err(e) = client.run(RunParams { text }).await {
                warn!("run failed for {name}: {}", e.message);
            }
        });
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
        let needle = path.to_string();
        if needle.is_empty() {
            return -1;
        }
        self.items
            .iter()
            .position(|item| item.path == needle)
            .map_or(-1, |i| i as i32)
    }

    fn set_selected_index(mut self: Pin<&mut Self>, index: i32) {
        self.as_mut().rust_mut().selected_index = index;
    }
}
