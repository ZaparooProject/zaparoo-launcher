// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//
// `Browse.Settings` — gamepad-accessible settings form. First field is
// Resolution (MiSTer only). The model is the seam between the QML form
// and the persistence/runtime side: it owns the curated picker list,
// remembers what the user picked, and on MiSTer re-runs `vmode` so the
// framebuffer changes immediately.
//
// Field design:
//   * `is_mister` — CONSTANT. Drives whether MiSTer-only fields render
//     in the form.
//   * `available_resolutions` — CONSTANT. Empty off MiSTer; on MiSTer,
//     the curated picker list. Order matters: it's the cycle order in
//     the UI's left/right cycler.
//   * `current_resolution` — READ + NOTIFY, persisted. Empty means "use
//     `[mister.video_*]` defaults from launcher.toml". The Settings
//     screen renders that empty value as `qsTr("Default")`.
//
// `set_resolution()` is the only mutator. It writes to disk first
// (so a runtime crash mid-`vmode` still leaves the choice persisted)
// and then runs `vmode` on MiSTer. On desktop the call is a no-op
// beyond the persist write — the field shouldn't be reachable from
// the form, but the call site is safe either way.

use crate::mister_runtime;
use crate::models::{with_persist_mut, with_persist_read};
use cxx_qt::{CxxQtType, Initialize};
use cxx_qt_lib::{QString, QStringList};
use std::pin::Pin;
use zaparoo_core::persist::{self, SettingsState};
use zaparoo_core::runtime;

/// Curated `MiSTer` resolution choices. Order is the left/right cycle
/// order in the form. Keep the list short — every entry is a literal
/// the user can crash a CRT scaler with if it doesn't suit their
/// monitor — and ASCII-only so the QML side never needs to translate
/// the strings (they're not user-facing labels, they're keys). The
/// empty leading entry is the "use `launcher.toml` defaults" sentinel;
/// the form renders it as `qsTr("Default")` so users can cycle back
/// to no-override after picking a custom value.
const MISTER_RESOLUTIONS: &[&str] = &["", "1280x720", "1920x1080", "640x480"];

#[derive(Default)]
pub struct SettingsRust {
    is_mister: bool,
    available_resolutions: QStringList,
    current_resolution: QString,
}

#[cxx_qt::bridge]
pub mod ffi {
    unsafe extern "C++" {
        include!("model_includes.h");

        type QString = cxx_qt_lib::QString;
        type QStringList = cxx_qt_lib::QStringList;
    }

    unsafe extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qml_singleton]
        #[qproperty(bool, is_mister, READ, CONSTANT)]
        #[qproperty(QStringList, available_resolutions, READ, CONSTANT)]
        #[qproperty(QString, current_resolution, READ, WRITE = set_resolution, NOTIFY)]
        type Settings = super::SettingsRust;

        #[qinvokable]
        fn set_resolution(self: Pin<&mut Settings>, value: QString);
    }

    impl cxx_qt::Initialize for Settings {}
}

impl Initialize for ffi::Settings {
    fn initialize(mut self: Pin<&mut Self>) {
        let snapshot: SettingsState = with_persist_read(|s| s.settings.clone());
        let is_mister = runtime::current().is_mister();
        self.as_mut().rust_mut().is_mister = is_mister;
        self.as_mut().rust_mut().available_resolutions = if is_mister {
            curated_resolutions()
        } else {
            QStringList::default()
        };
        self.as_mut().rust_mut().current_resolution = QString::from(snapshot.resolution.as_str());
    }
}

impl ffi::Settings {
    fn set_resolution(mut self: Pin<&mut Self>, value: QString) {
        if self.current_resolution == value {
            return;
        }
        let value_str = value.to_string();
        // Persist first so a runtime fault mid-`vmode` still leaves the
        // user's choice on disk for the next launch.
        persist_settings(|s| s.resolution.clone_from(&value_str));
        // Apply the framebuffer change *before* notifying QML. `vmode`
        // swaps the linuxfb mode in place and leaves stale pixels in
        // any region Qt's dirty tracker doesn't already know about; the
        // QML side hooks `current_resolution_changed` to scrub them
        // with a one-frame full-screen repaint, which only works if
        // vmode has already finished by the time the signal fires.
        if let Some((w, h)) = mister_runtime::parse_resolution(&value_str) {
            mister_runtime::run_vmode(w, h);
        }
        self.as_mut().rust_mut().current_resolution = value;
        self.as_mut().current_resolution_changed();
    }
}

fn persist_settings<F: FnOnce(&mut SettingsState)>(mutator: F) {
    let snapshot = with_persist_mut(|s| {
        mutator(&mut s.settings);
        s.clone()
    });
    persist::save(&snapshot);
}

fn curated_resolutions() -> QStringList {
    let mut list = QStringList::default();
    for r in MISTER_RESOLUTIONS {
        list.append(QString::from(*r));
    }
    list
}

#[cfg(test)]
mod tests {
    use super::{curated_resolutions, MISTER_RESOLUTIONS};

    #[test]
    fn curated_resolutions_preserves_order() {
        let list = curated_resolutions();
        let collected: Vec<String> = list.iter().map(String::from).collect();
        let expected: Vec<String> = MISTER_RESOLUTIONS
            .iter()
            .map(|s| (*s).to_string())
            .collect();
        assert_eq!(collected, expected);
    }

    #[test]
    fn curated_list_contains_720p_and_1080p() {
        // Mostly a sanity guard — if a future edit silently drops the
        // two most-likely-to-work resolutions, this test catches it.
        let collected: Vec<&str> = MISTER_RESOLUTIONS.to_vec();
        assert!(collected.contains(&"1280x720"));
        assert!(collected.contains(&"1920x1080"));
    }
}
