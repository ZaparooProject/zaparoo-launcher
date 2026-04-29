// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//
// Globals set by main() before the QML engine is created. QML singletons
// subscribe to data through `STORE` rather than receiving it via
// constructor injection — this side-channel is the only place
// cxx-qt's `Default::default()` boundary lets us reach into.
//
// The QML singletons are constructed *after* init_globals runs, so any
// `expect`/`panic` below represents an internal wiring bug (double-init
// or use-before-init) and is correctly fatal.
//
// `STORE` owns the `Client` and runtime and hands out shared
// `RemoteResource`s per (endpoint, args). Singletons reach it via
// `global_store()` — `bind_to_endpoint!` is the standard caller and
// closes the sync-seed contract from `docs/cxx-qt-bridge.md`
// structurally.

#![allow(
    clippy::panic,
    clippy::expect_used,
    reason = "process-local init invariants: any violation is a wiring bug and must be fatal"
)]

pub mod app_state;
pub mod app_status;
pub mod browse;
pub mod categories;
pub mod games;
pub mod games_state;
pub mod hub_state;
pub mod input;
pub mod runtime;
pub mod system_status;
pub mod systems;
pub mod systems_state;

use std::collections::HashMap;
use std::sync::{Arc, Mutex, OnceLock};
use tokio::runtime::Runtime;
use tracing::error;
use zaparoo_core::{persist::PersistedState, store::Store};

static RUNTIME: OnceLock<Arc<Runtime>> = OnceLock::new();
static STORE: OnceLock<Arc<Store>> = OnceLock::new();
static PERSIST_STATE: OnceLock<Arc<Mutex<PersistedState>>> = OnceLock::new();
static INPUT_BINDINGS: OnceLock<HashMap<i32, String>> = OnceLock::new();
static CORE_IS_LOCAL: OnceLock<bool> = OnceLock::new();

pub fn init_globals(
    runtime: Arc<Runtime>,
    store: Arc<Store>,
    persist_state: Arc<Mutex<PersistedState>>,
    input_bindings: HashMap<i32, String>,
    core_is_local: bool,
) {
    RUNTIME
        .set(runtime)
        .unwrap_or_else(|_| panic!("RUNTIME already initialized"));
    STORE
        .set(store)
        .unwrap_or_else(|_| panic!("STORE already initialized"));
    PERSIST_STATE
        .set(persist_state)
        .unwrap_or_else(|_| panic!("PERSIST_STATE already initialized"));
    INPUT_BINDINGS
        .set(input_bindings)
        .unwrap_or_else(|_| panic!("INPUT_BINDINGS already initialized"));
    CORE_IS_LOCAL
        .set(core_is_local)
        .unwrap_or_else(|_| panic!("CORE_IS_LOCAL already initialized"));
}

pub fn global_runtime() -> Arc<Runtime> {
    RUNTIME.get().expect("RUNTIME not initialized").clone()
}

pub fn global_store() -> Arc<Store> {
    STORE.get().expect("STORE not initialized").clone()
}

pub fn input_bindings() -> HashMap<i32, String> {
    INPUT_BINDINGS
        .get()
        .expect("INPUT_BINDINGS not initialized")
        .clone()
}

pub fn core_is_local() -> bool {
    *CORE_IS_LOCAL.get().expect("CORE_IS_LOCAL not initialized")
}

pub fn persist_state() -> Arc<Mutex<PersistedState>> {
    PERSIST_STATE
        .get()
        .expect("PERSIST_STATE not initialized")
        .clone()
}

/// Read the persisted state under a closure. Centralises the
/// lock + log + panic-on-poison chain so the 5+ persist call sites
/// can't drift in their error message or skip the log breadcrumb.
pub fn with_persist_read<R>(f: impl FnOnce(&PersistedState) -> R) -> R {
    let shared = persist_state();
    let guard = shared
        .lock()
        .inspect_err(|e| error!("persist mutex poisoned: {e}"))
        .expect("persist mutex poisoned");
    f(&guard)
}

/// Mutate the persisted state under a closure. Same poisoning
/// contract as `with_persist_read`.
pub fn with_persist_mut<R>(f: impl FnOnce(&mut PersistedState) -> R) -> R {
    let shared = persist_state();
    let mut guard = shared
        .lock()
        .inspect_err(|e| error!("persist mutex poisoned: {e}"))
        .expect("persist mutex poisoned");
    f(&mut guard)
}
