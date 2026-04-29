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
const COVER_KEY_ROLE: i32 = 256 + 2;

// Placeholder entry shown at the start of the categories row until a
// real Favorites pipeline lands in Core. Selecting it filters the
// systems grid by an unmatched category — the user sees an empty grid,
// which is the correct fallback for a feature that doesn't exist yet.
// Tracked in #20.
const FAVORITES_CATEGORY: &str = "Favorites";

// Categories Core surfaces but the launcher doesn't expose. `Other` is
// the synthesized bucket for systems with no upstream category and adds
// no value in the UI; `Media` is reserved for non-game content the
// launcher doesn't have a screen for yet. Tracked in #21.
const HIDDEN_CATEGORIES: &[&str] = &["Other", "Media"];

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
        ResourceStatus::Ready(data) => (Some(visible_categories(&data.categories)), String::new()),
        ResourceStatus::Errored { message, .. } => (None, message.clone()),
        ResourceStatus::Idle | ResourceStatus::Loading => (None, String::new()),
    }
}

/// Find `needle` in `haystack` with case-sensitive equality. Returns
/// the position as i32, or -1 if not found / empty needle. The
/// case-sensitive contract is deliberate: `HubState.category` is
/// persisted to disk and the launcher re-derives the row index from
/// that string. A case-insensitive lookup would silently coerce
/// "consoles" into "Consoles" if Core ever returned mixed case,
/// hiding a real upstream bug. Pulled out of `index_for_category`
/// so the contract is unit-testable without a `QObject` instance.
fn position_of(haystack: &[String], needle: &str) -> i32 {
    if needle.is_empty() {
        return -1;
    }
    haystack
        .iter()
        .position(|c| c == needle)
        .map_or(-1, |i| i as i32)
}

/// Apply the launcher-side category presentation rules to the raw list
/// from Core: drop hidden categories and prepend the Favorites
/// placeholder. Pulled out of `project` for unit-test coverage.
fn visible_categories(raw: &[String]) -> Vec<String> {
    let mut out = Vec::with_capacity(raw.len() + 1);
    out.push(FAVORITES_CATEGORY.to_string());
    for c in raw {
        if HIDDEN_CATEGORIES
            .iter()
            .any(|hidden| c.eq_ignore_ascii_case(hidden))
        {
            continue;
        }
        out.push(c.clone());
    }
    out
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
        match role {
            NAME_ROLE => {
                let s = &self.categories[index.row() as usize];
                QVariant::from(&QString::from(s.as_str()))
            }
            COVER_KEY_ROLE => {
                // Relative path under `resources/images/` (no extension).
                // Categories without a curated PNG (anything we haven't
                // bundled yet) still emit a key — Tile's Image fails to
                // resolve and the procedural fallback takes over.
                let s = &self.categories[index.row() as usize];
                QVariant::from(&QString::from(format!("categories/{s}").as_str()))
            }
            _ => QVariant::default(),
        }
    }

    fn role_names(&self) -> QHash<QHashPair_i32_QByteArray> {
        let mut hash = QHash::<QHashPair_i32_QByteArray>::default();
        hash.insert(NAME_ROLE, QByteArray::from("name"));
        hash.insert(COVER_KEY_ROLE, QByteArray::from("coverKey"));
        hash
    }

    fn category_at(&self, index: i32) -> QString {
        if index < 0 || index >= self.count {
            return QString::default();
        }
        QString::from(self.categories[index as usize].as_str())
    }

    fn index_for_category(&self, name: &QString) -> i32 {
        position_of(&self.categories, &name.to_string())
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

    use super::{position_of, visible_categories};

    #[test]
    fn position_of_returns_index_on_case_exact_match() {
        let items = vec!["Consoles".to_string(), "Arcade".to_string()];
        assert_eq!(position_of(&items, "Arcade"), 1);
    }

    #[test]
    fn position_of_is_case_sensitive_and_returns_minus_one_on_mismatch() {
        let items = vec!["Consoles".to_string(), "Arcade".to_string()];
        // Mixed case must NOT match — HubState.category is persisted as
        // an exact string and the lookup is case-sensitive on purpose.
        assert_eq!(position_of(&items, "arcade"), -1);
        assert_eq!(position_of(&items, "ARCADE"), -1);
    }

    #[test]
    fn position_of_empty_needle_returns_minus_one() {
        let items = vec!["Consoles".to_string()];
        assert_eq!(position_of(&items, ""), -1);
    }

    #[test]
    fn position_of_missing_returns_minus_one() {
        let items = vec!["Consoles".to_string()];
        assert_eq!(position_of(&items, "Missing"), -1);
    }

    #[test]
    fn favorites_is_prepended_to_visible_list() {
        let raw = vec!["Consoles".to_string(), "Arcade".to_string()];
        let visible = visible_categories(&raw);
        assert_eq!(visible, vec!["Favorites", "Consoles", "Arcade"]);
    }

    #[test]
    fn other_and_media_are_filtered_case_insensitively() {
        let raw = vec![
            "Arcade".to_string(),
            "Other".to_string(),
            "media".to_string(),
            "Consoles".to_string(),
        ];
        let visible = visible_categories(&raw);
        assert_eq!(visible, vec!["Favorites", "Arcade", "Consoles"]);
    }

    #[test]
    fn empty_raw_still_yields_favorites_only() {
        let visible = visible_categories(&[]);
        assert_eq!(visible, vec!["Favorites"]);
    }

    #[test]
    fn original_casing_is_preserved_for_visible_entries() {
        let raw = vec!["arcade".to_string(), "CONSOLES".to_string()];
        let visible = visible_categories(&raw);
        assert_eq!(visible, vec!["Favorites", "arcade", "CONSOLES"]);
    }
}
