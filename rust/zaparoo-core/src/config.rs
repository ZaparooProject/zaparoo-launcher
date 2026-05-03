// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0

use crate::input_actions;
use serde::Deserialize;
use std::collections::HashMap;
use std::io::Write;
use std::path::Path;
use tracing::warn;

#[derive(Debug, Clone)]
pub struct Config {
    pub core_endpoint: String,
    pub video_width: u32,
    pub video_height: u32,
    pub debug_logging: bool,
    /// Language override for the UI, passed to `QTranslator` via the
    /// C++ entry point. Empty string means "follow `QLocale::system()`";
    /// any non-empty value is treated as a BCP-47 tag (e.g. `en_US`,
    /// `ja`, `de_DE`). Populated from `[general] language` in the config
    /// file; the literal `auto` is normalised to an empty string.
    pub language: String,
    /// Qt key code → action name. Built at load time by merging
    /// `[input.keyboard]` overrides onto `input_actions::default_bindings()`
    /// and inverting.
    pub key_to_action: HashMap<i32, String>,
    /// Durable mirror of launcher-owned settings. These stay in
    /// `launcher.toml` so they survive `MiSTer`'s `/tmp` lifecycle.
    pub settings: SettingsConfig,
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct SettingsConfig {
    pub button_layout: Option<String>,
    pub mouse_enabled: Option<bool>,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            core_endpoint: "ws://localhost:7497/api/v0.1".into(),
            video_width: 1920,
            video_height: 1080,
            debug_logging: false,
            language: String::new(),
            key_to_action: input_actions::invert(&input_actions::default_bindings()),
            settings: SettingsConfig::default(),
        }
    }
}

#[derive(Deserialize, Default)]
struct RawConfig {
    #[serde(default)]
    general: RawGeneral,
    #[serde(default)]
    core: RawCore,
    #[serde(default)]
    video: RawVideo,
    #[serde(default)]
    logging: RawLogging,
    #[serde(default)]
    input: RawInput,
    #[serde(default)]
    settings: RawSettings,
}

#[derive(Deserialize, Default)]
struct RawGeneral {
    language: Option<String>,
}

#[derive(Deserialize, Default)]
struct RawCore {
    endpoint: Option<String>,
}

#[derive(Deserialize, Default)]
struct RawVideo {
    width: Option<u32>,
    height: Option<u32>,
}

#[derive(Deserialize, Default)]
struct RawLogging {
    debug: Option<bool>,
}

#[derive(Deserialize, Default)]
struct RawInput {
    #[serde(default)]
    keyboard: HashMap<String, Vec<String>>,
}

#[derive(Deserialize, Default)]
struct RawSettings {
    button_layout: Option<String>,
    mouse_enabled: Option<bool>,
}

pub fn load_config(path: &Path) -> Config {
    let mut cfg = Config::default();
    let Ok(src) = std::fs::read_to_string(path) else {
        return cfg;
    };
    let raw: RawConfig = match toml::from_str(&src) {
        Ok(r) => r,
        Err(e) => {
            warn!("config parse error in {}: {e}", path.display());
            return cfg;
        }
    };
    if let Some(lang) = raw.general.language {
        // "auto" is the documented opt-in to system-locale detection; treat
        // it as an empty override so the C++ side just calls `QLocale::system()`.
        cfg.language = if lang.eq_ignore_ascii_case("auto") {
            String::new()
        } else {
            lang
        };
    }
    if let Some(ep) = raw.core.endpoint {
        cfg.core_endpoint = ep;
    }
    // Env-var override wins over both the built-in default and any
    // launcher.toml setting. Used by run-dev.sh to point the launcher at
    // mock-core (port 27497) without forcing the user to maintain a
    // throwaway launcher.toml.
    if let Ok(ep) = std::env::var("ZAPAROO_CORE_ENDPOINT") {
        if !ep.is_empty() {
            cfg.core_endpoint = ep;
        }
    }
    if let Some(w) = raw.video.width {
        cfg.video_width = w;
    }
    if let Some(h) = raw.video.height {
        cfg.video_height = h;
    }
    if let Some(d) = raw.logging.debug {
        cfg.debug_logging = d;
    }
    if !raw.input.keyboard.is_empty() {
        let mut merged = input_actions::default_bindings();
        for (action, keys) in raw.input.keyboard {
            merged.insert(action, keys);
        }
        cfg.key_to_action = input_actions::invert(&merged);
    }
    cfg.settings = SettingsConfig {
        button_layout: raw
            .settings
            .button_layout
            .map(|value| value.trim().to_string()),
        mouse_enabled: raw.settings.mouse_enabled,
    };
    cfg
}

