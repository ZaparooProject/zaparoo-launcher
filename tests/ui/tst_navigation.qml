// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0

import QtQuick
import QtTest
import Zaparoo.App

// Tests poke `main.hubScreen._pendingCategory` directly to simulate
// mid-drill-in state. qmllint flags the access as "can be shadowed" —
// it's a regular property, not a final method on a Rust singleton —
// but for a test that's the whole point: we want to read/write a piece
// of internal state. Suppress the compiler category for this file so
// the test setup doesn't drown the lint output.
// qmllint disable compiler

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

    // The drill-in orchestration stages set_category in
    // _pendingCategory and consumes it after a 250 ms PauseAnimation.
    // If the user escapes during that window, the cancellation must
    // clear the pending value — otherwise the next drill-in would
    // queue a stale category. CategoriesModel is empty in this
    // harness, so seed _pendingCategory directly to simulate mid-
    // drill-in state.
    function test_escape_during_drill_in_clears_pending_category(): void {
        main.hubFocus = main.focusSystems
        main.hubScreen._pendingCategory = "FakeCategory"
        main.hubFocus = main.focusCategories
        compare(main.hubScreen._pendingCategory, "")
    }

    // The cancellation must NOT fire when section flips into
    // focusSystems — that's the drill-in itself. Pending value should
    // survive long enough for the wrapper Transition's ScriptAction
    // to consume it.
    function test_drill_into_systems_preserves_pending_category(): void {
        main.hubScreen._pendingCategory = "Pending"
        main.hubFocus = main.focusSystems
        compare(main.hubScreen._pendingCategory, "Pending")
    }

    // The wrapper hidden→shown Transition is a SequentialAnimation:
    // PauseAnimation(250 ms) → ScriptAction(consume _pendingCategory) →
    // NumberAnimation(opacity 0→1, 150 ms). This test pins down the full
    // ordering invariant: the ScriptAction must fire AFTER the
    // PauseAnimation (not inline at section change) and the opacity
    // Behavior must complete the ramp to 1.0. A regression that
    // reorders the SequentialAnimation steps (moving the ScriptAction
    // before the PauseAnimation) would re-introduce the
    // carousel-mid-animation freeze the comment block warns against,
    // and this test would catch it because the synchronous compare
    // immediately after the section change would see "" instead of the
    // pending value.
    function test_transition_consumes_pending_after_full_sequence(): void {
        main.hubScreen._pendingCategory = "TestCategory"
        main.hubFocus = main.focusSystems
        // Synchronously after section change the PauseAnimation is
        // still in flight, so the ScriptAction has not yet run.
        compare(main.hubScreen._pendingCategory, "TestCategory",
                "ScriptAction must not fire inline with the section change")
        // After the 250 ms PauseAnimation completes, the ScriptAction
        // clears the pending value. tryCompare polls so the timeout
        // tolerates scheduling jitter on CI runners.
        tryCompare(main.hubScreen, "_pendingCategory", "", 1500,
                   "ScriptAction must clear _pendingCategory after PauseAnimation")
        // The opacity ramp is the last step; reaching 1.0 proves the
        // full SequentialAnimation completed.
        tryCompare(main.hubScreen, "systemsContainerOpacity", 1.0, 1500,
                   "Wrapper opacity must reach 1.0 after the full sequence")
    }
}
