// Zaparoo Launcher
// Copyright (c) 2026 The Zaparoo Project Contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0

use crate::runtime;
use std::path::PathBuf;

pub fn config_file_path() -> PathBuf {
    if runtime::current().is_mister() {
        PathBuf::from("/media/fat/zaparoo/launcher.toml")
    } else {
        dirs_next::config_dir()
            .unwrap_or_else(|| PathBuf::from("."))
            .join("zaparoo")
            .join("launcher.toml")
    }
}

pub fn log_file_path() -> PathBuf {
    if runtime::current().is_mister() {
        PathBuf::from("/tmp/zaparoo/launcher.log")
    } else {
        dirs_next::data_local_dir()
            .unwrap_or_else(|| PathBuf::from("."))
            .join("zaparoo")
            .join("logs")
            .join("launcher.log")
    }
}

#[cfg(test)]
mod tests {
    #![allow(
        clippy::expect_used,
        clippy::unwrap_used,
        clippy::panic,
        reason = "tests should fail-fast on unexpected errors"
    )]

    use super::{config_file_path, log_file_path};
    use crate::runtime;

    #[test]
    fn paths_end_with_expected_filenames() {
        let cfg = config_file_path();
        assert_eq!(
            cfg.file_name().and_then(|n| n.to_str()),
            Some("launcher.toml")
        );

        let log = log_file_path();
        assert_eq!(
            log.file_name().and_then(|n| n.to_str()),
            Some("launcher.log")
        );
    }

    #[test]
    fn runtime_matches_configured_paths() {
        // When runtime is Desktop, paths route through dirs_next (per-user dirs)
        // rather than the fixed MiSTer locations. Asserts the branches stay in sync.
        if runtime::current().is_mister() {
            assert_eq!(
                config_file_path().to_str(),
                Some("/media/fat/zaparoo/launcher.toml")
            );
            assert_eq!(log_file_path().to_str(), Some("/tmp/zaparoo/launcher.log"));
        } else {
            let cfg = config_file_path();
            assert!(
                cfg.ends_with("zaparoo/launcher.toml"),
                "config path did not end with zaparoo/launcher.toml: {cfg:?}"
            );
            let log = log_file_path();
            assert!(
                log.ends_with("zaparoo/logs/launcher.log"),
                "log path did not end with zaparoo/logs/launcher.log: {log:?}"
            );
        }
    }
}
