// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0

use cxx_qt_build::{CxxQtBuilder, QmlModule};

fn main() {
    // cxx_qt_build compiles the CXX-Qt bridge code and registers the
    // Zaparoo.Browse QML module. Qt is located via the QMAKE env var
    // (set by ZaparooRust.cmake for ARM32 cross) or PATH qmake6 on desktop.
    //
    // 0.8 builder shape: new_qml_module() takes the QmlModule up front and
    // auto-links Qt Core + Qml; .files([...]) replaces the 0.7 rust_files
    // field on QmlModule (removed in 0.8).
    let builder = CxxQtBuilder::new_qml_module(
        QmlModule::new("Zaparoo.Browse")
            .version(1, 0)
            // QAbstractListModel-derived singletons (CategoriesModel, SystemsModel,
            // GamesModel, BrowseModel) need this for qmllint to follow the
            // prototype chain back to QObject.
            .depend("QtQml.Models"),
    )
    .qt_module("Gui")
    .qt_module("Quick")
    .qt_module("QuickControls2")
    .files([
        "src/models/categories.rs",
        "src/models/systems.rs",
        "src/models/games.rs",
        "src/models/browse.rs",
        "src/models/app_state.rs",
        "src/models/app_status.rs",
        "src/models/hub_state.rs",
        "src/models/systems_state.rs",
        "src/models/games_state.rs",
        "src/models/input.rs",
        "src/models/log_upload.rs",
        "src/models/media_status.rs",
        "src/models/platform.rs",
        "src/models/qr_code.rs",
        "src/models/recents.rs",
        "src/models/recents_state.rs",
        "src/models/runtime.rs",
        "src/models/settings.rs",
        "src/models/system_status.rs",
    ]);

    // SAFETY: cc_builder is unsafe in 0.8 because cxx-qt makes no stability
    // guarantees about the cc::Build instance. We only adjust the include
    // path so the generated bridge code can find model_includes.h; we do
    // not mutate flags or sources cxx-qt depends on.
    let builder = unsafe {
        builder.cc_builder(|cc| {
            cc.include("src/models");
        })
    };
    builder.build();

    println!("cargo:rerun-if-env-changed=ZAPAROO_RUNTIME");
    println!("cargo:rerun-if-env-changed=ZAPAROO_DEV_BUILD");

    println!("cargo:rustc-check-cfg=cfg(zaparoo_runtime, values(\"mister\"))");
    println!("cargo:rustc-check-cfg=cfg(dev_build)");
    if let Ok(rt) = std::env::var("ZAPAROO_RUNTIME") {
        if rt.trim().eq_ignore_ascii_case("mister") {
            println!("cargo:rustc-cfg=zaparoo_runtime=\"mister\"");
        } else {
            println!(
                "cargo:warning=ignoring unknown ZAPAROO_RUNTIME value: {rt:?} (expected \"mister\")"
            );
        }
    }
    if std::env::var("ZAPAROO_DEV_BUILD").is_ok() {
        println!("cargo:rustc-cfg=dev_build");
    }
}
