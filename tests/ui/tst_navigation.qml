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
    }

    function test_initial_state_is_hub(): void {
        compare(main.activeScreen, main.screenHub)
        compare(main.hubScreen.visible, true)
        compare(main.systemsScreen.visible, false)
        compare(main.gamesScreen.visible, false)
    }

    // Hard-cut peer screens: only the active screen is visible at any
    // time. Replaces the prior screenOffset-shift assertions; the slide
    // is gone (Step 8) and `visible` is now the observable contract.
    function test_activating_systems_screen_makes_systems_visible(): void {
        main.activeScreen = main.screenSystems
        compare(main.systemsScreen.visible, true)
        compare(main.hubScreen.visible, false)
        compare(main.gamesScreen.visible, false)
    }

    function test_activating_games_screen_makes_games_visible(): void {
        main.activeScreen = main.screenGames
        compare(main.gamesScreen.visible, true)
        compare(main.hubScreen.visible, false)
        compare(main.systemsScreen.visible, false)
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

    // Enter on an empty systems screen retries the current load (the
    // help bar's [OK] RETRY contract); it must not flip to games. The
    // test harness has no live catalog, so Systems is always Empty
    // here — the Ready-state drill into games is exercised live.
    function test_enter_on_empty_systems_does_not_flip_to_games(): void {
        main.activeScreen = main.screenSystems
        main.handleKey(Qt.Key_Return)
        compare(main.activeScreen, main.screenSystems,
                "Enter on an empty systems screen must retry, not flip to games")
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
