// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0

import QtQuick
import QtTest
import Zaparoo.App

// Exercises the hub ↔ systems ↔ games navigation state machine defined
// in Main.qml. State is driven either by writing to the activeScreen
// property (the observable contract) or by calling root.handleKey(key)
// directly — the latter proves the Keys.onPressed routing, which we
// can't exercise with keyClick because offscreen ApplicationWindows
// don't receive routed key events reliably.
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
        // Let the screenOffset animation settle before each test.
        tryCompare(main, "screenOffset", 0, 2000)
    }

    function test_initial_state_is_hub(): void {
        compare(main.activeScreen, main.screenHub)
        compare(main.screenOffset, 0)
    }

    function test_activating_systems_screen_shifts_offset_to_width(): void {
        main.activeScreen = main.screenSystems
        tryCompare(main, "screenOffset", main.width, 2000,
                   "screenOffset should animate to window width on systems screen")
    }

    function test_activating_games_screen_shifts_offset_to_double_width(): void {
        main.activeScreen = main.screenGames
        tryCompare(main, "screenOffset", 2 * main.width, 2000,
                   "screenOffset should animate to 2× window width on games screen")
    }

    // Enter on hub categories drills into systems screen.
    function test_enter_on_hub_routes_to_systems(): void {
        main.handleKey(Qt.Key_Return)
        compare(main.activeScreen, main.screenSystems)
    }

    // Down on hub categories drills into systems (matches d-pad layout
    // where systems sit visually "below"). Mirrors Enter without
    // requiring the user to find the keyboard.
    function test_down_on_hub_routes_to_systems(): void {
        main.handleKey(Qt.Key_Down)
        compare(main.activeScreen, main.screenSystems)
    }

    // Enter on systems drills into games screen.
    function test_enter_on_systems_routes_to_games(): void {
        main.activeScreen = main.screenSystems
        main.handleKey(Qt.Key_Return)
        compare(main.activeScreen, main.screenGames)
    }

    // Escape on games goes back to systems (one peer up the stack).
    function test_escape_on_games_returns_to_systems(): void {
        main.activeScreen = main.screenGames
        main.handleKey(Qt.Key_Escape)
        compare(main.activeScreen, main.screenSystems)
    }

    // Escape on systems goes back to hub.
    function test_escape_on_systems_returns_to_hub(): void {
        main.activeScreen = main.screenSystems
        main.handleKey(Qt.Key_Escape)
        compare(main.activeScreen, main.screenHub)
    }

    // Up on systems with an empty grid (test harness has no live
    // catalog) falls through to a peer-screen flip back to hub —
    // mirrors Escape but matches d-pad expectations. With a populated
    // grid, Up moves a row inside the grid; only the top row escapes.
    function test_up_at_top_row_on_systems_returns_to_hub(): void {
        main.activeScreen = main.screenSystems
        main.handleKey(Qt.Key_Up)
        compare(main.activeScreen, main.screenHub)
    }

    // Backspace is aliased to Escape in every branch.
    function test_backspace_behaves_like_escape_on_games(): void {
        main.activeScreen = main.screenGames
        main.handleKey(Qt.Key_Backspace)
        compare(main.activeScreen, main.screenSystems)
    }
}
