// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//
// `Browse.GamesState` — persisted state owned by the games screen.
// Records the system currently scoped to the games grid and the
// highlighted game path. Schema version is checked independently
// from other screens on load (see `zaparoo_core::persist`).

use crate::models::{with_persist_mut, with_persist_read};
use cxx_qt::{CxxQtType, Initialize};
use cxx_qt_lib::QString;
use std::pin::Pin;
use zaparoo_core::persist::{self, GamesState};

#[derive(Default)]
pub struct GamesStateRust {
    system_id: QString,
    game_path: QString,
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
        #[qproperty(QString, system_id, READ, WRITE = set_system_id, NOTIFY)]
        #[qproperty(QString, game_path, READ, WRITE = set_game_path, NOTIFY)]
        type GamesState = super::GamesStateRust;

        #[qinvokable]
        fn set_system_id(self: Pin<&mut GamesState>, value: QString);

        #[qinvokable]
        fn set_game_path(self: Pin<&mut GamesState>, value: QString);
    }

    impl cxx_qt::Initialize for GamesState {}
}

impl Initialize for ffi::GamesState {
    fn initialize(mut self: Pin<&mut Self>) {
        let snapshot: GamesState = with_persist_read(|s| s.games.clone());
        self.as_mut().rust_mut().system_id = QString::from(snapshot.system_id.as_str());
        self.as_mut().rust_mut().game_path = QString::from(snapshot.game_path.as_str());
    }
}

impl ffi::GamesState {
    fn set_system_id(mut self: Pin<&mut Self>, value: QString) {
        if self.system_id == value {
            return;
        }
        let value_str = value.to_string();
        self.as_mut().rust_mut().system_id = value;
        self.as_mut().system_id_changed();
        persist_games(|g| g.system_id = value_str);
    }

    fn set_game_path(mut self: Pin<&mut Self>, value: QString) {
        if self.game_path == value {
            return;
        }
        let value_str = value.to_string();
        self.as_mut().rust_mut().game_path = value;
        self.as_mut().game_path_changed();
        persist_games(|g| g.game_path = value_str);
    }
}

fn persist_games<F: FnOnce(&mut GamesState)>(mutator: F) {
    let snapshot = with_persist_mut(|s| {
        mutator(&mut s.games);
        s.clone()
    });
    persist::save(&snapshot);
}
