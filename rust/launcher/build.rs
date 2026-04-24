// Zaparoo Launcher
// Copyright (c) 2026 The Zaparoo Project Contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0

use cxx_qt_build::{CxxQtBuilder, QmlModule};

fn main() {
    // cxx_qt_build compiles the CXX-Qt bridge code and registers the
    // Zaparoo.Browse QML module. Qt is located via the QMAKE env var
    // (set by ZaparooRust.cmake for ARM32 cross) or PATH qmake6 on desktop.
    CxxQtBuilder::new()
        .qt_module("Core")
        .qt_module("Gui")
        .qt_module("Qml")
        .qt_module("Quick")
        .qt_module("QuickControls2")
        // Expose the models directory so generated C++ can find model_includes.h.
        .cc_builder(|cc| {
            cc.include("src/models");
        })
        .qml_module(QmlModule::<&str, &str> {
            uri: "Zaparoo.Browse",
            version_major: 1,
            version_minor: 0,
            rust_files: &[
                "src/models/categories.rs",
                "src/models/systems.rs",
                "src/models/games.rs",
                "src/models/browse.rs",
            ],
            qml_files: &[],
            ..Default::default()
        })
        .build();

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
