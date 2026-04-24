// Zaparoo Launcher
// Copyright (c) 2026 The Zaparoo Project Contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0

use serde::Deserialize;
use std::path::Path;
use tracing::warn;

#[derive(Debug, Clone)]
pub struct Config {
    pub core_endpoint: String,
    pub video_width: u32,
    pub video_height: u32,
    pub debug_logging: bool,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            core_endpoint: "ws://localhost:7497/api/v0.1".into(),
            video_width: 1920,
            video_height: 1080,
            debug_logging: false,
        }
    }
}

#[derive(Deserialize, Default)]
struct RawConfig {
    #[serde(default)]
    core: RawCore,
    #[serde(default)]
    video: RawVideo,
    #[serde(default)]
    logging: RawLogging,
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
    if let Some(ep) = raw.core.endpoint {
        cfg.core_endpoint = ep;
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
    cfg
}

#[cfg(test)]
mod tests {
    #![allow(
        clippy::expect_used,
        clippy::unwrap_used,
        clippy::panic,
        reason = "tests should fail-fast on unexpected errors"
    )]

    use super::{load_config, Config};
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
            [core]
            endpoint = "ws://example.com/api"

            [video]
            width = 640
            height = 480

            [logging]
            debug = true
        "#;
        let f = write_tmp(toml);
        let cfg = load_config(f.path());
        assert_eq!(cfg.core_endpoint, "ws://example.com/api");
        assert_eq!(cfg.video_width, 640);
        assert_eq!(cfg.video_height, 480);
        assert!(cfg.debug_logging);
    }

    #[test]
    fn empty_file_returns_defaults() {
        let f = write_tmp("");
        let cfg = load_config(f.path());
        assert_eq!(cfg.video_width, Config::default().video_width);
    }
}