pub fn save_settings_mirror(
    path: &Path,
    language: &str,
    button_layout: &str,
    mouse_enabled: bool,
    debug_logging: bool,
) -> Result<(), String> {
    let mut table = if path.exists() {
        let src = std::fs::read_to_string(path)
            .map_err(|e| format!("could not read {}: {e}", path.display()))?;
        toml::from_str::<toml::Table>(&src)
            .map_err(|e| format!("config parse error in {}: {e}", path.display()))?
    } else {
        toml::Table::new()
    };

    let general_value = table
        .entry("general")
        .or_insert_with(|| toml::Value::Table(toml::Table::new()));
    let Some(general) = general_value.as_table_mut() else {
        return Err(format!(
            "config key [general] in {} is not a table",
            path.display()
        ));
    };
    general.insert(
        "language".into(),
        toml::Value::String(normalize_language_override(language)),
    );

    let settings_value = table
        .entry("settings")
        .or_insert_with(|| toml::Value::Table(toml::Table::new()));
    let Some(settings) = settings_value.as_table_mut() else {
        return Err(format!(
            "config key [settings] in {} is not a table",
            path.display()
        ));
    };
    settings.insert(
        "button_layout".into(),
        toml::Value::String(button_layout.trim().to_string()),
    );
    settings.insert("mouse_enabled".into(), toml::Value::Boolean(mouse_enabled));

    let logging_value = table
        .entry("logging")
        .or_insert_with(|| toml::Value::Table(toml::Table::new()));
    let Some(logging) = logging_value.as_table_mut() else {
        return Err(format!(
            "config key [logging] in {} is not a table",
            path.display()
        ));
    };
    logging.insert("debug".into(), toml::Value::Boolean(debug_logging));

    let serialized =
        toml::to_string(&table).map_err(|e| format!("config serialisation failed: {e}"))?;
    write_atomic(path, serialized.as_bytes())
        .map_err(|e| format!("could not write {}: {e}", path.display()))
}

fn normalize_language_override(value: &str) -> String {
    let trimmed = value.trim();
    if trimmed.is_empty() || trimmed.eq_ignore_ascii_case("auto") {
        "auto".into()
    } else {
        trimmed.into()
    }
}

fn write_atomic(path: &Path, contents: &[u8]) -> std::io::Result<()> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    let tmp = tmp_sibling(path);
    let write_result = std::fs::File::create(&tmp).and_then(|mut file| {
        file.write_all(contents)?;
        file.sync_all()?;
        Ok(())
    });
    if let Err(e) = write_result {
        let _ = std::fs::remove_file(&tmp);
        return Err(e);
    }
    if let Err(e) = std::fs::rename(&tmp, path) {
        let _ = std::fs::remove_file(&tmp);
        return Err(e);
    }
    Ok(())
}

fn tmp_sibling(path: &Path) -> std::path::PathBuf {
    let pid = std::process::id();
    let tid = format!("{:?}", std::thread::current().id());
    let tid_clean: String = tid.chars().filter(char::is_ascii_alphanumeric).collect();
    let suffix = format!(".tmp.{pid}.{tid_clean}");
    let mut buf = path.as_os_str().to_owned();
    buf.push(&suffix);
    std::path::PathBuf::from(buf)
}

