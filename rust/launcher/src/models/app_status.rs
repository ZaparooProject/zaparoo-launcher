// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//
// `Browse.AppStatus` — ephemeral connection / catalog health, exposed
// to QML so the UI can render a status strip when Core is unreachable
// or the initial catalog fetch failed. State is not persisted: it is
// derived from a single `ResourceStatus<CatalogData>` watch which
// already merges the link state and the fetch state (see
// `RemoteResource` for the dispatch table).
//
// `connection_state` constants:
//   0 DISCONNECTED — resource Idle (link not attempted yet)
//   1 CONNECTING   — resource Loading (handshake or RPC in flight)
//   2 READY        — resource Ready (catalog loaded)
//   3 ERROR        — resource Errored (link unreachable or RPC failed)

use cxx_qt_lib::QString;
use std::pin::Pin;
use zaparoo_core::endpoints::catalog::CatalogEndpoint;
use zaparoo_core::remote_resource::ResourceStatus;
use zaparoo_core::systems_catalog::CatalogData;

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

crate::bind_to_endpoint! {
    for ffi::AppStatus,
    endpoint = CatalogEndpoint,
    args = (),
    select = project,
    apply = apply_state,
}

/// Map `ResourceStatus<CatalogData>` onto the four banner states the QML
/// side knows about. The error message is whatever the resource layer
/// surfaced — link error (`Unreachable`) or RPC error (`Errored` while
/// the link is still up). The UI treats them the same.
fn project(status: &ResourceStatus<CatalogData>) -> (i32, String) {
    match status {
        ResourceStatus::Idle => (DISCONNECTED, String::new()),
        ResourceStatus::Loading => (CONNECTING, String::new()),
        ResourceStatus::Ready(_) => (READY, String::new()),
        ResourceStatus::Errored { message, .. } => (ERROR, message.clone()),
    }
}

/// Apply a freshly-derived `(state, err)` to the model, suppressing
/// `QProperty` setters whose value hasn't changed so QML doesn't see
/// spurious `Changed` signals on every reconnect.
fn apply_state(mut model: Pin<&mut ffi::AppStatus>, (state, err): (i32, String)) {
    if model.connection_state != state {
        model.as_mut().set_connection_state(state);
    }
    let qerr = QString::from(err.as_str());
    if model.last_error != qerr {
        model.as_mut().set_last_error(qerr);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn empty_catalog() -> CatalogData {
        CatalogData {
            systems: Vec::new(),
            categories: Vec::new(),
        }
    }

    #[test]
    fn idle_maps_to_disconnected() {
        let (state, err) = project(&ResourceStatus::Idle);
        assert_eq!(state, DISCONNECTED);
        assert_eq!(err, "");
    }

    #[test]
    fn loading_maps_to_connecting() {
        let (state, err) = project(&ResourceStatus::Loading);
        assert_eq!(state, CONNECTING);
        assert_eq!(err, "");
    }

    #[test]
    fn ready_maps_to_ready_with_no_error() {
        let (state, err) = project(&ResourceStatus::Ready(empty_catalog()));
        assert_eq!(state, READY);
        assert_eq!(err, "");
    }

    #[test]
    fn errored_with_retrying_surfaces_message() {
        let (state, err) = project(&ResourceStatus::Errored {
            message: "rpc kaboom".into(),
            retrying: true,
        });
        assert_eq!(state, ERROR);
        assert_eq!(err, "rpc kaboom");
    }

    #[test]
    fn errored_without_retrying_surfaces_message() {
        let (state, err) = project(&ResourceStatus::Errored {
            message: "connection refused".into(),
            retrying: false,
        });
        assert_eq!(state, ERROR);
        assert_eq!(err, "connection refused");
    }
}
