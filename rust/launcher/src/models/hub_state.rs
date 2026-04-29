// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//
// `Browse.HubState` — persisted state owned by the hub screen. Holds
// the category the user last selected. Schema version is checked
// independently from other screens on load (see `zaparoo_core::persist`).

use crate::models::{with_persist_mut, with_persist_read};
use cxx_qt::{CxxQtType, Initialize};
use cxx_qt_lib::QString;
use std::pin::Pin;
use zaparoo_core::persist::{self, HubState};

#[derive(Default)]
pub struct HubStateRust {
    category: QString,
}

#[cxx_qt::bridge]
pub mod ffi {
    unsafe extern "C++" {
        include!("model_includes.h");

        type QString = cxx_qt_lib::QString;
    }

    unsafe extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qml_singleton]
        #[qproperty(QString, category, READ, WRITE = set_category, NOTIFY)]
        type HubState = super::HubStateRust;

        #[qinvokable]
        fn set_category(self: Pin<&mut HubState>, value: QString);
    }

    impl cxx_qt::Initialize for HubState {}
}

impl Initialize for ffi::HubState {
    fn initialize(mut self: Pin<&mut Self>) {
        let snapshot: HubState = with_persist_read(|s| s.hub.clone());
        self.as_mut().rust_mut().category = QString::from(snapshot.category.as_str());
    }
}

impl ffi::HubState {
    fn set_category(mut self: Pin<&mut Self>, value: QString) {
        if self.category == value {
            return;
        }
        let value_str = value.to_string();
        self.as_mut().rust_mut().category = value;
        self.as_mut().category_changed();
        persist_hub(|h| h.category = value_str);
    }
}

fn persist_hub<F: FnOnce(&mut HubState)>(mutator: F) {
    let snapshot = with_persist_mut(|s| {
        mutator(&mut s.hub);
        s.clone()
    });
    persist::save(&snapshot);
}
