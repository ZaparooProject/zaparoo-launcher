// Zaparoo Launcher
// Copyright (c) 2026 The Zaparoo Project Contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//
// Globals set by main() before the QML engine is created. Each QML singleton
// model reads from these in its Default::default() implementation so it can
// wire itself to the catalog broadcast without constructor-injection.
//
// The QML singletons are constructed *after* init_globals runs, so any
// `expect`/`panic` below represents an internal wiring bug (double-init or
// use-before-init) and is correctly fatal.

#![allow(
    clippy::panic,
    clippy::expect_used,
    reason = "process-local init invariants: any violation is a wiring bug and must be fatal"
)]

pub mod browse;
pub mod categories;
pub mod games;
pub mod systems;

use std::sync::{Arc, OnceLock};
use tokio::runtime::Runtime;
use tokio::sync::watch;
use zaparoo_core::{client::Client, systems_catalog::CatalogData};

static RUNTIME: OnceLock<Arc<Runtime>> = OnceLock::new();
static CLIENT: OnceLock<Arc<Client>> = OnceLock::new();
static CATALOG_TX: OnceLock<watch::Sender<Option<CatalogData>>> = OnceLock::new();

pub fn init_globals(
    runtime: Arc<Runtime>,
    client: Arc<Client>,
    catalog_tx: watch::Sender<Option<CatalogData>>,
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
