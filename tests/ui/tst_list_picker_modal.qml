// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0

import QtQuick
import QtTest
import Zaparoo.Theme
import Zaparoo.Ui

// `_entries` returns a plain JS array of `{ id, label }` objects. The
// AOT compiler can't infer the shape, so leaving it untyped trips the
// compiler category for that one helper. Same pattern the production
// `entries`-consuming files use (ContextMenu.qml, ListPickerModal.qml).
// qmllint disable compiler

// Direct ListPickerModal coverage. We exercise the navigation, signal,
// and initial-selection behavior end-to-end on the component itself —
// no screens involved, so this stays inside the "test reusable
// components, not screens" rule.
TestCase {
    id: testCase
    name: "UiListPickerModal"
    when: windowShown
    width: 640
    height: 480
    visible: true

    Component.onCompleted: {
        Sizing.screenWidth = testCase.width
        Sizing.screenHeight = testCase.height
    }

    ListPickerModal {
        id: picker
        anchors.fill: parent
        title: "Pick one"
    }

    SignalSpy {
        id: acceptedSpy
        target: picker
        signalName: "accepted"
    }

    SignalSpy {
        id: closeSpy
        target: picker
        signalName: "closeRequested"
    }

    function init(): void {
        Sizing.screenWidth = testCase.width
        Sizing.screenHeight = testCase.height
        picker.open = false
        picker.entries = []
        picker.initialId = ""
        picker.currentIndex = 0
        acceptedSpy.clear()
        closeSpy.clear()
    }

    function _entries(count) {
        const list = []
        for (let i = 0; i < count; ++i)
            list.push({ id: "id-" + i, label: "Item " + i })
        return list
    }

    function test_open_with_no_initial_id_starts_at_zero(): void {
        picker.entries = _entries(3)
        picker.open = true
        compare(picker.currentIndex, 0)
    }

    function test_open_with_matching_initial_id_selects_entry(): void {
        picker.entries = _entries(4)
        picker.initialId = "id-2"
        picker.open = true
        compare(picker.currentIndex, 2)
    }

    function test_open_with_unknown_initial_id_falls_back_to_zero(): void {
        picker.entries = _entries(3)
        picker.initialId = "id-missing"
        picker.open = true
        compare(picker.currentIndex, 0)
    }

    function test_move_advances_and_wraps_forward(): void {
        picker.entries = _entries(3)
        picker.open = true
        picker.move(1)
        compare(picker.currentIndex, 1)
        picker.move(1)
        compare(picker.currentIndex, 2)
        picker.move(1)
        compare(picker.currentIndex, 0)
    }

    function test_move_retreats_and_wraps_backward(): void {
        picker.entries = _entries(3)
        picker.open = true
        picker.move(-1)
        compare(picker.currentIndex, 2)
        picker.move(-1)
        compare(picker.currentIndex, 1)
    }

    function test_move_with_empty_entries_is_noop(): void {
        picker.entries = []
        picker.open = true
        picker.currentIndex = 0
        picker.move(1)
        compare(picker.currentIndex, 0)
        picker.move(-1)
        compare(picker.currentIndex, 0)
    }

    function test_handle_action_up_down_drives_navigation(): void {
        picker.entries = _entries(3)
        picker.open = true
        picker.handleAction("down")
        compare(picker.currentIndex, 1)
        picker.handleAction("down")
        compare(picker.currentIndex, 2)
        picker.handleAction("up")
        compare(picker.currentIndex, 1)
    }

    function test_handle_action_accept_emits_accepted_with_current_id(): void {
        picker.entries = _entries(3)
        picker.open = true
        picker.currentIndex = 2
        picker.handleAction("accept")
        compare(acceptedSpy.count, 1)
        compare(acceptedSpy.signalArguments[0][0], "id-2")
    }

    function test_handle_action_accept_with_empty_entries_no_signal(): void {
        picker.entries = []
        picker.open = true
        picker.currentIndex = 0
        picker.handleAction("accept")
        compare(acceptedSpy.count, 0)
    }

    function test_handle_action_cancel_emits_close_requested(): void {
        picker.entries = _entries(3)
        picker.open = true
        picker.handleAction("cancel")
        compare(closeSpy.count, 1)
    }

    function test_reopen_recomputes_initial_index(): void {
        // First open lands on a match.
        picker.entries = _entries(4)
        picker.initialId = "id-3"
        picker.open = true
        compare(picker.currentIndex, 3)
        // Close, swap entries + initialId, re-open. The next open must
        // re-resolve from the new initialId, not carry the prior index.
        picker.open = false
        picker.entries = _entries(2)
        picker.initialId = "id-1"
        picker.open = true
        compare(picker.currentIndex, 1)
    }

    function test_long_list_caps_visible_rows(): void {
        // _viewportHeight is bounded by _maxVisibleRows (= 6 in source).
        // For an 8-entry list, the viewport must reflect the cap, not
        // the full content height. _contentHeight is unbounded so the
        // Flickable can scroll.
        picker.entries = _entries(8)
        picker.open = true
        const stride = picker._rowHeight + picker._rowSpacing
        const expectedViewport =
              6 * picker._rowHeight + 5 * picker._rowSpacing
        compare(picker._viewportHeight, expectedViewport)
        compare(picker._contentHeight,
                8 * picker._rowHeight + 7 * picker._rowSpacing)
    }
}
