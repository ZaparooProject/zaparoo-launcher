// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0

import QtQuick
import QtTest
import Zaparoo.Theme
import Zaparoo.Ui

// Direct moveSelection coverage. PagedGrid wraps in surprising ways
// (page-overshoot lands on last existing item, single-page wraps,
// vertical wrap stays within the current page), so each branch needs
// its own explicit case.
//
// Test geometry pinned to 1280×480, which makes Sizing yield a 4×3
// grid (pageSize=12). All test indices below assume that layout.
TestCase {
    id: testCase
    name: "UiPagedGrid"
    when: windowShown
    width: 1280
    height: 480
    visible: true

    Component.onCompleted: {
        Sizing.screenWidth = testCase.width
        Sizing.screenHeight = testCase.height
    }

    ListModel {
        id: model
    }

    Component {
        id: cellDelegate
        Item {
            required property string name
            required property string coverKey
            required property bool isSelected
            required property bool isFocused
        }
    }

    PagedGrid {
        id: grid
        anchors.fill: parent
        model: model
        delegate: cellDelegate
    }

    function fillModel(count: int): void {
        model.clear()
        for (let i = 0; i < count; i++)
            model.append({ "name": "item-" + i, "coverKey": "" })
        // Wait for Repeater itemCount to catch up before any test assertions.
        tryCompare(grid, "itemCount", count)
    }

    function init(): void {
        Sizing.screenWidth = testCase.width
        Sizing.screenHeight = testCase.height
        fillModel(0)
        grid.setCurrentIndexImmediate(0)
    }

    function test_geometry_matches_pinned_resolution(): void {
        compare(grid.columns, 4, "expected 4 columns at 480px height")
        compare(grid.rows, 3, "expected 3 rows at 480px height")
        compare(grid.pageSize, 12)
    }

    function test_empty_model_refuses_movement(): void {
        compare(grid.itemCount, 0)
        compare(grid.moveSelection(1, 0), false)
        compare(grid.moveSelection(0, 1), false)
        compare(grid.currentIndex, 0)
    }

    function test_within_page_step_right(): void {
        fillModel(20)
        compare(grid.currentIndex, 0)
        compare(grid.moveSelection(1, 0), true)
        compare(grid.currentIndex, 1)
    }

    function test_within_page_step_down(): void {
        fillModel(20)
        compare(grid.moveSelection(0, 1), true)
        // (row 0, col 0) → (row 1, col 0) → index 4
        compare(grid.currentIndex, 4)
    }

    function test_up_at_top_row_wraps_to_bottom_of_same_page(): void {
        fillModel(20)
        // currentIndex 0 → page 0, row 0, col 0. Up wraps to row 2,
        // col 0 on the same page → index 8.
        compare(grid.moveSelection(0, -1), true)
        compare(grid.currentIndex, 8)
    }

    function test_down_at_bottom_row_wraps_to_top_of_same_page(): void {
        fillModel(20)
        grid.setCurrentIndexImmediate(8) // (page 0, row 2, col 0)
        compare(grid.currentRow, 2)
        compare(grid.moveSelection(0, 1), true)
        // Wraps to (page 0, row 0, col 0) → index 0.
        compare(grid.currentIndex, 0)
    }

    function test_down_into_partial_page_hole_clamps_to_last_existing(): void {
        // 14 items: page 1 has rows 0 (cells 12..15) — but only 12, 13
        // exist (indices 12, 13). Standing at (page 1, row 0, col 1)
        // = index 13 and pressing down would land on (page 1, row 1,
        // col 1) = index 17, which doesn't exist. Clamps to the last
        // item on page 1 (13). No move, returns false.
        fillModel(14)
        grid.setCurrentIndexImmediate(13)
        compare(grid.moveSelection(0, 1), false)
        compare(grid.currentIndex, 13)
    }

    function test_up_into_partial_page_hole_clamps_to_last_existing(): void {
        // 14 items as above. From (page 1, row 0, col 1) = 13, up wraps
        // to (page 1, row 2, col 1) = 21 — doesn't exist. Clamps to the
        // last item on page 1 (13). No move, returns false.
        fillModel(14)
        grid.setCurrentIndexImmediate(13)
        compare(grid.moveSelection(0, -1), false)
        compare(grid.currentIndex, 13)
    }

    function test_right_crosses_page_boundary_to_full_target(): void {
        // 24 items = exactly 2 pages. Right at (0, row 0, col 3) lands
        // at (1, row 0, col 0).
        fillModel(24)
        grid.setCurrentIndexImmediate(3)
        compare(grid.moveSelection(1, 0), true)
        compare(grid.currentIndex, 12)
    }

    function test_right_overshoot_to_partial_page_lands_on_last_existing(): void {
        // 20 items: page 1 has 8 items (12..19). Right from (page 0,
        // row 2, col 3) overshoots a hole on (page 1, row 2, col 0)
        // and clamps to the last item on the partial page (19).
        fillModel(20)
        grid.setCurrentIndexImmediate(11)
        compare(grid.moveSelection(1, 0), true)
        compare(grid.currentIndex, 19)
    }

    function test_left_at_first_column_wraps_to_previous_page(): void {
        fillModel(24)
        grid.setCurrentIndexImmediate(12) // (page 1, row 0, col 0)
        compare(grid.moveSelection(-1, 0), true)
        // (page 0, row 0, last col) → 0*12 + 0*4 + 3 = 3
        compare(grid.currentIndex, 3)
    }

    function test_left_at_page_zero_wraps_to_last_page(): void {
        fillModel(24)
        compare(grid.currentIndex, 0)
        compare(grid.moveSelection(-1, 0), true)
        // (last page = 1, row 0, last col) → 1*12 + 0*4 + 3 = 15
        compare(grid.currentIndex, 15)
    }

    function test_right_at_last_page_wraps_to_first(): void {
        fillModel(24)
        grid.setCurrentIndexImmediate(15) // (page 1, row 0, col 3)
        compare(grid.moveSelection(1, 0), true)
        // Wraps to (page 0, row 0, col 0)
        compare(grid.currentIndex, 0)
    }

    function test_single_page_right_wrap_from_last_item(): void {
        // 6 items = single page (page 0, rows 0..1, only col 0..1 on row 1).
        fillModel(6)
        grid.setCurrentIndexImmediate(5) // (page 0, row 1, col 1)
        compare(grid.pageCount, 1)
        compare(grid.moveSelection(1, 0), true)
        // Single-page wrap: lands at item 0.
        compare(grid.currentIndex, 0)
    }

    function test_single_page_left_wrap_to_last_col_when_row_full(): void {
        // 6 items at 4-cols: row 0 is full (0..3), row 1 partial (4..5).
        // Left-wrap from index 0 lands on (row 0, col 3) → index 3.
        // Item 3 exists, so no overshoot adjustment fires.
        fillModel(6)
        compare(grid.currentIndex, 0)
        compare(grid.pageCount, 1)
        compare(grid.moveSelection(-1, 0), true)
        compare(grid.currentIndex, 3)
    }

    function test_single_page_left_wrap_partial_row_clamps_to_last_item(): void {
        // 2 items at 4-cols: row 0 is partial (0..1). Left-wrap from
        // index 0 would land on (row 0, col 3) = index 3, which doesn't
        // exist; the dCol<0 branch then clamps to the last item (1).
        fillModel(2)
        compare(grid.currentIndex, 0)
        compare(grid.pageCount, 1)
        compare(grid.moveSelection(-1, 0), true)
        compare(grid.currentIndex, 1)
    }

    function test_no_movement_returns_false(): void {
        fillModel(20)
        compare(grid.moveSelection(0, 0), false)
        compare(grid.currentIndex, 0)
    }

    function test_item_count_clamp_keeps_current_in_bounds(): void {
        // Shrink the model directly (without an intermediate clear)
        // so the clamp at PagedGrid.onItemCountChanged is exercised
        // with a stale-but-valid currentIndex (not just 0).
        fillModel(20)
        grid.setCurrentIndexImmediate(19)
        model.remove(10, 10)
        tryCompare(grid, "itemCount", 10)
        compare(grid.currentIndex, 9)
    }
}
