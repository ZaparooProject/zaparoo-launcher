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
//   * `available_languages` — CONSTANT. Curated language tags plus the
//     `auto` sentinel. The runtime translator is still startup-only, so
//     this setting applies on the next launch.
//   * `current_language` — READ + NOTIFY. Mirrors `[general].language`
//     from launcher.toml and is also recorded in persisted state so the
//     settings snapshot stays coherent.
//   * `available_button_layouts` — CONSTANT. Single-letter ids used to
//     compose resources/images/buttons/<layout>/Button*.png. Style A is
//     the legacy Nintendo-style glyph set, B is the Xbox-style set, C
//     is the Sony-style set; the user-facing labels are "Style A/B/C"
//     (see `SettingsScreen.qml::_buttonLayoutDisplay`) so the picker
//     reads as a neutral aesthetic choice rather than a vendor pick.
//   * `current_button_layout` — READ + NOTIFY, persisted. Defaults to
//     "a" — the new id for the previous "nintendo" asset directory.
//     `normalize_button_layout` migrates legacy persisted values
//     (`nintendo`/`xbox`/`sony`) to the new ids so users keep their
//     selection across the rename.
//   * `current_mouse_enabled` — READ + NOTIFY, persisted. Defaults to true
//     so existing installs keep the visible cursor and mouse hit targets.
//   * `current_debug_logging` — READ + NOTIFY, persisted. Defaults to false.
//     Toggling it writes `[logging] debug = …` into launcher.toml; the
//     tracing subscriber is built once at startup so the change only takes
//     effect on the next launch (mirrors how `language` works).
//
// Launcher-owned durable settings are mirrored into both `state.toml`
// and `launcher.toml`. `state.toml` keeps the in-process snapshot
// coherent; `launcher.toml` is the durable copy that survives MiSTer's
// `/tmp` lifecycle. Resolution is intentionally excluded from the config
// mirror for now and remains state/session-backed only because startup
// mode switching is not trusted yet. Button layout only changes the QML
// resource path used by help-bar icons, mouse support drives the QML
// cursor/input blocker, and language still takes effect on the next
// launch because Qt installs translators only at startup.

use crate::mister_runtime;
use crate::models::{with_persist_mut, with_persist_read};
use cxx_qt::{CxxQtType, Initialize};
use cxx_qt_lib::{QString, QStringList};
use std::pin::Pin;
use tracing::warn;
use zaparoo_core::config::{load_config, save_settings_mirror, Config};
use zaparoo_core::persist::{self, SettingsState};
use zaparoo_core::platform_paths::config_file_path;
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
const LANGUAGES: &[&str] = &["auto", "en", "it_IT"];
const DEFAULT_LANGUAGE: &str = "auto";
const BUTTON_LAYOUTS: &[&str] = &["a", "b", "c"];
const DEFAULT_BUTTON_LAYOUT: &str = "a";

#[derive(Default)]
pub struct SettingsRust {
    is_mister: bool,
    available_resolutions: QStringList,
    current_resolution: QString,
    available_languages: QStringList,
    current_language: QString,
    available_button_layouts: QStringList,
    current_button_layout: QString,
    current_mouse_enabled: bool,
    current_debug_logging: bool,
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
        #[qproperty(QStringList, available_languages, READ, CONSTANT)]
        #[qproperty(QString, current_language, READ, WRITE = set_language, NOTIFY)]
        #[qproperty(QStringList, available_button_layouts, READ, CONSTANT)]
        #[qproperty(QString, current_button_layout, READ, WRITE = set_button_layout, NOTIFY)]
        #[qproperty(bool, current_mouse_enabled, READ, WRITE = set_mouse_enabled, NOTIFY)]
        #[qproperty(bool, current_debug_logging, READ, WRITE = set_debug_logging, NOTIFY)]
        type Settings = super::SettingsRust;

        #[qinvokable]
        fn set_resolution(self: Pin<&mut Settings>, value: QString);

        #[qinvokable]
        fn set_language(self: Pin<&mut Settings>, value: QString);

        #[qinvokable]
        fn set_button_layout(self: Pin<&mut Settings>, value: QString);

        #[qinvokable]
        fn set_mouse_enabled(self: Pin<&mut Settings>, value: bool);

