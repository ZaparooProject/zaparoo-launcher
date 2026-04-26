// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//
// Canned fixture data for mock-core. Response shapes mirror the
// upstream Core API: https://zaparoo.org/docs/core/api/methods/
// 3 categories x 10 systems x 5 games each = 50 games total,
// distributed so every system has content when the launcher drills
// into it.

use serde_json::{json, Value};

pub fn version_response() -> Value {
    json!({
        "version": "mock-0.1.0",
        "platform": "mock",
    })
}

pub fn systems_response() -> Value {
    json!({
        "systems": [
            { "id": "nes",     "name": "Nintendo Entertainment System", "category": "Consoles" },
            { "id": "snes",    "name": "Super Nintendo",                "category": "Consoles" },
            { "id": "genesis", "name": "Sega Genesis",                  "category": "Consoles" },
            { "id": "n64",     "name": "Nintendo 64",                   "category": "Consoles" },
            { "id": "gb",      "name": "Game Boy",                      "category": "Handhelds" },
            { "id": "gbc",     "name": "Game Boy Color",                "category": "Handhelds" },
            { "id": "gba",     "name": "Game Boy Advance",              "category": "Handhelds" },
            { "id": "nds",     "name": "Nintendo DS",                   "category": "Handhelds" },
            { "id": "mame",    "name": "MAME",                          "category": "Arcade" },
            { "id": "neogeo",  "name": "Neo Geo",                       "category": "Arcade" },
        ]
    })
}

pub fn media_search_response(params: &Value) -> Value {
    let systems = params
        .get("systems")
        .and_then(Value::as_array)
        .map(|a| a.iter().filter_map(Value::as_str).collect::<Vec<_>>())
        .unwrap_or_default();
    let max = params
        .get("maxResults")
        .and_then(Value::as_u64)
        .unwrap_or(100) as usize;

    let results: Vec<Value> = games_for_systems(&systems).take(max).collect();
    // `total` is deprecated upstream and always returns -1; pagination
    // info now travels under the `pagination` envelope. The mock has no
    // real pagination, so it always reports a single complete page.
    json!({
        "results": results,
        "total": -1,
        "pagination": {
            "hasNextPage": false,
            "pageSize": max,
        },
    })
}

pub fn media_browse_response(params: &Value) -> Value {
    let path = params.get("path").and_then(Value::as_str).unwrap_or("");
    let entries: Vec<Value> = ALL_GAMES
        .iter()
        .take(20)
        .map(|(name, file, system)| {
            json!({
                "name": name,
                "path": format!("{path}/{file}"),
                "type": "media",
                "systemId": system,
                "zapScript": format!("@{system}/{file}"),
                "relativePath": file,
            })
        })
        .collect();
    let total_files = entries.len() as u64;
    json!({
        "path": path,
        "entries": entries,
        "totalFiles": total_files,
        "pagination": {
            "hasNextPage": false,
            "pageSize": 100,
        },
    })
}

fn games_for_systems<'a>(systems: &'a [&'a str]) -> impl Iterator<Item = Value> + 'a {
    ALL_GAMES.iter().filter_map(move |(name, file, system)| {
        if !systems.is_empty() && !systems.contains(system) {
            return None;
        }
        Some(json!({
            "name": name,
            "path": format!("/mock/{system}/{file}"),
            "zapScript": format!("@{system}/{file}"),
            "system": { "id": system, "name": system, "category": "" },
            "tags": [],
        }))
    })
}

// (display name, filename, system id)
const ALL_GAMES: &[(&str, &str, &str)] = &[
    // NES
    ("Super Mario Bros.", "smb.nes", "nes"),
    ("The Legend of Zelda", "zelda.nes", "nes"),
    ("Metroid", "metroid.nes", "nes"),
    ("Mega Man 2", "mm2.nes", "nes"),
    ("Castlevania", "castlevania.nes", "nes"),
    // SNES
    ("Super Mario World", "smw.sfc", "snes"),
    ("A Link to the Past", "alttp.sfc", "snes"),
    ("Super Metroid", "sm.sfc", "snes"),
    ("Chrono Trigger", "ct.sfc", "snes"),
    ("F-Zero", "fzero.sfc", "snes"),
    // Genesis
    ("Sonic the Hedgehog", "sonic1.md", "genesis"),
    ("Sonic the Hedgehog 2", "sonic2.md", "genesis"),
    ("Streets of Rage 2", "sor2.md", "genesis"),
    ("Gunstar Heroes", "gunstar.md", "genesis"),
    ("Ecco the Dolphin", "ecco.md", "genesis"),
    // N64
    ("Super Mario 64", "sm64.z64", "n64"),
    ("Ocarina of Time", "oot.z64", "n64"),
    ("GoldenEye 007", "goldeneye.z64", "n64"),
    ("Mario Kart 64", "mk64.z64", "n64"),
    ("Perfect Dark", "pd.z64", "n64"),
    // Game Boy
    ("Tetris", "tetris.gb", "gb"),
    ("Pokemon Red", "pokered.gb", "gb"),
    ("Link's Awakening", "la.gb", "gb"),
    ("Super Mario Land", "sml.gb", "gb"),
    ("Metroid II", "metroid2.gb", "gb"),
    // Game Boy Color
    ("Pokemon Crystal", "pokecrystal.gbc", "gbc"),
    ("Zelda: Oracle of Ages", "oracle_of_ages.gbc", "gbc"),
    ("Wario Land 3", "wl3.gbc", "gbc"),
    ("Dragon Warrior III", "dw3.gbc", "gbc"),
    ("Shantae", "shantae.gbc", "gbc"),
    // Game Boy Advance
    ("Metroid Fusion", "fusion.gba", "gba"),
    ("Castlevania: Aria of Sorrow", "aos.gba", "gba"),
    ("Pokemon Emerald", "emerald.gba", "gba"),
    ("Advance Wars", "aw.gba", "gba"),
    ("Golden Sun", "gs.gba", "gba"),
    // Nintendo DS
    ("Super Mario 64 DS", "sm64ds.nds", "nds"),
    ("Mario Kart DS", "mkds.nds", "nds"),
    ("Phoenix Wright", "pw.nds", "nds"),
    ("Pokemon Diamond", "diamond.nds", "nds"),
    ("The World Ends With You", "twewy.nds", "nds"),
    // MAME
    ("Pac-Man", "pacman.zip", "mame"),
    ("Donkey Kong", "dkong.zip", "mame"),
    ("Galaga", "galaga.zip", "mame"),
    ("Street Fighter II", "sf2.zip", "mame"),
    ("Ms. Pac-Man", "mspacman.zip", "mame"),
    // Neo Geo
    ("Metal Slug", "mslug.neo", "neogeo"),
    ("The King of Fighters '98", "kof98.neo", "neogeo"),
    ("Samurai Shodown", "samsho.neo", "neogeo"),
    ("Fatal Fury", "fatfury.neo", "neogeo"),
    ("Garou: Mark of the Wolves", "garou.neo", "neogeo"),
];
