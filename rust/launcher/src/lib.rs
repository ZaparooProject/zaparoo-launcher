// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
// SPDX-FileCopyrightText: 2026 Callan Barrett

mod mister_runtime;
mod models;

/// Called from the Qt message handler in main.cpp. `level` is QtMsgType
/// cast to u8. `msg_ptr`/`msg_len` are a UTF-8 slice owned by the caller.
/// Routes Qt log output through the tracing registry so it lands in the
/// same stderr + file sinks as Rust log messages.
#[no_mangle]
pub extern "C" fn zaparoo_log_qt(level: u8, msg_ptr: *const u8, msg_len: usize) {
    let msg = unsafe { std::str::from_utf8_unchecked(std::slice::from_raw_parts(msg_ptr, msg_len)) };
    match level {
        0 /* QtDebugMsg    */ => tracing::debug!(target: "qt", "{}", msg),
        4 /* QtInfoMsg     */ => tracing::info!(target: "qt", "{}", msg),
        1 /* QtWarningMsg  */ => tracing::warn!(target: "qt", "{}", msg),
        2 /* QtCriticalMsg */ => tracing::error!(target: "qt", "{}", msg),
        3 /* QtFatalMsg    */ => tracing::error!(target: "qt", "FATAL: {}", msg),
        _ => tracing::info!(target: "qt", "{}", msg),
    }
}

use std::ffi::c_int;
use std::sync::Arc;
use zaparoo_core::{client::Client, config::load_config, logger::install, platform_paths::config_file_path, systems_catalog};

/// Called by the C++ main before QGuiApplication is constructed.
/// Sets up logging, tokio runtime, MiSTer pre-Qt env/vmode, WebSocket
/// client, SystemsCatalog, and model globals. Returns 0 on success.
#[no_mangle]
pub extern "C" fn zaparoo_rust_init() -> c_int {
    let config_path = config_file_path();
    let config = load_config(&config_path);

    // Leak the guard — it must live for the process lifetime to keep the
    // file-appender thread running. The OS reclaims it on exit.
    let guard = install(&config);
    Box::leak(Box::new(guard));

    tracing::info!("Zaparoo Launcher starting");

    let runtime = Arc::new(
        tokio::runtime::Builder::new_multi_thread()
            .enable_all()
            .build()
            .expect("tokio runtime"),
    );

    mister_runtime::apply_pre_qt_setup(&config);

    let client = Client::new(config.core_endpoint.clone(), runtime.clone());
    let catalog_tx = systems_catalog::spawn(client.clone(), runtime.clone());

    // init_globals stores Arcs — runtime keeps running after this fn returns.
    models::init_globals(runtime, client, catalog_tx);

    0
}

/// Called by the C++ main after the QML engine has loaded but before exec().
/// Fires the Zaparoo Core service start (MiSTer only, no-op on desktop).
#[no_mangle]
pub extern "C" fn zaparoo_rust_post_qt_start() {
    mister_runtime::ensure_core_service_running();
}
