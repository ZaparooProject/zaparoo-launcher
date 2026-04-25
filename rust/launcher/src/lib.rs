// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0

mod mister_runtime;
mod models;

/// Called from the Qt message handler in main.cpp. `level` is `QtMsgType`
/// cast to u8. `msg_ptr`/`msg_len` are a UTF-8 slice owned by the caller.
/// Routes Qt log output through the tracing registry so it lands in the
/// same stderr + file sinks as Rust log messages.
///
/// # Safety
///
/// `msg_ptr` must point to `msg_len` bytes of valid UTF-8 that remain live
/// for the duration of this call. The Qt message handler always provides a
/// valid `QString::toUtf8()` slice, so this invariant holds in practice.
#[no_mangle]
pub unsafe extern "C" fn zaparoo_log_qt(level: u8, msg_ptr: *const u8, msg_len: usize) {
    // SAFETY: Caller guarantees `msg_ptr`..`msg_ptr + msg_len` is a valid
    // UTF-8 byte slice (Qt's message handler passes QString::toUtf8()).
    let msg =
        unsafe { std::str::from_utf8_unchecked(std::slice::from_raw_parts(msg_ptr, msg_len)) };
    match level {
        0 /* QtDebugMsg    */ => tracing::debug!(target: "qt", "{}", msg),
        4 /* QtInfoMsg     */ => tracing::info!(target: "qt", "{}", msg),
        1 /* QtWarningMsg  */ => tracing::warn!(target: "qt", "{}", msg),
        2 /* QtCriticalMsg */ => tracing::error!(target: "qt", "{}", msg),
        3 /* QtFatalMsg    */ => tracing::error!(target: "qt", "FATAL: {}", msg),
        _ => tracing::info!(target: "qt", "{}", msg),
    }
}

use std::ffi::{c_char, c_int, CString};
use std::sync::{Arc, Mutex, OnceLock};
use zaparoo_core::{
    client::Client, config::load_config, logger::install, persist, platform,
    platform_paths::config_file_path, systems_catalog,
};

/// Resolved language override, cached after [`zaparoo_rust_init`] so the
/// C++ side can pull it via [`zaparoo_rust_language_code`] without re-
/// loading config. An empty string means "use `QLocale::system()`".
static LANGUAGE_CODE: OnceLock<CString> = OnceLock::new();

/// Returns the resolved UI language override as a NUL-terminated UTF-8
/// string. An empty string signals "follow `QLocale::system()`"; any
/// other value is a BCP-47 tag passed straight to `QLocale(code)` in
/// C++. The pointer is valid for the process lifetime.
///
/// Called before [`zaparoo_rust_init`] returns an empty string, since
/// the `OnceLock` has not yet been populated.
#[no_mangle]
pub extern "C" fn zaparoo_rust_language_code() -> *const c_char {
    LANGUAGE_CODE
        .get()
        .map_or_else(|| c"".as_ptr(), |s| s.as_ptr())
}

/// Installs a panic hook that routes Rust panics through the tracing
/// registry so they land in the same stderr + JSONL sinks as normal log
/// output. Without this, a panic on a tokio worker goes to raw stderr
/// only — invisible on `MiSTer` where stderr is not captured. The hook
/// chains to the previous default, preserving abort-on-panic semantics.
fn install_panic_hook() {
    let default = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |info| {
        let payload = info.payload();
        let msg = payload
            .downcast_ref::<&str>()
            .copied()
            .or_else(|| payload.downcast_ref::<String>().map(String::as_str))
            .unwrap_or("<non-string panic payload>");
        let location = info.location().map_or_else(
            || "<unknown>".to_string(),
            |l| format!("{}:{}:{}", l.file(), l.line(), l.column()),
        );
        let thread = std::thread::current();
        let thread_name = thread.name().unwrap_or("<unnamed>");
        let backtrace = std::backtrace::Backtrace::capture();
        tracing::error!(
            target: "panic",
            "thread '{thread_name}' panicked at {location}: {msg}\n{backtrace}"
        );
        default(info);
    }));
}

/// Called by the C++ main before `QGuiApplication` is constructed.
/// Sets up logging, tokio runtime, `MiSTer` pre-Qt env/vmode, WebSocket
/// client, `SystemsCatalog`, and model globals. Returns 0 on success.
#[no_mangle]
pub extern "C" fn zaparoo_rust_init() -> c_int {
    let config_path = config_file_path();
    let config = load_config(&config_path);

    // Cache the language override so `zaparoo_rust_language_code` (called
    // from main.cpp before the QML engine loads) can return it without
    // re-parsing the TOML. `CString::new` only fails on interior NULs,
    // which a valid BCP-47 tag or the empty sentinel cannot contain —
    // fall back to empty ("use QLocale::system()") if a user manages it.
    let _ = LANGUAGE_CODE.set(CString::new(config.language.clone()).unwrap_or_default());

    // Leak the guard — it must live for the process lifetime to keep the
    // file-appender thread running. The OS reclaims it on exit.
    let guard = install(&config);
    Box::leak(Box::new(guard));

    // Install after logging so panics go through the same sinks; before
    // tokio / client setup so a panic during those lines is captured.
    install_panic_hook();

    tracing::info!("Zaparoo Launcher starting");

    let runtime = match tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()
    {
        Ok(r) => Arc::new(r),
        Err(e) => {
            tracing::error!("failed to build tokio runtime: {e}");
            return 1;
        }
    };

    mister_runtime::apply_pre_qt_setup(&config);

    let client = Client::new(config.core_endpoint.clone(), &runtime);
    platform::spawn_fetcher(client.clone(), &runtime);
    let channels = systems_catalog::spawn(client.clone(), &runtime);

    // Load persisted UI state up front so per-screen singletons can seed
    // their properties from a consistent snapshot during Initialize.
    let persist_state = Arc::new(Mutex::new(persist::load()));

    // init_globals stores Arcs — runtime keeps running after this fn returns.
    models::init_globals(
        runtime,
        client,
        channels.data,
        channels.status,
        persist_state,
        config.key_to_action.clone(),
    );

    0
}

/// Called by the C++ main after the QML engine has loaded but before `exec()`.
/// Fires the Zaparoo Core service start (`MiSTer` only, no-op on desktop).
#[no_mangle]
pub extern "C" fn zaparoo_rust_post_qt_start() {
    mister_runtime::ensure_core_service_running();
}