        #[qinvokable]
        fn set_debug_logging(self: Pin<&mut Settings>, value: bool);
    }

    impl cxx_qt::Initialize for Settings {}
}

impl Initialize for ffi::Settings {
    fn initialize(mut self: Pin<&mut Self>) {
        let snapshot: SettingsState = with_persist_read(|s| s.settings.clone());
        let config_path = config_file_path();
        let is_mister = runtime::current().is_mister();
        let config = load_config(&config_path);
        let merged = merge_settings(&snapshot, &config);
        persist_if_changed(&snapshot, &merged);
        mirror_settings_to_config(&config_path, &merged);
        self.as_mut().rust_mut().is_mister = is_mister;
        self.as_mut().rust_mut().available_resolutions = if is_mister {
            curated_resolutions()
        } else {
            QStringList::default()
        };
        self.as_mut().rust_mut().current_resolution = QString::from(merged.resolution.as_str());
        self.as_mut().rust_mut().available_languages = languages();
        self.as_mut().rust_mut().current_language = QString::from(merged.language.as_str());
        self.as_mut().rust_mut().available_button_layouts = button_layouts();
        self.as_mut().rust_mut().current_button_layout =
            QString::from(merged.button_layout.as_str());
        self.as_mut().rust_mut().current_mouse_enabled = merged.mouse_enabled;
        self.as_mut().rust_mut().current_debug_logging = merged.debug_logging;
    }
}

impl ffi::Settings {
    fn set_resolution(mut self: Pin<&mut Self>, value: QString) {
        if self.current_resolution == value {
            return;
        }
        let value_str = value.to_string();
        // Persist before `vmode` so a runtime fault mid-switch still
        // leaves the session/state snapshot coherent for the next run.
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

    #[allow(
        clippy::needless_pass_by_value,
        reason = "cxx-qt qinvokable signature requires QString by value"
    )]
    fn set_language(mut self: Pin<&mut Self>, value: QString) {
        let value_str = normalize_language(&value.to_string()).to_string();
        if self.current_language.to_string() == value_str {
            return;
        }
        let snapshot = persist_settings(|s| s.language.clone_from(&value_str));
        mirror_settings_to_config(&config_file_path(), &snapshot.settings);
        self.as_mut().rust_mut().current_language = QString::from(value_str.as_str());
        self.as_mut().current_language_changed();
    }

    #[allow(
        clippy::needless_pass_by_value,
        reason = "cxx-qt qinvokable signature requires QString by value"
    )]
    fn set_button_layout(mut self: Pin<&mut Self>, value: QString) {
        let value_str = normalize_button_layout(&value.to_string()).to_string();
        if self.current_button_layout.to_string() == value_str {
            return;
        }
        let snapshot = persist_settings(|s| s.button_layout.clone_from(&value_str));
        mirror_settings_to_config(&config_file_path(), &snapshot.settings);
        self.as_mut().rust_mut().current_button_layout = QString::from(value_str.as_str());
        self.as_mut().current_button_layout_changed();
    }

    fn set_mouse_enabled(mut self: Pin<&mut Self>, value: bool) {
        if self.current_mouse_enabled == value {
            return;
        }
        let snapshot = persist_settings(|s| s.mouse_enabled = value);
        mirror_settings_to_config(&config_file_path(), &snapshot.settings);
        self.as_mut().rust_mut().current_mouse_enabled = value;
        self.as_mut().current_mouse_enabled_changed();
    }

    fn set_debug_logging(mut self: Pin<&mut Self>, value: bool) {
        if self.current_debug_logging == value {
            return;
        }
        let snapshot = persist_settings(|s| s.debug_logging = value);
        mirror_settings_to_config(&config_file_path(), &snapshot.settings);
        self.as_mut().rust_mut().current_debug_logging = value;
        self.as_mut().current_debug_logging_changed();
    }
}

fn persist_settings<F: FnOnce(&mut SettingsState)>(mutator: F) -> persist::PersistedState {
    let snapshot = with_persist_mut(|s| {
        mutator(&mut s.settings);
        s.clone()
    });
    persist::save(&snapshot);
    snapshot
}

fn persist_if_changed(current: &SettingsState, merged: &SettingsState) {
    if current == merged {
        return;
    }
    let snapshot = with_persist_mut(|s| {
        s.settings = merged.clone();
        s.clone()
    });
    persist::save(&snapshot);
}

