// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//
// Globals set by main() before the QML engine is created. Each QML singleton
// model reads from these in its Default::default() implementation so it can
// wire itself to the catalog watch without constructor-injection.
//
// The QML singletons are constructed *after* init_globals runs, so any
// `expect`/`panic` below represents an internal wiring bug (double-init or
// use-before-init) and is correctly fatal.

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
pub mod systems;

use std::collections::HashMap;
use std::sync::{Arc, Mutex, OnceLock};
use tokio::runtime::Runtime;
use tokio::sync::watch;
use zaparoo_core::{
    client::Client,
    persist::PersistedState,
    systems_catalog::{CatalogData, CatalogStatus},
};

static RUNTIME: OnceLock<Arc<Runtime>> = OnceLock::new();
static CLIENT: OnceLock<Arc<Client>> = OnceLock::new();
static CATALOG_TX: OnceLock<watch::Sender<Option<CatalogData>>> = OnceLock::new();
static CATALOG_STATUS_TX: OnceLock<watch::Sender<CatalogStatus>> = OnceLock::new();
static PERSIST_STATE: OnceLock<Arc<Mutex<PersistedState>>> = OnceLock::new();
static INPUT_BINDINGS: OnceLock<HashMap<i32, String>> = OnceLock::new();

pub fn init_globals(
    runtime: Arc<Runtime>,
    client: Arc<Client>,
    catalog_tx: watch::Sender<Option<CatalogData>>,
    catalog_status_tx: watch::Sender<CatalogStatus>,
    persist_state: Arc<Mutex<PersistedState>>,
    input_bindings: HashMap<i32, String>,
) {
    RUNTIME
        .set(runtime)
        .unwrap_or_else(|_| panic!("RUNTIME already initialized"));
    CLIENT
        .set(client)
        .unwrap_or_else(|_| panic!("CLIENT already initialized"));
    CATALOG_TX
        .set(catalog_tx)
        .unwrap_or_else(|_| panic!("CATALOG_TX already initialized"));
    CATALOG_STATUS_TX
        .set(catalog_status_tx)
        .unwrap_or_else(|_| panic!("CATALOG_STATUS_TX already initialized"));
    PERSIST_STATE
        .set(persist_state)
        .unwrap_or_else(|_| panic!("PERSIST_STATE already initialized"));
    INPUT_BINDINGS
        .set(input_bindings)
        .unwrap_or_else(|_| panic!("INPUT_BINDINGS already initialized"));
}

pub fn global_runtime() -> Arc<Runtime> {
    RUNTIME.get().expect("RUNTIME not initialized").clone()
}

pub fn global_client() -> Arc<Client> {
    CLIENT.get().expect("CLIENT not initialized").clone()
}

pub fn subscribe_catalog() -> watch::Receiver<Option<CatalogData>> {
    CATALOG_TX
        .get()
        .expect("CATALOG_TX not initialized")
        .subscribe()
}

pub fn subscribe_catalog_status() -> watch::Receiver<CatalogStatus> {
    CATALOG_STATUS_TX
        .get()
        .expect("CATALOG_STATUS_TX not initialized")
        .subscribe()
}

pub fn input_bindings() -> HashMap<i32, String> {
    INPUT_BINDINGS
        .get()
        .expect("INPUT_BINDINGS not initialized")
        .clone()
}

pub fn persist_state() -> Arc<Mutex<PersistedState>> {
    PERSIST_STATE
        .get()
        .expect("PERSIST_STATE not initialized")
        .clone()
}
