// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//
// Normalised UI action catalogue and the defaulted key-bindings that map
// raw Qt key codes onto those actions. Screens handle actions, not keys,
// so gamepad / NFC reader sources can slot in beside the keyboard without
// touching the UI tree. Inspired by RetroArch's RetroPad abstraction.

use std::collections::HashMap;

pub mod actions {
    pub const UP: &str = "up";
    pub const DOWN: &str = "down";
    pub const LEFT: &str = "left";
    pub const RIGHT: &str = "right";
    pub const ACCEPT: &str = "accept";
    pub const CANCEL: &str = "cancel";
    pub const DETAILS: &str = "details";
    pub const PAGE_PREV: &str = "page_prev";
    pub const PAGE_NEXT: &str = "page_next";
    pub const QUIT: &str = "quit";
}

/// Resolves a `Qt::Key` name as found in `launcher.toml` (e.g. `"Left"`,
/// `"Return"`) to the numeric key code Qt emits at runtime. Returns None
/// for unknown names so the caller can warn and skip.
#[must_use]
pub fn qt_key_code(name: &str) -> Option<i32> {
    // Subset that covers every action in the default bindings plus a few
    // common aliases. Extend as new actions land. Values match Qt::Key.
    match name {
        "Left" => Some(0x0100_0012),
        "Right" => Some(0x0100_0014),
        "Up" => Some(0x0100_0013),
        "Down" => Some(0x0100_0015),
        "Return" => Some(0x0100_0004),
        "Enter" => Some(0x0100_0005),
        "Escape" => Some(0x0100_0000),
        "Backspace" => Some(0x0100_0003),
        "PageUp" => Some(0x0100_0016),
        "PageDown" => Some(0x0100_0017),
        "Space" => Some(0x20),
        "Tab" => Some(0x0100_0001),
        _ => None,
    }
}

/// Default action → Qt-key-name list. Merged with `[input.keyboard]`
/// overrides from `launcher.toml`: a user-provided list replaces the
/// default for that action (not merged), so emptying a list unbinds it.
#[must_use]
pub fn default_bindings() -> HashMap<String, Vec<String>> {
    let mut map: HashMap<String, Vec<String>> = HashMap::new();
    map.insert(actions::LEFT.into(), vec!["Left".into()]);
    map.insert(actions::RIGHT.into(), vec!["Right".into()]);
    map.insert(actions::UP.into(), vec!["Up".into()]);
    map.insert(actions::DOWN.into(), vec!["Down".into()]);
    map.insert(
        actions::ACCEPT.into(),
        vec!["Return".into(), "Enter".into()],
    );
    map.insert(
        actions::CANCEL.into(),
        vec!["Escape".into(), "Backspace".into()],
    );
    map.insert(actions::PAGE_PREV.into(), vec!["PageUp".into()]);
    map.insert(actions::PAGE_NEXT.into(), vec!["PageDown".into()]);
    map
}

/// Inverts the bindings (action → keys) into the runtime lookup shape
/// ([`Qt::Key`] code → action). Later bindings for the same key win — a
/// sane collision policy for a small hand-authored table.
#[must_use]
pub fn invert<S>(bindings: &HashMap<String, Vec<String>, S>) -> HashMap<i32, String>
where
    S: std::hash::BuildHasher,
{
    let mut out: HashMap<i32, String> = HashMap::new();
    for (action, keys) in bindings {
        for name in keys {
            if let Some(code) = qt_key_code(name) {
                out.insert(code, action.clone());
            } else {
                tracing::warn!("unknown Qt key name in input binding: {name}");
            }
        }
    }
    out
}

#[cfg(test)]
mod tests {
    #![allow(
        clippy::expect_used,
        clippy::unwrap_used,
        reason = "tests should fail-fast on unexpected errors"
    )]

    use super::{actions, default_bindings, invert, qt_key_code};

    #[test]
    fn defaults_cover_every_navigable_action() {
        let b = default_bindings();
        for action in [
            actions::LEFT,
            actions::RIGHT,
            actions::UP,
            actions::DOWN,
            actions::ACCEPT,
            actions::CANCEL,
        ] {
            assert!(
                b.get(action).is_some_and(|v| !v.is_empty()),
                "missing default binding for {action}"
            );
        }
    }

    #[test]
    fn invert_produces_unique_key_to_action_map() {
        let map = invert(&default_bindings());
        assert_eq!(
            map.get(&qt_key_code("Left").unwrap()).map(String::as_str),
            Some(actions::LEFT),
        );
        assert_eq!(
            map.get(&qt_key_code("Return").unwrap()).map(String::as_str),
            Some(actions::ACCEPT),
        );
        assert_eq!(
            map.get(&qt_key_code("Escape").unwrap()).map(String::as_str),
            Some(actions::CANCEL),
        );
    }

    #[test]
    fn unknown_key_names_are_silently_skipped_not_panicked() {
        let mut b = default_bindings();
        b.insert("fictional".into(), vec!["NotAKey".into()]);
        // invert logs a warning and keeps going; the result holds no entry
        // for the fictional action.
        let map = invert(&b);
        assert!(!map.values().any(|v| v == "fictional"));
    }
}