fn mirror_settings_to_config(config_path: &std::path::Path, settings: &SettingsState) {
    if let Err(e) = save_settings_mirror(
        config_path,
        settings.language.as_str(),
        settings.button_layout.as_str(),
        settings.mouse_enabled,
        settings.debug_logging,
    ) {
        warn!(
            "could not save settings mirror to {}: {e}",
            config_path.display()
        );
    }
}

fn merge_settings(snapshot: &SettingsState, config: &Config) -> SettingsState {
    SettingsState {
        resolution: snapshot.resolution.clone(),
        language: normalize_language(&config.language).to_string(),
        button_layout: normalize_button_layout(
            config
                .settings
                .button_layout
                .as_deref()
                .unwrap_or(snapshot.button_layout.as_str()),
        )
        .to_string(),
        mouse_enabled: config
            .settings
            .mouse_enabled
            .unwrap_or(snapshot.mouse_enabled),
        // Config wins so launcher.toml is the durable source of truth on
        // MiSTer (state.toml lives on tmpfs).
        debug_logging: config.debug_logging,
    }
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

fn languages() -> QStringList {
    let mut list = QStringList::default();
    for language in LANGUAGES {
        list.append(QString::from(*language));
    }
    list
}

fn normalize_language(value: &str) -> &str {
    let trimmed = value.trim();
    if trimmed.is_empty() || trimmed.eq_ignore_ascii_case("auto") {
        return DEFAULT_LANGUAGE;
    }
    LANGUAGES
        .iter()
        .copied()
        .find(|language| *language == trimmed)
        .unwrap_or(DEFAULT_LANGUAGE)
}

fn normalize_button_layout(value: &str) -> &'static str {
    let trimmed = value.trim();
    // Legacy alias map: state files written by builds before the
    // a/b/c rename hold "nintendo"/"xbox"/"sony"; preserve the user's
    // pick instead of silently snapping back to the default.
    let migrated = match trimmed {
        "nintendo" => "a",
        "xbox" => "b",
        "sony" => "c",
        other => other,
    };
    BUTTON_LAYOUTS
        .iter()
        .copied()
        .find(|layout| *layout == migrated)
        .unwrap_or(DEFAULT_BUTTON_LAYOUT)
}

#[cfg(test)]
mod tests {
    use super::{
        button_layouts, curated_resolutions, languages, normalize_button_layout,
        normalize_language, BUTTON_LAYOUTS, DEFAULT_BUTTON_LAYOUT, DEFAULT_LANGUAGE, LANGUAGES,
        MISTER_RESOLUTIONS,
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
    fn languages_preserve_order() {
        let list = languages();
        let collected: Vec<String> = list.iter().map(String::from).collect();
        let expected: Vec<String> = LANGUAGES.iter().map(|s| (*s).to_string()).collect();
        assert_eq!(collected, expected);
    }

    #[test]
    fn language_normalization_defaults_to_auto() {
        assert_eq!(normalize_language(""), DEFAULT_LANGUAGE);
        assert_eq!(normalize_language("auto"), DEFAULT_LANGUAGE);
        assert_eq!(normalize_language("AUTO"), DEFAULT_LANGUAGE);
        assert_eq!(normalize_language("fr"), DEFAULT_LANGUAGE);
        assert_eq!(normalize_language("it_IT"), "it_IT");
    }

    #[test]
    fn button_layout_values_are_lowercase() {
        for layout in BUTTON_LAYOUTS {
            assert_eq!(*layout, layout.to_ascii_lowercase());
        }
    }

    #[test]
    fn button_layout_normalization_defaults_to_a() {
        assert_eq!(normalize_button_layout(""), DEFAULT_BUTTON_LAYOUT);
        assert_eq!(
            normalize_button_layout("playstation"),
            DEFAULT_BUTTON_LAYOUT
        );
        assert_eq!(normalize_button_layout("b"), "b");
    }

    #[test]
    fn button_layout_migrates_legacy_vendor_ids() {
        assert_eq!(normalize_button_layout("nintendo"), "a");
        assert_eq!(normalize_button_layout("xbox"), "b");
        assert_eq!(normalize_button_layout("sony"), "c");
    }
}
