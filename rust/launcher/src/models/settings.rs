// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//
// `Browse.Settings` — gamepad-accessible settings form. The model is the
// seam between the QML form and the persistence/runtime side: it owns
// curated picker lists, remembers what the user picked, and on MiSTer
// re-runs `vmode` when the resolution changes so the framebuffer updates
// immediately.
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
//   * `available_button_layouts` — CONSTANT. Lowercase directory names
//     used to compose resources/images/buttons/<layout>/Button*.png.
//   * `current_button_layout` — READ + NOTIFY, persisted. Defaults to
//     "nintendo" so existing state files keep the current asset path.
//   * `current_mouse_enabled` — READ + NOTIFY, persisted. Defaults to true
//     so existing installs keep the visible cursor and mouse hit targets.
//
// Setters write to disk first so a runtime crash mid-apply still leaves
// the choice persisted. Resolution then runs `vmode` on MiSTer; button
// layout only changes the QML resource path used by help-bar icons, and
// mouse support drives the QML cursor/input blocker.

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
const MISTER_RESOLUTIONS: &[&str] = &["", "1280x720", "1920x1080", "640x480", "1920x1440"];
const BUTTON_LAYOUTS: &[&str] = &["nintendo", "xbox", "sony"];
const DEFAULT_BUTTON_LAYOUT: &str = "nintendo";

#[derive(Default)]
pub struct SettingsRust {
    is_mister: bool,
    available_resolutions: QStringList,
    current_resolution: QString,
    available_button_layouts: QStringList,
    current_button_layout: QString,
    current_mouse_enabled: bool,
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
        #[qproperty(QStringList, available_button_layouts, READ, CONSTANT)]
        #[qproperty(QString, current_button_layout, READ, WRITE = set_button_layout, NOTIFY)]
        #[qproperty(bool, current_mouse_enabled, READ, WRITE = set_mouse_enabled, NOTIFY)]
        type Settings = super::SettingsRust;

        #[qinvokable]
        fn set_resolution(self: Pin<&mut Settings>, value: QString);

        #[qinvokable]
        fn set_button_layout(self: Pin<&mut Settings>, value: QString);

        #[qinvokable]
        fn set_mouse_enabled(self: Pin<&mut Settings>, value: bool);
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
        self.as_mut().rust_mut().available_button_layouts = button_layouts();
        self.as_mut().rust_mut().current_button_layout =
            QString::from(normalize_button_layout(&snapshot.button_layout));
        self.as_mut().rust_mut().current_mouse_enabled = snapshot.mouse_enabled;
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

    fn set_button_layout(mut self: Pin<&mut Self>, value: QString) {
        let value_str = normalize_button_layout(&value.to_string()).to_string();
        if self.current_button_layout.to_string() == value_str {
            return;
        }
        persist_settings(|s| s.button_layout.clone_from(&value_str));
        self.as_mut().rust_mut().current_button_layout = QString::from(value_str.as_str());
        self.as_mut().current_button_layout_changed();
    }

    fn set_mouse_enabled(mut self: Pin<&mut Self>, value: bool) {
        if self.current_mouse_enabled == value {
            return;
        }
        persist_settings(|s| s.mouse_enabled = value);
        self.as_mut().rust_mut().current_mouse_enabled = value;
        self.as_mut().current_mouse_enabled_changed();
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

fn button_layouts() -> QStringList {
    let mut list = QStringList::default();
    for layout in BUTTON_LAYOUTS {
        list.append(QString::from(*layout));
    }
    list
}

fn normalize_button_layout(value: &str) -> &'static str {
    let trimmed = value.trim();
    BUTTON_LAYOUTS
        .iter()
        .copied()
        .find(|layout| *layout == trimmed)
        .unwrap_or(DEFAULT_BUTTON_LAYOUT)
}

#[cfg(test)]
mod tests {
    use super::{
        button_layouts, curated_resolutions, normalize_button_layout, BUTTON_LAYOUTS,
        DEFAULT_BUTTON_LAYOUT, MISTER_RESOLUTIONS,
    };

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

    #[test]
    fn button_layouts_preserve_order() {
        let list = button_layouts();
        let collected: Vec<String> = list.iter().map(String::from).collect();
        let expected: Vec<String> = BUTTON_LAYOUTS.iter().map(|s| (*s).to_string()).collect();
        assert_eq!(collected, expected);
    }

    #[test]
    fn button_layout_values_are_lowercase() {
        for layout in BUTTON_LAYOUTS {
            assert_eq!(*layout, layout.to_ascii_lowercase());
        }
    }

    #[test]
    fn button_layout_normalization_defaults_to_nintendo() {
        assert_eq!(normalize_button_layout(""), DEFAULT_BUTTON_LAYOUT);
        assert_eq!(normalize_button_layout("playstation"), DEFAULT_BUTTON_LAYOUT);
        assert_eq!(normalize_button_layout("xbox"), "xbox");
    }
}
