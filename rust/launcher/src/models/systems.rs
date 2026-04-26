// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0

use cxx_qt::CxxQtType;
use cxx_qt_lib::{QByteArray, QHash, QHashPair_i32_QByteArray, QModelIndex, QString, QVariant};
use std::pin::Pin;
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

#[derive(Default)]
pub struct SystemsModelRust {
    systems: Vec<SystemInfo>,
    count: i32,
    current_category: QString,
    error_message: QString,
    // Last-known-good catalog. Updated by `apply_state` on every
    // `Ready`; never cleared on `Loading`/`Errored`. Lets
    // `set_category` keep populating rows during a transient refetch
    // instead of wiping the carousel until the catalog returns to
    // `Ready`.
    last_ready: Option<CatalogData>,
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

/// Filter `catalog`'s systems to the named category and re-shape them
/// into the local row type. Returns empty when `catalog` is `None` so
/// `set_category` and `apply_state` share one filter+map definition.
fn rows_for_category(catalog: Option<&CatalogData>, cat: &str) -> Vec<SystemInfo> {
    catalog.map_or_else(Vec::new, |c| {
        c.systems_by_category(cat)
            .into_iter()
            .map(|s| SystemInfo {
                id: s.id,
                name: s.name,
                category: s.category,
            })
            .collect()
    })
}

fn apply_state(mut model: Pin<&mut ffi::SystemsModel>, (data, err): (Option<CatalogData>, String)) {
    if let Some(data) = data {
        let cat = model.rust().current_category.to_string();
        if !cat.is_empty() {
            let rows = rows_for_category(Some(&data), &cat);
            let count = rows.len() as i32;
            model.as_mut().begin_reset_model();
            model.as_mut().rust_mut().systems = rows;
            model.as_mut().rust_mut().count = count;
            model.as_mut().end_reset_model();
            model.as_mut().count_changed();
        }
        model.as_mut().rust_mut().last_ready = Some(data);
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
        // Read from `last_ready` rather than the live `ResourceStatus`
        // so a transient `Loading` (a refetch in flight) doesn't wipe
        // the carousel between the user's category change and the
        // refetch completing.
        let rows = rows_for_category(self.rust().last_ready.as_ref(), &cat);
        let count = rows.len() as i32;
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

#[cfg(test)]
mod tests {
    #![allow(
        clippy::expect_used,
        clippy::unwrap_used,
        clippy::panic,
        reason = "tests should fail-fast on unexpected errors"
    )]

    use super::{project, rows_for_category};
    use zaparoo_core::media_types::SystemInfo as MediaSystemInfo;
    use zaparoo_core::remote_resource::ResourceStatus;
    use zaparoo_core::systems_catalog::CatalogData;

    fn sys(id: &str, name: &str, category: &str) -> MediaSystemInfo {
        MediaSystemInfo {
            id: id.into(),
            name: name.into(),
            category: category.into(),
        }
    }

    fn catalog_with(systems: Vec<MediaSystemInfo>) -> CatalogData {
        CatalogData {
            systems,
            categories: Vec::new(),
        }
    }

    #[test]
    fn idle_projects_to_no_data_no_error() {
        let (data, err) = project(&ResourceStatus::Idle);
        assert!(data.is_none());
        assert!(err.is_empty());
    }

    #[test]
    fn loading_projects_to_no_data_no_error() {
        let (data, err) = project(&ResourceStatus::Loading);
        assert!(data.is_none());
        assert!(err.is_empty());
    }

    #[test]
    fn ready_projects_data_and_no_error() {
        let catalog = catalog_with(vec![sys("smb", "SMB", "Consoles")]);
        let (data, err) = project(&ResourceStatus::Ready(catalog));
        assert!(data.is_some());
        assert!(err.is_empty());
        assert_eq!(data.unwrap().systems.len(), 1);
    }

    #[test]
    fn errored_projects_message_and_no_data() {
        let status: ResourceStatus<CatalogData> = ResourceStatus::Errored {
            message: "boom".into(),
            retrying: false,
        };
        let (data, err) = project(&status);
        assert!(data.is_none());
        assert_eq!(err, "boom");
    }

    #[test]
    fn errored_with_retrying_still_propagates_message() {
        let status: ResourceStatus<CatalogData> = ResourceStatus::Errored {
            message: "reconnecting".into(),
            retrying: true,
        };
        let (data, err) = project(&status);
        assert!(data.is_none());
        assert_eq!(err, "reconnecting");
    }

    #[test]
    fn rows_for_category_none_returns_empty() {
        let rows = rows_for_category(None, "Arcade");
        assert!(rows.is_empty());
    }

    #[test]
    fn rows_for_category_filters_and_reshapes() {
        let catalog = catalog_with(vec![
            sys("smb", "Super Mario Bros", "Consoles"),
            sys("snk", "SNK Heroes", "Arcade"),
            sys("zelda", "Zelda", "Consoles"),
        ]);
        let rows = rows_for_category(Some(&catalog), "Consoles");
        assert_eq!(rows.len(), 2);
        assert_eq!(rows[0].id, "smb");
        assert_eq!(rows[0].name, "Super Mario Bros");
        assert_eq!(rows[0].category, "Consoles");
        assert_eq!(rows[1].id, "zelda");
    }

    #[test]
    fn rows_for_category_unknown_returns_empty() {
        let catalog = catalog_with(vec![sys("smb", "SMB", "Consoles")]);
        let rows = rows_for_category(Some(&catalog), "DoesNotExist");
        assert!(rows.is_empty());
    }
}
