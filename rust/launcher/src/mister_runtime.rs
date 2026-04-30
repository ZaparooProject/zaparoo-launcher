// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0

use zaparoo_core::config::Config;

/// Sets `QT_QPA_PLATFORM=linuxfb` and `QT_QUICK_BACKEND=software`, then runs
/// `vmode -r W H rgb32`. Must be called before `QGuiApplication`. No-op on
/// non-MiSTer builds.
///
/// Resolution priority: `SettingsState.resolution` (if a parsable
/// `WxH` value is on disk) wins over `[mister.video_*]` from
/// `launcher.toml`. Empty/missing/malformed falls back to config —
/// matches the pre-Settings behaviour exactly so users who never visit
/// the Settings screen see no change.
pub fn apply_pre_qt_setup(config: &Config) {
    #[cfg(zaparoo_runtime = "mister")]
    {
        std::env::set_var("QT_QPA_PLATFORM", "linuxfb");
        std::env::set_var("QT_QUICK_BACKEND", "software");

        let (width, height) = resolve_startup_resolution(config);
        run_vmode(width, height);
    }
    #[cfg(not(zaparoo_runtime = "mister"))]
    let _ = config;
}

/// Run `vmode -r W H rgb32`. No-op on non-MiSTer builds. Exposed so the
/// Settings screen can re-apply a freshly-picked resolution at runtime
/// without going through the full `apply_pre_qt_setup` env-var dance.
pub fn run_vmode(width: u32, height: u32) {
    #[cfg(zaparoo_runtime = "mister")]
    {
        use tracing::warn;
        let status = std::process::Command::new("vmode")
            .args(["-r", &width.to_string(), &height.to_string(), "rgb32"])
            .status();
        match status {
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
                warn!("vmode not found — display mode unchanged");
            }
            Err(e) => warn!("vmode error: {e}"),
            Ok(s) if !s.success() => {
                warn!(
                    "vmode exited with {:?} — display mode may not have changed",
                    s.code()
                );
            }
            Ok(_) => {}
        }
    }
    #[cfg(not(zaparoo_runtime = "mister"))]
    let _ = (width, height);
}

#[cfg(zaparoo_runtime = "mister")]
fn resolve_startup_resolution(config: &Config) -> (u32, u32) {
    // Read the persisted state directly here — `init_globals` hasn't run
    // yet (we're called from `zaparoo_rust_init` before `persist::load`
    // is stored in the singleton mutex), so `with_persist_read` would
    // panic. The state file is tiny (<300 bytes) and lives on tmpfs on
    // MiSTer, so the extra read is negligible.
    let saved = zaparoo_core::persist::load().settings.resolution;
    if let Some((w, h)) = parse_resolution(&saved) {
        return (w, h);
    }
    (config.video_width, config.video_height)
}

/// Parse a `"WxH"` resolution string like `"1920x1080"` (case-insensitive
/// `x`) into `(width, height)`. Returns `None` on empty input, missing
/// separator, non-numeric components, or zero values — the caller falls
/// back to its config defaults in any of those cases.
pub fn parse_resolution(value: &str) -> Option<(u32, u32)> {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        return None;
    }
    let (w_str, h_str) = trimmed
        .split_once('x')
        .or_else(|| trimmed.split_once('X'))?;
    let w: u32 = w_str.trim().parse().ok()?;
    let h: u32 = h_str.trim().parse().ok()?;
    if w == 0 || h == 0 {
        return None;
    }
    Some((w, h))
}

/// Fire-and-forget `zaparoo.sh -service start`. No-op on non-MiSTer builds.
pub fn ensure_core_service_running() {
    #[cfg(zaparoo_runtime = "mister")]
    {
        use tracing::warn;
        if let Err(e) = std::process::Command::new("/media/fat/Scripts/zaparoo.sh")
            .args(["-service", "start"])
            .spawn()
        {
            warn!("failed to start zaparoo.sh: {e}");
        }
    }
}

#[cfg(test)]
mod tests {
    use super::parse_resolution;

    #[test]
    fn parse_resolution_accepts_lower_x() {
        assert_eq!(parse_resolution("1920x1080"), Some((1920, 1080)));
    }

    #[test]
    fn parse_resolution_accepts_upper_x() {
        assert_eq!(parse_resolution("640X480"), Some((640, 480)));
    }

    #[test]
    fn parse_resolution_trims_whitespace() {
        assert_eq!(parse_resolution("  1280x720 "), Some((1280, 720)));
    }

    #[test]
    fn parse_resolution_rejects_empty() {
        assert!(parse_resolution("").is_none());
        assert!(parse_resolution("   ").is_none());
    }

    #[test]
    fn parse_resolution_rejects_missing_separator() {
        assert!(parse_resolution("1920").is_none());
        assert!(parse_resolution("1920-1080").is_none());
    }

    #[test]
    fn parse_resolution_rejects_non_numeric() {
        assert!(parse_resolution("widexheight").is_none());
        assert!(parse_resolution("1920xfoo").is_none());
    }

    #[test]
    fn parse_resolution_rejects_zero_components() {
        assert!(parse_resolution("0x1080").is_none());
        assert!(parse_resolution("1920x0").is_none());
    }
}
