// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//
// Persistent UI state. MiSTer's parent process kills the launcher binary
// without notice; every user-visible navigation choice must round-trip
// through disk so the next boot resumes where the user was.
//
// Layout: a single TOML with one section per screen. Each section owns
// its own `schema_version` so a screen can evolve its schema (rename
// fields, change types) without forcing other screens to reset. On
// load, any section whose `schema_version` doesn't match the current
// owner's constant is replaced with `Default` — other sections
// survive.
//
// Written synchronously on every mutation (write-through). Parent can
// SIGKILL between any two lines, so the loss window must be zero. File
// is tiny (<300 bytes) and lives on tmpfs on MiSTer; sync cost on the
// Qt thread is microseconds.

use crate::platform_paths::state_file_path;
use serde::{Deserialize, Serialize};
use std::io::Write;
use std::path::{Path, PathBuf};
use tracing::warn;

pub const HUB_SCHEMA: u32 = 2;
pub const SYSTEMS_SCHEMA: u32 = 1;
pub const GAMES_SCHEMA: u32 = 1;

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default)]
pub struct PersistedState {
    pub active_screen: String,
    pub hub: HubState,
    pub systems: SystemsState,
    pub games: GamesState,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default)]
pub struct HubState {
    pub schema_version: u32,
    pub category: String,
}

