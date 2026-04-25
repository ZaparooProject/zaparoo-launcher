// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//
// `Browse.AppStatus` — ephemeral connection / catalog health, exposed
// to QML so the UI can render a status strip when Core is unreachable
// or the initial catalog fetch failed. State is not persisted: it is
// recomputed from the live client and catalog channels on every start.
//
// `connection_state` constants:
//   0 DISCONNECTED — no active ws link and not currently attempting one
//   1 CONNECTING   — ws handshake in flight, or ws up with catalog RPC
//                    pending (same user-facing meaning: "waiting on Core")
//   2 READY        — ws up and catalog loaded; UI has data
//   3 ERROR        — catalog RPC errored, or ws reconnect exceeded the
//                    client's retry threshold (see client::ConnectionState)

use cxx_qt::{Initialize, Threading};
use cxx_qt_lib::QString;
use std::pin::Pin;
use zaparoo_core::client::ConnectionState;
use zaparoo_core::systems_catalog::CatalogStatus;

pub const DISCONNECTED: i32 = 0;
pub const CONNECTING: i32 = 1;
pub const READY: i32 = 2;
pub const ERROR: i32 = 3;

pub struct AppStatusRust {
    connection_state: i32,
    last_error: QString,
}

impl Default for AppStatusRust {
    fn default() -> Self {
        Self {
            connection_state: DISCONNECTED,
            last_error: QString::default(),
        }
    }
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
        #[qproperty(i32, connection_state)]
        #[qproperty(QString, last_error)]
        type AppStatus = super::AppStatusRust;
    }

    impl cxx_qt::Threading for AppStatus {}
    impl cxx_qt::Initialize for AppStatus {}
}

impl Initialize for ffi::AppStatus {
    fn initialize(self: Pin<&mut Self>) {
        use crate::models::{global_client, global_runtime, subscribe_catalog_status};

        let qt_thread = self.qt_thread();
        let client = global_client();
        let mut connection_rx = client.connection.subscribe();
        let mut status_rx = subscribe_catalog_status();

        global_runtime().spawn(async move {
            // Seed both halves from the watches' current values so a late
            // subscriber (this `initialize()` runs after the QML engine
            // boots, which is after the WebSocket task has likely already
            // transitioned through Connecting → Connected) sees the real
            // current state instead of sitting on a hardcoded default.
            let mut connection = connection_rx.borrow_and_update().clone();
            let mut status = status_rx.borrow_and_update().clone();
            push(&qt_thread, &connection, &status);

            loop {
                tokio::select! {
                    result = connection_rx.changed() => match result {
                        Ok(()) => {
                            connection = connection_rx.borrow_and_update().clone();
                            push(&qt_thread, &connection, &status);
                        }
                        Err(_) => break,
                    },
                    result = status_rx.changed() => match result {
                        Ok(()) => {
                            status = status_rx.borrow_and_update().clone();
                            push(&qt_thread, &connection, &status);
                        }
                        Err(_) => break,
                    }
                }
            }
        });
    }
}

fn push(
    qt_thread: &cxx_qt::CxxQtThread<ffi::AppStatus>,
    connection: &ConnectionState,
    status: &CatalogStatus,
) {
    let (state, err) = derive(connection, status);
    let _ = qt_thread.queue(move |mut model| {
        if model.connection_state != state {
            model.as_mut().set_connection_state(state);
        }
        let new_err = QString::from(err.as_str());
        if model.last_error != new_err {
            model.as_mut().set_last_error(new_err);
        }
    });
}

/// Merge the two sources of truth (ws link + catalog RPC) into the
/// single `connection_state` + `last_error` pair that QML consumes.
///
/// Precedence: a catalog error outranks a link error outranks a link
/// transition. A successful link with no catalog yet shows CONNECTING
/// so the UI doesn't flicker READY between ws-up and catalog-loaded.
fn derive(connection: &ConnectionState, status: &CatalogStatus) -> (i32, String) {
    match (connection, status) {
        (_, CatalogStatus::Errored(msg)) | (ConnectionState::Error(msg), _) => (ERROR, msg.clone()),
        (ConnectionState::Disconnected, _) => (DISCONNECTED, String::new()),
        (ConnectionState::Connecting, _) => (CONNECTING, String::new()),
        (ConnectionState::Connected, CatalogStatus::Idle | CatalogStatus::Loading) => {
            (CONNECTING, String::new())
        }
        (ConnectionState::Connected, CatalogStatus::Ready) => (READY, String::new()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn errored_catalog_outranks_connected_link() {
        let (state, err) = derive(
            &ConnectionState::Connected,
            &CatalogStatus::Errored("rpc kaboom".into()),
        );
        assert_eq!(state, ERROR);
        assert_eq!(err, "rpc kaboom");
    }

    #[test]
    fn link_error_surfaces_after_retries_exhausted() {
        let (state, err) = derive(
            &ConnectionState::Error("connection refused".into()),
            &CatalogStatus::Idle,
        );
        assert_eq!(state, ERROR);
        assert_eq!(err, "connection refused");
    }

    #[test]
    fn connecting_link_maps_to_connecting_banner() {
        let (state, err) = derive(&ConnectionState::Connecting, &CatalogStatus::Idle);
        assert_eq!(state, CONNECTING);
        assert_eq!(err, "");
    }

    #[test]
    fn connected_but_catalog_loading_stays_connecting() {
        let (state, _) = derive(&ConnectionState::Connected, &CatalogStatus::Loading);
        assert_eq!(state, CONNECTING);
    }

    #[test]
    fn ready_requires_both_connected_and_catalog_ready() {
        let (state, _) = derive(&ConnectionState::Connected, &CatalogStatus::Ready);
        assert_eq!(state, READY);
    }

    #[test]
    fn disconnected_link_overrides_stale_catalog_state() {
        let (state, _) = derive(&ConnectionState::Disconnected, &CatalogStatus::Ready);
        assert_eq!(state, DISCONNECTED);
    }
}
