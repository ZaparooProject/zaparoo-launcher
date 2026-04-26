// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0

use cxx_qt::CxxQtType;
use cxx_qt_lib::{QByteArray, QHash, QHashPair_i32_QByteArray, QModelIndex, QString, QVariant};
use std::pin::Pin;
use zaparoo_core::endpoints::catalog::CatalogEndpoint;
use zaparoo_core::remote_resource::ResourceStatus;
use zaparoo_core::systems_catalog::CatalogData;

const NAME_ROLE: i32 = 256 + 1; // Qt::UserRole + 1

#[derive(Default)]
pub struct CategoriesModelRust {
    categories: Vec<String>,
    count: i32,
    error_message: QString,
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
        #[qproperty(QString, error_message)]
        type CategoriesModel = super::CategoriesModelRust;

        #[qinvokable]
        fn category_at(self: &CategoriesModel, index: i32) -> QString;

        #[qinvokable]
        fn index_for_category(self: &CategoriesModel, name: &QString) -> i32;

        #[inherit]
        #[cxx_name = "beginResetModel"]
        fn begin_reset_model(self: Pin<&mut CategoriesModel>);

        #[inherit]
        #[cxx_name = "endResetModel"]
        fn end_reset_model(self: Pin<&mut CategoriesModel>);

        // QAbstractListModel virtual overrides
        #[cxx_name = "rowCount"]
        fn row_count(self: &CategoriesModel, parent: &QModelIndex) -> i32;
        fn data(self: &CategoriesModel, index: &QModelIndex, role: i32) -> QVariant;
        #[cxx_name = "roleNames"]
        fn role_names(self: &CategoriesModel) -> QHash_i32_QByteArray;
    }

    impl cxx_qt::Threading for CategoriesModel {}
    impl cxx_qt::Initialize for CategoriesModel {}
}

crate::bind_to_endpoint! {
    for ffi::CategoriesModel,
    endpoint = CatalogEndpoint,
    args = (),
    select = project,
    apply = apply_state,
}

/// Pull the two pieces this model cares about out of the unified
/// `ResourceStatus`: the category list (only present on `Ready`) and the
/// surfaced error message (empty unless `Errored`).
fn project(status: &ResourceStatus<CatalogData>) -> (Option<Vec<String>>, String) {
    match status {
        ResourceStatus::Ready(data) => (Some(data.categories.clone()), String::new()),
        ResourceStatus::Errored { message, .. } => (None, message.clone()),
        ResourceStatus::Idle | ResourceStatus::Loading => (None, String::new()),
    }
}

fn apply_state(
    mut model: Pin<&mut ffi::CategoriesModel>,
    (categories, err): (Option<Vec<String>>, String),
) {
    if let Some(categories) = categories {
        let count = categories.len() as i32;
        model.as_mut().begin_reset_model();
        model.as_mut().rust_mut().categories = categories;
        model.as_mut().rust_mut().count = count;
        model.as_mut().end_reset_model();
        model.as_mut().count_changed();
    }
    let qerr = QString::from(err.as_str());
    if model.error_message != qerr {
        model.as_mut().set_error_message(qerr);
    }
}

impl ffi::CategoriesModel {
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
        if role == NAME_ROLE {
            let s = &self.categories[index.row() as usize];
            QVariant::from(&QString::from(s.as_str()))
        } else {
            QVariant::default()
        }
    }

    fn role_names(&self) -> QHash<QHashPair_i32_QByteArray> {
        let mut hash = QHash::<QHashPair_i32_QByteArray>::default();
        hash.insert(NAME_ROLE, QByteArray::from("name"));
        hash
    }

    fn category_at(&self, index: i32) -> QString {
        if index < 0 || index >= self.count {
            return QString::default();
        }
        QString::from(self.categories[index as usize].as_str())
    }

    fn index_for_category(&self, name: &QString) -> i32 {
        let needle = name.to_string();
        if needle.is_empty() {
            return -1;
        }
        self.categories
            .iter()
            .position(|c| c == &needle)
            .map_or(-1, |i| i as i32)
    }
}
