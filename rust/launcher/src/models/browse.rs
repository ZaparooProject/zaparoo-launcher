// Zaparoo Launcher
// Copyright (c) 2026 The Zaparoo Project Contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//
// Minimal BrowseModel stub — dormant, kept to satisfy the Zaparoo.Browse QML
// module registration. Full implementation deferred to a future phase.

use cxx_qt_lib::{QByteArray, QHash, QHashPair_i32_QByteArray, QModelIndex, QString, QVariant};
use std::pin::Pin;

#[derive(Default)]
pub struct BrowseModelRust {
    count: i32,
    current_path: QString,
    can_go_back: bool,
    loading: bool,
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
        #[qproperty(QString, current_path)]
        #[qproperty(bool, can_go_back)]
        #[qproperty(bool, loading)]
        #[qproperty(QString, error_message)]
        type BrowseModel = super::BrowseModelRust;

        #[qinvokable]
        fn enter(self: Pin<&mut BrowseModel>, index: i32);

        #[qinvokable]
        fn go_back(self: Pin<&mut BrowseModel>);

        #[qinvokable]
        fn refresh(self: Pin<&mut BrowseModel>);

        #[qinvokable]
        fn launch_at(self: Pin<&mut BrowseModel>, index: i32);

        #[qinvokable]
        fn set_selected_index(self: Pin<&mut BrowseModel>, index: i32);

        #[qinvokable]
        fn name_at(self: &BrowseModel, index: i32) -> QString;

        #[qinvokable]
        fn is_folder_at(self: &BrowseModel, index: i32) -> bool;

        #[cxx_name = "rowCount"]
        fn row_count(self: &BrowseModel, parent: &QModelIndex) -> i32;
        fn data(self: &BrowseModel, index: &QModelIndex, role: i32) -> QVariant;
        #[cxx_name = "roleNames"]
        fn role_names(self: &BrowseModel) -> QHash_i32_QByteArray;
    }
}

impl ffi::BrowseModel {
    fn row_count(&self, parent: &QModelIndex) -> i32 {
        if parent.is_valid() {
            0
        } else {
            self.count
        }
    }

    fn data(&self, _index: &QModelIndex, _role: i32) -> QVariant {
        QVariant::default()
    }

    fn role_names(&self) -> QHash<QHashPair_i32_QByteArray> {
        let mut h = QHash::<QHashPair_i32_QByteArray>::default();
        h.insert(256 + 1, QByteArray::from("name"));
        h.insert(256 + 2, QByteArray::from("path"));
        h.insert(256 + 3, QByteArray::from("type"));
        h.insert(256 + 4, QByteArray::from("fileCount"));
        h.insert(256 + 5, QByteArray::from("isFolder"));
        h
    }

    fn enter(self: Pin<&mut Self>, _index: i32) {}
    fn go_back(self: Pin<&mut Self>) {}
    fn refresh(self: Pin<&mut Self>) {}
    fn launch_at(self: Pin<&mut Self>, _index: i32) {}
    fn set_selected_index(self: Pin<&mut Self>, _index: i32) {}

    fn name_at(&self, _index: i32) -> QString {
        QString::default()
    }

    fn is_folder_at(&self, _index: i32) -> bool {
        false
    }
}
