// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0

import QtQuick
import QtTest
import Zaparoo.App
import Zaparoo.Browse as Browse

// Regression tests for the kill/relaunch persistence flow. The failure
// these guard against: during restore the carousels seed their
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
        main.hubFocus = main.focusCategories
        tryCompare(main, "screenOffset", 0, 2000)
    }

    // Browse.* singletons are process-wide, so state writes leak across
    // TestCases. Reset to defaults (empty strings) after every test so
    // later suites — in particular tst_smoke's test_initial_state — see
    // a clean Component.onCompleted path.
    function cleanup(): void {
        Browse.AppState.active_screen = ""
        Browse.HubState.focus = ""
        Browse.HubState.category = ""
        Browse.HubState.system_id = ""
        Browse.GamesState.system_id = ""
        Browse.GamesState.game_path = ""
    }

    // CategoriesModel is empty in this test harness (no live Core).
    // Left/Right must not call _navigateCarousel → _at(0) → "" on an
    // empty model, because that would wipe the saved category from
    // persisted state.
    function test_empty_categories_navigation_preserves_hub_state(): void {
        Browse.HubState.category = "persistence-probe-category"
        main.handleKey(Qt.Key_Left)
        main.handleKey(Qt.Key_Right)
        compare(Browse.HubState.category, "persistence-probe-category",
                "navigating an empty categories carousel must not overwrite HubState.category")
    }

    function test_empty_systems_navigation_preserves_hub_state(): void {
        Browse.HubState.system_id = "persistence-probe-system"
        main.hubFocus = main.focusSystems
        main.handleKey(Qt.Key_Left)
        main.handleKey(Qt.Key_Right)
        // Down stays within the (empty) grid; Up at row 0 falls through
        // to a section flip back to categories — neither path may write
        // a system id derived from index 0 of an empty model.
        main.handleKey(Qt.Key_Down)
        compare(Browse.HubState.system_id, "persistence-probe-system",
                "Down on an empty systems grid must not overwrite HubState.system_id")
        // Restore systems focus so Up exercises the empty-systems path
        // (the prior Down may have flipped sections via the same
        // fall-through). Up on an empty grid hits the section-flip
        // branch that mirrors Escape — it must also not write system_id.
        main.hubFocus = main.focusSystems
        main.handleKey(Qt.Key_Up)
        compare(Browse.HubState.system_id, "persistence-probe-system",
                "Up on an empty systems grid must not overwrite HubState.system_id")
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

    // Focus/screen flips are user-visible intent, not selection state.
    // They should persist even when the underlying model is empty (so
    // the launcher resumes on the right screen next boot).
    function test_focus_flip_on_empty_categories_persists_hub_focus(): void {
        main.handleKey(Qt.Key_Return)
        compare(Browse.HubState.focus, main.focusSystems,
                "Enter must flip hubFocus even on an empty carousel")
    }

    function test_screen_flip_on_empty_systems_persists_active_screen(): void {
        main.hubFocus = main.focusSystems
        main.handleKey(Qt.Key_Return)
        compare(Browse.AppState.active_screen, main.screenGames,
                "Enter must flip active_screen even on an empty carousel")
    }

    // Enter commits the highlighted selection into HubState so first-launch
    // users who never press Left/Right still get a restorable identifier on
    // disk. The write is guarded by itemCount > 0 — on an empty carousel
    // (this harness) the guard must skip the write, leaving prior state
    // intact.
    function test_enter_on_empty_categories_preserves_hub_state(): void {
        Browse.HubState.category = "persistence-probe-category"
        main.handleKey(Qt.Key_Return)
        compare(Browse.HubState.category, "persistence-probe-category",
                "Enter on an empty categories carousel must not overwrite HubState.category")
    }

    function test_enter_on_empty_systems_preserves_hub_state(): void {
        Browse.HubState.system_id = "persistence-probe-system"
        main.hubFocus = main.focusSystems
        main.handleKey(Qt.Key_Return)
        compare(Browse.HubState.system_id, "persistence-probe-system",
                "Enter on an empty systems carousel must not overwrite HubState.system_id")
    }

    function test_enter_on_empty_games_preserves_games_state(): void {
        Browse.GamesState.game_path = "persistence-probe-path"
        main.activeScreen = main.screenGames
        main.handleKey(Qt.Key_Return)
        compare(Browse.GamesState.game_path, "persistence-probe-path",
                "Enter on an empty games carousel must not overwrite GamesState.game_path")
    }
}
