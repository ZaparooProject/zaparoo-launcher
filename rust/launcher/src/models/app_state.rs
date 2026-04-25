// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//
// `Browse.AppState` — top-level singleton for launch-resume routing.
// Holds only the currently-active screen; every per-screen detail
// lives in its own singleton (`Browse.HubState`, `Browse.GamesState`)
// so a screen can evolve its schema without touching the others.

use cxx_qt::{CxxQtType, Initialize};
use cxx_qt_lib::QString;
use std::pin::Pin;
use zaparoo_core::persist;

#[derive(Default)]
pub struct AppStateRust {
    active_screen: QString,
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
        #[qproperty(QString, active_screen, READ, WRITE = set_active_screen, NOTIFY)]
        type AppState = super::AppStateRust;

        #[qinvokable]
        fn set_active_screen(self: Pin<&mut AppState>, value: QString);
    }

    impl cxx_qt::Initialize for AppState {}
}

impl Initialize for ffi::AppState {
    fn initialize(mut self: Pin<&mut Self>) {
        let shared = crate::models::persist_state();
        let snapshot = {
            let guard = shared.lock().expect("persist mutex poisoned");
            guard.active_screen.clone()
        };
        self.as_mut().rust_mut().active_screen = QString::from(snapshot.as_str());
        // No *_changed emits here: QML bindings haven't attached yet
        // during Initialize, and Main.qml reads the property directly
        // in Component.onCompleted.
    }
}

impl ffi::AppState {
    fn set_active_screen(mut self: Pin<&mut Self>, value: QString) {
        if self.active_screen == value {
            return;
        }
        let value_str = value.to_string();
        self.as_mut().rust_mut().active_screen = value;
        self.as_mut().active_screen_changed();
        persist_active_screen(value_str);
    }
}

fn persist_active_screen(value: String) {
    let shared = crate::models::persist_state();
    let snapshot = {
        let mut guard = shared.lock().expect("persist mutex poisoned");
        guard.active_screen = value;
        guard.clone()
    };
    persist::save(&snapshot);
}
