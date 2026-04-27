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
            { "id": "NES",          "name": "Nintendo Entertainment System", "category": "Consoles" },
            { "id": "SNES",         "name": "Super Nintendo",                "category": "Consoles" },
            { "id": "Genesis",      "name": "Sega Genesis",                  "category": "Consoles" },
            { "id": "Nintendo64",   "name": "Nintendo 64",                   "category": "Consoles" },
            { "id": "Gameboy",      "name": "Game Boy",                      "category": "Handhelds" },
            { "id": "GameboyColor", "name": "Game Boy Color",                "category": "Handhelds" },
            { "id": "GBA",          "name": "Game Boy Advance",              "category": "Handhelds" },
            { "id": "NDS",          "name": "Nintendo DS",                   "category": "Handhelds" },
            { "id": "MAME",         "name": "MAME",                          "category": "Arcade" },
            { "id": "NeoGeo",       "name": "Neo Geo",                       "category": "Arcade" },
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
    ("Super Mario Bros.", "smb.nes", "NES"),
    ("The Legend of Zelda", "zelda.nes", "NES"),
    ("Metroid", "metroid.nes", "NES"),
    ("Mega Man 2", "mm2.nes", "NES"),
    ("Castlevania", "castlevania.nes", "NES"),
    // SNES
    ("Super Mario World", "smw.sfc", "SNES"),
    ("A Link to the Past", "alttp.sfc", "SNES"),
    ("Super Metroid", "sm.sfc", "SNES"),
    ("Chrono Trigger", "ct.sfc", "SNES"),
    ("F-Zero", "fzero.sfc", "SNES"),
    // Genesis
    ("Sonic the Hedgehog", "sonic1.md", "Genesis"),
    ("Sonic the Hedgehog 2", "sonic2.md", "Genesis"),
    ("Streets of Rage 2", "sor2.md", "Genesis"),
    ("Gunstar Heroes", "gunstar.md", "Genesis"),
    ("Ecco the Dolphin", "ecco.md", "Genesis"),
    // Nintendo 64
    ("Super Mario 64", "sm64.z64", "Nintendo64"),
    ("Ocarina of Time", "oot.z64", "Nintendo64"),
    ("GoldenEye 007", "goldeneye.z64", "Nintendo64"),
    ("Mario Kart 64", "mk64.z64", "Nintendo64"),
    ("Perfect Dark", "pd.z64", "Nintendo64"),
    // Game Boy
    ("Tetris", "tetris.gb", "Gameboy"),
    ("Pokemon Red", "pokered.gb", "Gameboy"),
    ("Link's Awakening", "la.gb", "Gameboy"),
    ("Super Mario Land", "sml.gb", "Gameboy"),
    ("Metroid II", "metroid2.gb", "Gameboy"),
    // Game Boy Color
    ("Pokemon Crystal", "pokecrystal.gbc", "GameboyColor"),
    (
        "Zelda: Oracle of Ages",
        "oracle_of_ages.gbc",
        "GameboyColor",
    ),
    ("Wario Land 3", "wl3.gbc", "GameboyColor"),
    ("Dragon Warrior III", "dw3.gbc", "GameboyColor"),
    ("Shantae", "shantae.gbc", "GameboyColor"),
    // Game Boy Advance
    ("Metroid Fusion", "fusion.gba", "GBA"),
    ("Castlevania: Aria of Sorrow", "aos.gba", "GBA"),
    ("Pokemon Emerald", "emerald.gba", "GBA"),
    ("Advance Wars", "aw.gba", "GBA"),
    ("Golden Sun", "gs.gba", "GBA"),
    // Nintendo DS
    ("Super Mario 64 DS", "sm64ds.nds", "NDS"),
    ("Mario Kart DS", "mkds.nds", "NDS"),
    ("Phoenix Wright", "pw.nds", "NDS"),
    ("Pokemon Diamond", "diamond.nds", "NDS"),
    ("The World Ends With You", "twewy.nds", "NDS"),
    // MAME
    ("Pac-Man", "pacman.zip", "MAME"),
    ("Donkey Kong", "dkong.zip", "MAME"),
    ("Galaga", "galaga.zip", "MAME"),
    ("Street Fighter II", "sf2.zip", "MAME"),
    ("Ms. Pac-Man", "mspacman.zip", "MAME"),
    // Neo Geo
    ("Metal Slug", "mslug.neo", "NeoGeo"),
    ("The King of Fighters '98", "kof98.neo", "NeoGeo"),
    ("Samurai Shodown", "samsho.neo", "NeoGeo"),
    ("Fatal Fury", "fatfury.neo", "NeoGeo"),
    ("Garou: Mark of the Wolves", "garou.neo", "NeoGeo"),
];
