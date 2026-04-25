// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0

#![allow(
    clippy::unwrap_used,
    reason = "RwLock poisoning signals another thread panicked with the lock held; state is unrecoverable"
)]

use cxx_qt::CxxQtType;
use cxx_qt_lib::{QByteArray, QHash, QHashPair_i32_QByteArray, QModelIndex, QString, QVariant};
use std::pin::Pin;
use std::sync::{Arc, RwLock};
use zaparoo_core::endpoints::catalog::CatalogEndpoint;
use zaparoo_core::remote_resource::ResourceStatus;
use zaparoo_core::systems_catalog::CatalogData;

const ID_ROLE: i32 = 256 + 1;
const NAME_ROLE: i32 = 256 + 2;
const CATEGORY_ROLE: i32 = 256 + 3;

pub struct SystemInfo {
    pub id: String,
    pub name: String,
    pub category: String,
}

pub struct SystemsModelRust {
    systems: Vec<SystemInfo>,
    count: i32,
    current_category: QString,
    error_message: QString,
    // Shared catalog owned by the background task; model reads it on setCategory
    catalog: Arc<RwLock<Option<CatalogData>>>,
}

impl Default for SystemsModelRust {
    fn default() -> Self {
        Self {
            systems: Vec::new(),
            count: 0,
            current_category: QString::default(),
            error_message: QString::default(),
            catalog: Arc::new(RwLock::new(None)),
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
        #[qproperty(QString, current_category)]
        #[qproperty(QString, error_message)]
        type SystemsModel = super::SystemsModelRust;

        #[qinvokable]
        fn set_category(self: Pin<&mut SystemsModel>, category: QString);

        #[qinvokable]
        fn system_id_at(self: &SystemsModel, index: i32) -> QString;

        #[qinvokable]
        fn system_name_at(self: &SystemsModel, index: i32) -> QString;

        #[qinvokable]
        fn index_for_system_id(self: &SystemsModel, id: &QString) -> i32;

        #[inherit]
        #[cxx_name = "beginResetModel"]
        fn begin_reset_model(self: Pin<&mut SystemsModel>);

        #[inherit]
        #[cxx_name = "endResetModel"]
        fn end_reset_model(self: Pin<&mut SystemsModel>);

        #[cxx_name = "rowCount"]
        fn row_count(self: &SystemsModel, parent: &QModelIndex) -> i32;
        fn data(self: &SystemsModel, index: &QModelIndex, role: i32) -> QVariant;
        #[cxx_name = "roleNames"]
        fn role_names(self: &SystemsModel) -> QHash_i32_QByteArray;
    }

    impl cxx_qt::Threading for SystemsModel {}
    impl cxx_qt::Initialize for SystemsModel {}
}

crate::bind_to_endpoint! {
    for ffi::SystemsModel,
    endpoint = CatalogEndpoint,
    args = (),
    select = project,
    apply = apply_state,
}

/// Pull the two pieces this model cares about out of the unified
/// `ResourceStatus`: the catalog payload (only present on `Ready`) and
/// the surfaced error message (empty unless `Errored`).
fn project(status: &ResourceStatus<CatalogData>) -> (Option<CatalogData>, String) {
    match status {
        ResourceStatus::Ready(data) => (Some(data.clone()), String::new()),
        ResourceStatus::Errored { message, .. } => (None, message.clone()),
        ResourceStatus::Idle | ResourceStatus::Loading => (None, String::new()),
    }
}

fn apply_state(mut model: Pin<&mut ffi::SystemsModel>, (data, err): (Option<CatalogData>, String)) {
    if let Some(data) = data {
        // Rebuild visible rows directly from `data` — if the user has
        // already picked a category — *before* moving it into the
        // shared catalog cache, so we don't have to re-acquire the
        // read lock to look at what we just wrote.
        let cat = model.rust().current_category.to_string();
        if !cat.is_empty() {
            let systems = data.systems_by_category(&cat);
            let count = systems.len() as i32;
            let rows: Vec<SystemInfo> = systems
                .into_iter()
                .map(|s| SystemInfo {
                    id: s.id,
                    name: s.name,
                    category: s.category,
                })
                .collect();
            model.as_mut().begin_reset_model();
            model.as_mut().rust_mut().systems = rows;
            model.as_mut().rust_mut().count = count;
            model.as_mut().end_reset_model();
            model.as_mut().count_changed();
        }
        // Refresh the shared catalog cache that `set_category` reads
        // so subsequent category switches see the latest data.
        *model.rust().catalog.write().unwrap() = Some(data);
    }
    let qerr = QString::from(err.as_str());
    if model.error_message != qerr {
        model.as_mut().set_error_message(qerr);
    }
}

impl ffi::SystemsModel {
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
        let s = &self.systems[index.row() as usize];
        match role {
            ID_ROLE => QVariant::from(&QString::from(s.id.as_str())),
            NAME_ROLE => QVariant::from(&QString::from(s.name.as_str())),
            CATEGORY_ROLE => QVariant::from(&QString::from(s.category.as_str())),
            _ => QVariant::default(),
        }
    }

    fn role_names(&self) -> QHash<QHashPair_i32_QByteArray> {
        let mut h = QHash::<QHashPair_i32_QByteArray>::default();
        h.insert(ID_ROLE, QByteArray::from("id"));
        h.insert(NAME_ROLE, QByteArray::from("name"));
        h.insert(CATEGORY_ROLE, QByteArray::from("category"));
        h
    }

    fn set_category(mut self: Pin<&mut Self>, category: QString) {
        let cat = category.to_string();
        let systems = self
            .rust()
            .catalog
            .read()
            .unwrap()
            .as_ref()
            .map(|c| c.systems_by_category(&cat))
            .unwrap_or_default();
        let count = systems.len() as i32;
        let rows: Vec<SystemInfo> = systems
            .into_iter()
            .map(|s| SystemInfo {
                id: s.id,
                name: s.name,
                category: s.category,
            })
            .collect();
        self.as_mut().begin_reset_model();
        self.as_mut().rust_mut().systems = rows;
        self.as_mut().rust_mut().count = count;
        self.as_mut().rust_mut().current_category = category;
        self.as_mut().end_reset_model();
        self.as_mut().count_changed();
        self.as_mut().current_category_changed();
    }

    fn system_id_at(&self, index: i32) -> QString {
        if index < 0 || index >= self.count {
            return QString::default();
        }
        QString::from(self.systems[index as usize].id.as_str())
    }

    fn system_name_at(&self, index: i32) -> QString {
        if index < 0 || index >= self.count {
            return QString::default();
        }
        QString::from(self.systems[index as usize].name.as_str())
    }

    fn index_for_system_id(&self, id: &QString) -> i32 {
        let needle = id.to_string();
        if needle.is_empty() {
            return -1;
        }
        self.systems
            .iter()
            .position(|s| s.id == needle)
            .map_or(-1, |i| i as i32)
    }
}
