// Zaparoo Launcher
// Copyright (c) 2026 The Zaparoo Project Contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0

use zaparoo_core::config::Config;

/// Sets `QT_QPA_PLATFORM=linuxfb` and `QT_QUICK_BACKEND=software`, then runs
/// `vmode -r W H rgb32`. Must be called before `QGuiApplication`. No-op on
/// non-MiSTer builds.
pub fn apply_pre_qt_setup(config: &Config) {
    #[cfg(zaparoo_runtime = "mister")]
    {
        use tracing::warn;
        std::env::set_var("QT_QPA_PLATFORM", "linuxfb");
        std::env::set_var("QT_QUICK_BACKEND", "software");

        let status = std::process::Command::new("vmode")
            .args([
                "-r",
                &config.video_width.to_string(),
                &config.video_height.to_string(),
                "rgb32",
            ])
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
    let _ = config;
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