impl Default for HubState {
    fn default() -> Self {
        Self {
            schema_version: HUB_SCHEMA,
            category: String::new(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default)]
pub struct SystemsState {
    pub schema_version: u32,
    pub system_id: String,
}

impl Default for SystemsState {
    fn default() -> Self {
        Self {
            schema_version: SYSTEMS_SCHEMA,
            system_id: String::new(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default)]
pub struct GamesState {
    pub schema_version: u32,
    pub system_id: String,
    pub game_path: String,
}

impl Default for GamesState {
    fn default() -> Self {
        Self {
            schema_version: GAMES_SCHEMA,
            system_id: String::new(),
            game_path: String::new(),
        }
    }
}

pub fn load() -> PersistedState {
    load_from(&state_file_path())
}

pub fn save(state: &PersistedState) {
    save_to(&state_file_path(), state);
}

fn load_from(path: &Path) -> PersistedState {
    let Ok(src) = std::fs::read_to_string(path) else {
        return PersistedState::default();
    };
    let mut state: PersistedState = match toml::from_str(&src) {
        Ok(s) => s,
        Err(e) => {
            warn!("persist state parse error in {}: {e}", path.display());
            return PersistedState::default();
        }
    };
    if state.hub.schema_version != HUB_SCHEMA {
        warn!(
            "persist: hub section version {} != expected {}; resetting section",
            state.hub.schema_version, HUB_SCHEMA
        );
        state.hub = HubState::default();
    }
    if state.systems.schema_version != SYSTEMS_SCHEMA {
        warn!(
            "persist: systems section version {} != expected {}; resetting section",
            state.systems.schema_version, SYSTEMS_SCHEMA
        );
        state.systems = SystemsState::default();
    }
    if state.games.schema_version != GAMES_SCHEMA {
        warn!(
            "persist: games section version {} != expected {}; resetting section",
            state.games.schema_version, GAMES_SCHEMA
        );
        state.games = GamesState::default();
    }
    state
}

fn save_to(path: &Path, state: &PersistedState) {
    let serialized = match toml::to_string(state) {
        Ok(s) => s,
        Err(e) => {
            warn!("persist state serialisation failed: {e}");
            return;
        }
    };
    if let Some(parent) = path.parent() {
        if let Err(e) = std::fs::create_dir_all(parent) {
            warn!("could not create {}: {e}", parent.display());
            return;
        }
    }
    // Atomic replace: write to a unique sibling temp file, then rename. A
    // crash mid-write leaves the temp behind but never a torn state.toml.
    let tmp = tmp_sibling(path);
    match std::fs::File::create(&tmp).and_then(|mut f| {
        f.write_all(serialized.as_bytes())?;
        f.sync_all()?;
        Ok(())
    }) {
        Ok(()) => {}
        Err(e) => {
            warn!("persist state write to {} failed: {e}", tmp.display());
            let _ = std::fs::remove_file(&tmp);
            return;
        }
    }
    if let Err(e) = std::fs::rename(&tmp, path) {
        warn!(
            "persist state rename {} → {} failed: {e}",
            tmp.display(),
            path.display()
        );
        let _ = std::fs::remove_file(&tmp);
    }
}

fn tmp_sibling(path: &Path) -> PathBuf {
    // Per-process-and-thread suffix keeps concurrent writers from
    // clobbering each other's temp file and then racing on rename. The
    // final rename is still atomic; only the last one wins, which is the
    // desired semantics.
    let pid = std::process::id();
    let tid = format!("{:?}", std::thread::current().id());
    let tid_clean: String = tid.chars().filter(char::is_ascii_alphanumeric).collect();
    let suffix = format!(".tmp.{pid}.{tid_clean}");
    let mut buf = path.as_os_str().to_owned();
    buf.push(&suffix);
    PathBuf::from(buf)
}

#[cfg(test)]
mod tests {
    #![allow(
        clippy::expect_used,
        clippy::unwrap_used,
        clippy::panic,
        reason = "tests should fail-fast on unexpected errors"
    )]

    use super::{
        load_from, save_to, GamesState, HubState, PersistedState, SystemsState, GAMES_SCHEMA,
        HUB_SCHEMA, SYSTEMS_SCHEMA,
    };
    use std::thread;

    #[test]
    fn load_returns_default_on_missing_file() {
        let dir = tempfile::tempdir().expect("tempdir");
        let path = dir.path().join("missing.toml");
        let state = load_from(&path);
        assert_eq!(state, PersistedState::default());
        assert_eq!(state.hub.schema_version, HUB_SCHEMA);
        assert_eq!(state.systems.schema_version, SYSTEMS_SCHEMA);
        assert_eq!(state.games.schema_version, GAMES_SCHEMA);
    }

    #[test]
    fn save_then_load_round_trips_all_sections() {
        let dir = tempfile::tempdir().expect("tempdir");
        let path = dir.path().join("state.toml");
        let original = PersistedState {
            active_screen: "games".into(),
            hub: HubState {
                schema_version: HUB_SCHEMA,
                category: "Consoles".into(),
            },
            systems: SystemsState {
                schema_version: SYSTEMS_SCHEMA,
                system_id: "NES".into(),
            },
            games: GamesState {
                schema_version: GAMES_SCHEMA,
                system_id: "NES".into(),
                game_path: "/roms/smb.nes".into(),
            },
        };
        save_to(&path, &original);
        let loaded = load_from(&path);
        assert_eq!(loaded, original);
    }

    #[test]
    fn load_from_malformed_toml_returns_default() {
        let dir = tempfile::tempdir().expect("tempdir");
        let path = dir.path().join("state.toml");
        std::fs::write(&path, "this is = not [ valid toml").expect("write");
        let state = load_from(&path);
        assert_eq!(state, PersistedState::default());
    }

    #[test]
    fn section_with_unknown_schema_version_resets_only_that_section() {
        let dir = tempfile::tempdir().expect("tempdir");
        let path = dir.path().join("state.toml");
        // Hub with a stale version; systems and games at current. Hub
        // must reset, the others must be preserved intact.
        let on_disk = format!(
            r#"active_screen = "games"

[hub]
schema_version = 999
category = "ancient"

[systems]
schema_version = {SYSTEMS_SCHEMA}
system_id = "NES"

[games]
schema_version = {GAMES_SCHEMA}
system_id = "NES"
game_path = "/roms/smb.nes"
"#
        );
        std::fs::write(&path, on_disk).expect("write");
        let state = load_from(&path);
        assert_eq!(state.active_screen, "games");
        assert_eq!(state.hub, HubState::default(), "hub should reset");
        assert_eq!(state.systems.schema_version, SYSTEMS_SCHEMA);
        assert_eq!(state.systems.system_id, "NES");
        assert_eq!(state.games.schema_version, GAMES_SCHEMA);
        assert_eq!(state.games.system_id, "NES");
        assert_eq!(state.games.game_path, "/roms/smb.nes");
    }

    #[test]
    fn stale_systems_section_resets_independently() {
        let dir = tempfile::tempdir().expect("tempdir");
        let path = dir.path().join("state.toml");
        // Systems at a stale version; hub and games at current. Only
        // systems must reset.
        let on_disk = format!(
            r#"active_screen = "systems"

[hub]
schema_version = {HUB_SCHEMA}
category = "Console"

[systems]
schema_version = 999
system_id = "ancient_sys"

[games]
schema_version = {GAMES_SCHEMA}
system_id = "NES"
game_path = "/roms/smb.nes"
"#
        );
        std::fs::write(&path, on_disk).expect("write");
        let state = load_from(&path);
        assert_eq!(state.hub.schema_version, HUB_SCHEMA);
        assert_eq!(state.hub.category, "Console");
        assert_eq!(
            state.systems,
            SystemsState::default(),
            "systems should reset"
        );
        assert_eq!(state.games.system_id, "NES");
    }

    #[test]
    fn save_creates_parent_directories() {
        let dir = tempfile::tempdir().expect("tempdir");
        let nested = dir.path().join("deeper").join("sub").join("state.toml");
        save_to(&nested, &PersistedState::default());
        assert!(nested.exists(), "state file was not created at {nested:?}");
    }

    #[test]
    fn save_is_atomic_under_concurrent_writes() {
        let dir = tempfile::tempdir().expect("tempdir");
        let path = dir.path().join("state.toml");
        let handles: Vec<_> = (0..8)
            .map(|i| {
                let path = path.clone();
                thread::spawn(move || {
                    for j in 0..20 {
                        let state = PersistedState {
                            active_screen: format!("screen-{i}"),
                            hub: HubState {
                                schema_version: HUB_SCHEMA,
                                category: format!("cat-{i}-{j}"),
                            },
                            systems: SystemsState {
                                schema_version: SYSTEMS_SCHEMA,
                                system_id: format!("sys-{i}-{j}"),
                            },
                            games: GamesState {
                                schema_version: GAMES_SCHEMA,
                                system_id: format!("sys-{i}-{j}"),
                                game_path: format!("/roms/{i}/{j}.rom"),
                            },
                        };
                        save_to(&path, &state);
                    }
                })
            })
            .collect();
        for h in handles {
            h.join().expect("thread join");
        }
        let final_state = load_from(&path);
        assert!(final_state.active_screen.starts_with("screen-"));
        assert!(final_state.hub.category.starts_with("cat-"));
        assert!(final_state.systems.system_id.starts_with("sys-"));
        assert_eq!(final_state.hub.schema_version, HUB_SCHEMA);
        assert_eq!(final_state.systems.schema_version, SYSTEMS_SCHEMA);
        assert_eq!(final_state.games.schema_version, GAMES_SCHEMA);
    }

    #[test]
    fn empty_sections_deserialise_via_default() {
        // A file with only `active_screen` — every section should
        // populate from `Default`, which sets the current schema_version.
        let dir = tempfile::tempdir().expect("tempdir");
        let path = dir.path().join("state.toml");
        std::fs::write(&path, "active_screen = \"hub\"\n").expect("write");
        let state = load_from(&path);
        assert_eq!(state.active_screen, "hub");
        assert_eq!(state.hub, HubState::default());
        assert_eq!(state.systems, SystemsState::default());
        assert_eq!(state.games, GamesState::default());
    }

    #[test]
    fn unknown_field_in_section_is_ignored() {
        // Forward-compat: adding a new field in a future version then
        // downgrading should not wipe state. Serde default drops
        // unknown fields silently.
        let dir = tempfile::tempdir().expect("tempdir");
        let path = dir.path().join("state.toml");
        let on_disk = format!(
            r#"[hub]
schema_version = {HUB_SCHEMA}
category = "Arcade"
future_field = "ignored"

[systems]
schema_version = {SYSTEMS_SCHEMA}
system_id = "NES"
future_field = "ignored"

[games]
schema_version = {GAMES_SCHEMA}
system_id = "NES"
game_path = "/x.rom"
"#
        );
        std::fs::write(&path, on_disk).expect("write");
        let state = load_from(&path);
        assert_eq!(state.hub.category, "Arcade");
        assert_eq!(state.systems.system_id, "NES");
        assert_eq!(state.games.game_path, "/x.rom");
    }
}
