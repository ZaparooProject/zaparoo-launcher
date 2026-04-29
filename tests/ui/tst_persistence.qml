// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0

import QtQuick
import QtTest
import Zaparoo.App
import Zaparoo.Browse as Browse

// cxx-qt 0.8 patches `isFinal: true` on singleton properties but the
// qmltypes schema has no `isFinal` slot for Method, so every direct
// read or write of a Browse.* singleton property still trips qmllint's
// "Member can be shadowed" check. Until the schema grows method-level
// finality, suppress the compiler category file-wide — same pattern
// every other QML file in the tree uses.
// qmllint disable compiler

// Regression tests for the kill/relaunch persistence flow. The failure
// these guard against: during restore the row/grid seeds its
// currentIndex *programmatically*; prior revisions wrote that seeded
// value back to disk via onCurrentIndexChanged, silently overwriting
// the user's saved identifier with a fallback. These tests exercise
// the key-handler guards that keep disk state intact when the model
// is empty (the same code path that runs if keys arrive mid-restore).
TestCase {
    name: "UiPersistence"
    when: windowShown

    Main {
        id: main
        width: 1280
        height: 720
    }

    function init(): void {
        main.activeScreen = main.screenHub
    }

    // Browse.* singletons are process-wide, so state writes leak across
    // TestCases. Reset to defaults (empty strings) after every test so
    // later suites — in particular tst_smoke's test_initial_state — see
    // a clean Component.onCompleted path.
    function cleanup(): void {
        Browse.AppState.active_screen = ""
        Browse.HubState.category = ""
        Browse.SystemsState.system_id = ""
        Browse.GamesState.system_id = ""
        Browse.GamesState.game_path = ""
    }

    // CategoriesModel is empty in this test harness (no live Core).
    // Left/Right must not call _navigate → _at(0) → "" on an empty
    // model, because that would wipe the saved category from
    // persisted state.
    function test_empty_categories_navigation_preserves_hub_state(): void {
        Browse.HubState.category = "persistence-probe-category"
        main.handleKey(Qt.Key_Left)
        main.handleKey(Qt.Key_Right)
        compare(Browse.HubState.category, "persistence-probe-category",
                "navigating an empty categories row must not overwrite HubState.category")
    }

    function test_empty_systems_navigation_preserves_systems_state(): void {
        Browse.SystemsState.system_id = "persistence-probe-system"
        main.activeScreen = main.screenSystems
        // None of these keys flip screens on an empty grid — they're
        // all in-grid moves that no-op when there's nothing to move
        // to. None may write a system id derived from index 0.
        main.handleKey(Qt.Key_Left)
        main.handleKey(Qt.Key_Right)
        main.handleKey(Qt.Key_Down)
        main.handleKey(Qt.Key_Up)
        compare(Browse.SystemsState.system_id, "persistence-probe-system",
                "Navigating an empty systems grid must not overwrite SystemsState.system_id")
    }

    function test_empty_games_navigation_preserves_games_state(): void {
        Browse.GamesState.game_path = "persistence-probe-path"
        main.activeScreen = main.screenGames
        main.handleKey(Qt.Key_Left)
        main.handleKey(Qt.Key_Right)
        main.handleKey(Qt.Key_Up)
        main.handleKey(Qt.Key_Down)
        compare(Browse.GamesState.game_path, "persistence-probe-path",
                "navigating an empty games grid must not overwrite GamesState.game_path")
    }

    // Screen flips are user-visible intent, not selection state. On Hub
    // they should persist even when the underlying model is empty (so
    // the launcher resumes on the right screen next boot). Systems and
    // Games own a [OK] RETRY contract on non-Ready accept, so Enter on
    // an empty Systems grid re-fires the current load instead of
    // flipping forward — the screen-flip-on-empty rule is Hub-only.
    function test_screen_flip_on_empty_categories_persists_active_screen(): void {
        main.handleKey(Qt.Key_Return)
        compare(Browse.AppState.active_screen, main.screenSystems,
                "Enter must flip active_screen to systems even on an empty categories row")
    }

    // Symmetric to the Hub test above: that one proves the flip *does*
    // write AppState; this one proves Systems retry *doesn't*. Seed a
    // sentinel because test isolation clears AppState in cleanup() and
    // setting `main.activeScreen` directly bypasses the request-signal
    // path that writes AppState — so we need a non-empty starting value
    // to detect a stray write.
    function test_enter_on_empty_systems_does_not_persist_games_screen(): void {
        Browse.AppState.active_screen = "persistence-probe-screen"
        main.activeScreen = main.screenSystems
        main.handleKey(Qt.Key_Return)
        compare(Browse.AppState.active_screen, "persistence-probe-screen",
                "Enter on an empty systems grid must retry, not flip — AppState.active_screen must not be overwritten")
    }

    // Enter commits the highlighted selection into HubState so first-launch
    // users who never press Left/Right still get a restorable identifier on
    // disk. The write is guarded by count > 0 — on an empty row (this
    // harness) the guard must skip the write, leaving prior state intact.
    function test_enter_on_empty_categories_preserves_hub_state(): void {
        Browse.HubState.category = "persistence-probe-category"
        main.handleKey(Qt.Key_Return)
        compare(Browse.HubState.category, "persistence-probe-category",
                "Enter on an empty categories row must not overwrite HubState.category")
    }

    function test_enter_on_empty_systems_preserves_systems_state(): void {
        Browse.SystemsState.system_id = "persistence-probe-system"
        main.activeScreen = main.screenSystems
        main.handleKey(Qt.Key_Return)
        compare(Browse.SystemsState.system_id, "persistence-probe-system",
                "Enter on an empty systems grid must not overwrite SystemsState.system_id")
    }

    function test_enter_on_empty_games_preserves_games_state(): void {
        Browse.GamesState.game_path = "persistence-probe-path"
        main.activeScreen = main.screenGames
        main.handleKey(Qt.Key_Return)
        compare(Browse.GamesState.game_path, "persistence-probe-path",
                "Enter on an empty games grid must not overwrite GamesState.game_path")
    }
}