#[cfg(test)]
mod tests {
    #![allow(
        clippy::expect_used,
        clippy::unwrap_used,
        clippy::panic,
        reason = "tests should fail-fast on unexpected errors"
    )]

    use super::{load_config, save_settings_mirror, Config};
    use std::io::Write;

    fn write_tmp(contents: &str) -> tempfile::NamedTempFile {
        let mut f = tempfile::NamedTempFile::new().expect("tempfile");
        f.write_all(contents.as_bytes()).expect("write");
        f
    }

    #[test]
    fn defaults_match_production_values() {
        let cfg = Config::default();
        assert_eq!(cfg.core_endpoint, "ws://localhost:7497/api/v0.1");
        assert_eq!(cfg.video_width, 1920);
        assert_eq!(cfg.video_height, 1080);
        assert!(!cfg.debug_logging);
        assert_eq!(cfg.language, "");
        assert_eq!(cfg.settings.button_layout, None);
        assert_eq!(cfg.settings.mouse_enabled, None);
        // Default keyboard bindings populate the map.
        assert!(!cfg.key_to_action.is_empty());
    }

    #[test]
    fn language_auto_is_normalised_to_empty() {
        let f = write_tmp("[general]\nlanguage = \"auto\"\n");
        let cfg = load_config(f.path());
        assert_eq!(cfg.language, "");
    }

    #[test]
    fn language_auto_is_case_insensitive() {
        let f = write_tmp("[general]\nlanguage = \"AUTO\"\n");
        let cfg = load_config(f.path());
        assert_eq!(cfg.language, "");
    }

    #[test]
    fn language_explicit_code_passes_through() {
        let f = write_tmp("[general]\nlanguage = \"ja_JP\"\n");
        let cfg = load_config(f.path());
        assert_eq!(cfg.language, "ja_JP");
    }

    #[test]
    fn keyboard_override_replaces_default_for_that_action() {
        use crate::input_actions::{actions, qt_key_code};

        let toml = r#"
            [input.keyboard]
            accept = ["Space"]
        "#;
        let f = write_tmp(toml);
        let cfg = load_config(f.path());
        let space = qt_key_code("Space").unwrap();
        let enter = qt_key_code("Enter").unwrap();
        assert_eq!(
            cfg.key_to_action.get(&space).map(String::as_str),
            Some(actions::ACCEPT)
        );
        // Enter is no longer bound to accept: the user's list replaced
        // the default for this action entirely.
        assert!(!cfg.key_to_action.contains_key(&enter));
        // Cancel defaults survive untouched.
        let escape = qt_key_code("Escape").unwrap();
        assert_eq!(
            cfg.key_to_action.get(&escape).map(String::as_str),
            Some(actions::CANCEL)
        );
    }

    #[test]
    fn missing_file_returns_defaults() {
        let cfg = load_config(std::path::Path::new("/definitely/does/not/exist.toml"));
        assert_eq!(cfg.video_width, 1920);
    }

    #[test]
    fn malformed_toml_returns_defaults() {
        let f = write_tmp("this is not = valid toml [[[");
        let cfg = load_config(f.path());
        assert_eq!(cfg.core_endpoint, Config::default().core_endpoint);
    }

    #[test]
    fn partial_config_merges_with_defaults() {
        let f = write_tmp("[video]\nwidth = 1280\n");
        let cfg = load_config(f.path());
        assert_eq!(cfg.video_width, 1280);
        assert_eq!(cfg.video_height, 1080); // default preserved
        assert_eq!(cfg.core_endpoint, Config::default().core_endpoint);
    }

    #[test]
    fn full_config_overrides_all_fields() {
        let toml = r#"
            [general]
            language = "it_IT"

            [core]
            endpoint = "ws://example.com/api"

            [video]
            width = 640
            height = 480

            [logging]
            debug = true

            [settings]
            button_layout = "c"
            mouse_enabled = false
        "#;
        let f = write_tmp(toml);
        let cfg = load_config(f.path());
        assert_eq!(cfg.language, "it_IT");
        assert_eq!(cfg.core_endpoint, "ws://example.com/api");
        assert_eq!(cfg.video_width, 640);
        assert_eq!(cfg.video_height, 480);
        assert!(cfg.debug_logging);
        assert_eq!(cfg.settings.button_layout.as_deref(), Some("c"));
        assert_eq!(cfg.settings.mouse_enabled, Some(false));
    }

    #[test]
    fn empty_file_returns_defaults() {
        let f = write_tmp("");
        let cfg = load_config(f.path());
        assert_eq!(cfg.video_width, Config::default().video_width);
    }

    #[test]
    fn save_settings_mirror_creates_sections() {
        let dir = tempfile::tempdir().expect("tempdir");
        let path = dir.path().join("launcher.toml");
        save_settings_mirror(&path, "it_IT", "b", false, true).expect("save");
        let cfg = load_config(&path);
        assert_eq!(cfg.language, "it_IT");
        assert_eq!(cfg.settings.button_layout.as_deref(), Some("b"));
        assert_eq!(cfg.settings.mouse_enabled, Some(false));
        assert!(cfg.debug_logging);
    }

    #[test]
    fn save_settings_mirror_preserves_other_sections() {
        let f = write_tmp(
            "[core]\nendpoint = \"ws://example.com/api\"\n[video]\nwidth = 1280\nheight = 720\n",
        );
        save_settings_mirror(f.path(), "en", "a", true, false).expect("save");
        let cfg = load_config(f.path());
        assert_eq!(cfg.language, "en");
        assert_eq!(cfg.core_endpoint, "ws://example.com/api");
        assert_eq!(cfg.video_width, 1280);
        assert_eq!(cfg.video_height, 720);
        assert_eq!(cfg.settings.button_layout.as_deref(), Some("a"));
        assert_eq!(cfg.settings.mouse_enabled, Some(true));
        assert!(!cfg.debug_logging);
    }

    #[test]
    fn save_settings_mirror_normalizes_auto() {
        let f = write_tmp("");
        save_settings_mirror(f.path(), "", "c", false, true).expect("save");
        let written = std::fs::read_to_string(f.path()).expect("read");
        assert!(written.contains("language = \"auto\""));
        assert!(written.contains("button_layout = \"c\""));
        assert!(written.contains("mouse_enabled = false"));
        assert!(written.contains("debug = true"));
        let cfg = load_config(f.path());
        assert_eq!(cfg.language, "");
        assert_eq!(cfg.settings.button_layout.as_deref(), Some("c"));
        assert_eq!(cfg.settings.mouse_enabled, Some(false));
        assert!(cfg.debug_logging);
    }

    // Single test because std::env is process-global; splitting into
    // separate #[test]s would race when nextest runs them in parallel.
    #[test]
    fn env_var_overrides_endpoint_and_empty_string_is_ignored() {
        const KEY: &str = "ZAPAROO_CORE_ENDPOINT";
        let prior = std::env::var(KEY).ok();
        let f = write_tmp("[core]\nendpoint = \"ws://example.com/api\"\n");

        std::env::set_var(KEY, "ws://localhost:27497/api/v0.1");
        assert_eq!(
            load_config(f.path()).core_endpoint,
            "ws://localhost:27497/api/v0.1"
        );

        // Empty value is treated as unset so accidentally exporting an
        // empty ZAPAROO_CORE_ENDPOINT in a shell rc file doesn't blank
        // out the user's launcher.toml.
        std::env::set_var(KEY, "");
        assert_eq!(load_config(f.path()).core_endpoint, "ws://example.com/api");

        match prior {
            Some(v) => std::env::set_var(KEY, v),
            None => std::env::remove_var(KEY),
        }
    }
}
