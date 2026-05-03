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
        // The cold-launch BootOverlay normally hides every screen until
        // Core's catalog reaches READY. Tests don't run a real Core, so
        // we mark the boot complete up-front; otherwise every visibility
        // assertion below would fail against the boot curtain.
        main.bootComplete = true
        main.activeScreen = main.screenHub
        // Hub focus is two rows now (categories + actions); reset both
        // axes so a prior test's row-jump doesn't leak into the next.
        // qmllint disable compiler
        main.hubScreen.resetFocus()
        // qmllint enable compiler
    }

    function test_initial_state_is_hub(): void {
        compare(main.activeScreen, main.screenHub)
        compare(main.hubScreen.visible, true)
        compare(main.systemsScreen.visible, false)
        compare(main.gamesScreen.visible, false)
    }

    // Hard-cut peer screens: only the active screen is visible at any
    // time. `visible` binds directly to `root.activeScreen === ...` in
    // MainLayout, so the swap is synchronous with the assignment.
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

    // Down on hub moves focus between the categories row and the
    // actions row (Recently Played / Settings); it must never flip
    // off-screen to systems. Accept is the only path that drills
    // into another screen.
    function test_down_on_hub_does_not_route_to_systems(): void {
        main.handleKey(Qt.Key_Down)
        compare(main.activeScreen, main.screenHub,
                "Down on hub must not flip to systems — only Accept drills")
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

    // Up on systems is a grid-internal move; at the top row (or on an
    // empty grid in the test harness) it no-ops rather than flipping
    // back to hub. Escape is the only back path.
    function test_up_on_empty_systems_does_not_return_to_hub(): void {
        main.activeScreen = main.screenSystems
        main.handleKey(Qt.Key_Up)
        compare(main.activeScreen, main.screenSystems,
                "Up on systems must not flip to hub — Escape is the back path")
    }

    // Backspace is aliased to Escape in every branch.
    function test_backspace_behaves_like_escape_on_games(): void {
        main.activeScreen = main.screenGames
        main.handleKey(Qt.Key_Backspace)
        compare(main.activeScreen, main.screenSystems)
    }

    // Cross-row mapping. The test harness has no live CategoriesModel
    // so we can't drive the full handleAction("down") flow with real
    // categories — instead we unit-test the pure arithmetic helper
    // that owns the math. The shape verifies the user-stated
    // 4-over-2-centered mapping (a→e, b→e, c→f, d→f and e→b, f→c)
    // and a couple of degenerate cases.
    // qmllint disable compiler
    function test_cross_row_4_over_2_down(): void {
        const map = main.hubScreen._mapCrossRow
        compare(map(0, 4, 2), 0, "Down from top[0] (a) → bottom[0] (e)")
        compare(map(1, 4, 2), 0, "Down from top[1] (b) → bottom[0] (e)")
        compare(map(2, 4, 2), 1, "Down from top[2] (c) → bottom[1] (f)")
        compare(map(3, 4, 2), 1, "Down from top[3] (d) → bottom[1] (f)")
    }

    function test_cross_row_4_over_2_up(): void {
        const map = main.hubScreen._mapCrossRow
        compare(map(0, 2, 4), 1, "Up from bottom[0] (e) → top[1] (b)")
        compare(map(1, 2, 4), 2, "Up from bottom[1] (f) → top[2] (c)")
    }

    // 4-over-3 (the previous Favorites layout) — the offset is 0.5,
    // so Math.round's half-toward-+∞ rounds the boundary cells right.
    function test_cross_row_4_over_3(): void {
        const map = main.hubScreen._mapCrossRow
        compare(map(0, 4, 3), 0)
        compare(map(1, 4, 3), 1)
        compare(map(2, 4, 3), 2)
        compare(map(3, 4, 3), 2, "Rightmost top clamps onto rightmost bottom")
    }

    function test_cross_row_equal_counts_is_identity(): void {
        const map = main.hubScreen._mapCrossRow
        compare(map(0, 3, 3), 0)
        compare(map(1, 3, 3), 1)
        compare(map(2, 3, 3), 2)
    }

    function test_cross_row_empty_destination_returns_zero(): void {
        const map = main.hubScreen._mapCrossRow
        compare(map(2, 4, 0), 0,
                "Degenerate destCount=0 returns 0 — caller guards the no-op")
    }

    // Up on the top row wraps onto the bottom row (the two rows form a
    // closed loop). Test harness has no live categories, so we start
    // at top[0] and just verify currentRow flipped — the destination
    // index is verified by the _mapCrossRow tests above.
    function test_up_on_top_row_wraps_to_bottom_row(): void {
        // resetFocus() in init() leaves us on top[0].
        main.handleKey(Qt.Key_Up)
        compare(main.hubScreen.currentRow, 1,
                "Up from top should wrap to bottom row")
    }

    // Bottom row wraps left/right. Use Down from top[0] to drop into
    // the bottom row first; bottomCount=2 so a single Right at the
    // last index must wrap to 0.
    function test_bottom_row_right_wraps_to_first(): void {
        main.handleKey(Qt.Key_Down)
        // _mapCrossRow(0, topCount=0, 2) lands us at bottom[1].
        compare(main.hubScreen.currentRow, 1)
        compare(main.hubScreen.currentIndex, 1,
                "Centered map of top[0] with empty top lands at bottom[1]")
        main.handleKey(Qt.Key_Right)
        compare(main.hubScreen.currentIndex, 0,
                "Right at last bottom-row index wraps to first")
    }

    function test_bottom_row_left_wraps_to_last(): void {
        main.handleKey(Qt.Key_Down)
        compare(main.hubScreen.currentRow, 1)
        // Drive Left twice: bottom[1] → bottom[0] → wrap to bottom[1].
        main.handleKey(Qt.Key_Left)
        compare(main.hubScreen.currentIndex, 0)
        main.handleKey(Qt.Key_Left)
        compare(main.hubScreen.currentIndex, 1,
                "Left at first bottom-row index wraps to last")
    }
    // qmllint enable compiler
}
