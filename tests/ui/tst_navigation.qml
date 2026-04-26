// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0

import QtQuick
import QtTest
import Zaparoo.App

// Exercises the hub↔games navigation state machine defined in Main.qml.
// State is driven either by writing to the activeScreen and hubFocus
// properties (the observable contract) or by calling root.handleKey(key)
// directly — the latter proves the Keys.onPressed routing, which we can't
// exercise with keyClick because offscreen ApplicationWindows don't
// receive routed key events reliably.
TestCase {
    name: "UiNavigation"
    when: windowShown

    Main {
        id: main
        width: 1280
        height: 720
    }

    function init(): void {
        main.activeScreen = main.screenHub
        main.hubFocus = main.focusCategories
        // Let the screenOffset animation settle before each test.
        tryCompare(main, "screenOffset", 0, 2000)
    }

    function test_initial_state_is_hub_categories(): void {
        compare(main.activeScreen, main.screenHub)
        compare(main.hubFocus, main.focusCategories)
        compare(main.screenOffset, 0)
    }

    function test_flipping_hub_focus_keeps_screen_on_hub(): void {
        main.hubFocus = main.focusSystems
        compare(main.activeScreen, main.screenHub)
        compare(main.screenOffset, 0)
    }

    function test_activating_games_screen_shifts_offset_to_width(): void {
        main.activeScreen = main.screenGames
        tryCompare(main, "screenOffset", main.width, 2000,
                   "screenOffset should animate to window width on games screen")
    }

    function test_games_to_hub_transition_preserves_hub_focus(): void {
        main.hubFocus = main.focusSystems
        main.activeScreen = main.screenGames
        tryCompare(main, "screenOffset", main.width, 2000)

        main.activeScreen = main.screenHub
        tryCompare(main, "screenOffset", 0, 2000)
        // hubFocus is preserved across the round-trip (matches Escape-from-games behaviour).
        compare(main.hubFocus, main.focusSystems)
    }

    function test_hub_focus_transitions_are_idempotent(): void {
        main.hubFocus = main.focusSystems
        main.hubFocus = main.focusSystems
        compare(main.hubFocus, main.focusSystems)

        main.hubFocus = main.focusCategories
        compare(main.hubFocus, main.focusCategories)
    }

    // Enter on hub+categories transitions to hub+systems (via handleKey).
    function test_enter_on_hub_categories_routes_to_systems(): void {
        main.handleKey(Qt.Key_Return)
        compare(main.hubFocus, main.focusSystems)
        compare(main.activeScreen, main.screenHub)
    }

    // Enter on hub+systems transitions to games screen.
    function test_enter_on_hub_systems_routes_to_games(): void {
        main.hubFocus = main.focusSystems
        main.handleKey(Qt.Key_Return)
        compare(main.activeScreen, main.screenGames)
    }

    // Escape on games returns to hub (hub focus preserved).
    function test_escape_on_games_returns_to_hub(): void {
        main.hubFocus = main.focusSystems
        main.activeScreen = main.screenGames
        main.handleKey(Qt.Key_Escape)
        compare(main.activeScreen, main.screenHub)
        compare(main.hubFocus, main.focusSystems)
    }

    // Escape on hub+systems goes back to hub+categories (does NOT quit).
    function test_escape_on_hub_systems_returns_to_categories(): void {
        main.hubFocus = main.focusSystems
        main.handleKey(Qt.Key_Escape)
        compare(main.activeScreen, main.screenHub)
        compare(main.hubFocus, main.focusCategories)
    }

    // Up on hub+systems with an empty grid (test harness has no live
    // catalog) falls through to a section flip back to categories —
    // mirrors Escape but matches d-pad expectations. With a populated
    // grid, Up moves a row inside the grid; only the top row escapes.
    function test_up_on_hub_systems_returns_to_categories(): void {
        main.hubFocus = main.focusSystems
        main.handleKey(Qt.Key_Up)
        compare(main.hubFocus, main.focusCategories)
    }

    // Down on hub+categories drills into systems (matches d-pad layout
    // where systems sit visually below). Mirrors Enter without requiring
    // the user to find the keyboard.
    function test_down_on_hub_categories_routes_to_systems(): void {
        main.handleKey(Qt.Key_Down)
        compare(main.hubFocus, main.focusSystems)
        compare(main.activeScreen, main.screenHub)
    }

    // Backspace is aliased to Escape in every branch.
    function test_backspace_behaves_like_escape_on_games(): void {
        main.activeScreen = main.screenGames
        main.handleKey(Qt.Key_Backspace)
        compare(main.activeScreen, main.screenHub)
    }
}
