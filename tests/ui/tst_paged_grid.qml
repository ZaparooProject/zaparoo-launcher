// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0

import QtQuick
import QtTest
import Zaparoo.Theme
import Zaparoo.Ui

// Direct moveSelection coverage. PagedGrid wraps in surprising ways
// (within-row Left/Right wrap, vertical page advance/retreat, partial
// last-page hole clamps), so each branch needs its own explicit case.
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

    // ── Vertical paging (Up/Down crosses page boundaries) ───────────────

    function test_down_at_bottom_row_advances_to_next_page(): void {
        // 24 items, two full pages. From (page 0, row 2, col 0) = 8,
        // Down advances to (page 1, row 0, col 0) = 12.
        fillModel(24)
        grid.setCurrentIndexImmediate(8)
        compare(grid.moveSelection(0, 1), true)
        compare(grid.currentIndex, 12)
    }

    function test_up_at_top_row_retreats_to_previous_page(): void {
        // 24 items. From (page 1, row 0, col 0) = 12, Up retreats to
        // (page 0, row 2, col 0) = 8.
        fillModel(24)
        grid.setCurrentIndexImmediate(12)
        compare(grid.moveSelection(0, -1), true)
        compare(grid.currentIndex, 8)
    }

    function test_down_at_last_page_last_row_wraps_to_page_zero(): void {
        // 24 items. From (page 1, row 2, col 0) = 20, Down wraps to
        // (page 0, row 0, col 0) = 0.
        fillModel(24)
        grid.setCurrentIndexImmediate(20)
        compare(grid.moveSelection(0, 1), true)
        compare(grid.currentIndex, 0)
    }

    function test_up_at_page_zero_first_row_wraps_to_last_page(): void {
        // 24 items. From (page 0, row 0, col 0) = 0, Up wraps to
        // (page 1, row 2, col 0) = 20.
        fillModel(24)
        compare(grid.moveSelection(0, -1), true)
        compare(grid.currentIndex, 20)
    }

    function test_up_at_page_zero_wraps_to_partial_last_page_clamped(): void {
        // 20 items: page 1 has rows 0..1 (12..19). Up from index 0
        // would land on (page 1, row 2, col 0) = 20 — a hole. Clamp
        // to the last item on the partial last page (19).
        fillModel(20)
        compare(grid.moveSelection(0, -1), true)
        compare(grid.currentIndex, 19)
    }

    function test_down_overshoot_to_partial_page_clamps_to_last_existing(): void {
        // 13 items: page 1 has only index 12 (row 0, col 0). From
        // (page 0, row 2, col 3) = 11, Down would land on (page 1,
        // row 0, col 3) = 15 — a hole. Clamp to last item on the
        // partial page (12).
        fillModel(13)
        grid.setCurrentIndexImmediate(11)
        compare(grid.moveSelection(0, 1), true)
        compare(grid.currentIndex, 12)
    }

    function test_down_below_last_filled_row_on_partial_page_wraps_to_page_zero(): void {
        // 14 items: standing at (page 1, row 0, col 1) = 13 (the last
        // item; row 1 of this page is empty). Down advances off the
        // last filled row — same as overflowing the grid, so on the
        // last page it wraps to (page 0, row 0, same col) = 1.
        fillModel(14)
        grid.setCurrentIndexImmediate(13)
        compare(grid.moveSelection(0, 1), true)
        compare(grid.currentIndex, 1)
    }

    function test_up_from_partial_page_retreats_to_previous_page(): void {
        // 14 items: page 1 has indices 12, 13. From (page 1, row 0,
        // col 1) = 13, Up retreats to (page 0, row 2, col 1) = 9
        // (a real cell on the full prev page).
        fillModel(14)
        grid.setCurrentIndexImmediate(13)
        compare(grid.moveSelection(0, -1), true)
        compare(grid.currentIndex, 9)
    }

    // ── Single-page Up/Down (wraps within the page) ─────────────────────

    function test_single_page_up_wraps_to_last_row_same_page(): void {
        // 12 items, single full page. From (row 0, col 0) = 0,
        // Up wraps to (row 2, col 0) = 8.
        fillModel(12)
        compare(grid.pageCount, 1)
        compare(grid.moveSelection(0, -1), true)
        compare(grid.currentIndex, 8)
    }

    function test_single_page_down_at_partial_last_row_wraps_to_top(): void {
        // 6 items, single partial page. From (row 1, col 1) = 5, Down
        // steps below the last filled row, which on the only (=last)
        // page wraps to (row 0, same col) = 1. Mirrors the full-page
        // single-page Down-wrap so partial pages aren't a special case.
        fillModel(6)
        grid.setCurrentIndexImmediate(5)
        compare(grid.pageCount, 1)
        compare(grid.moveSelection(0, 1), true)
        compare(grid.currentIndex, 1)
    }

    // ── Horizontal within-row wrap (Left/Right never changes page) ──────

    function test_right_at_last_col_wraps_within_row(): void {
        // 24 items. From (page 0, row 0, col 3) = 3, Right wraps to
        // (page 0, row 0, col 0) = 0. No page change.
        fillModel(24)
        grid.setCurrentIndexImmediate(3)
        compare(grid.moveSelection(1, 0), true)
        compare(grid.currentIndex, 0)
    }

    function test_left_at_first_col_wraps_within_row(): void {
        // 24 items. From (page 0, row 0, col 0) = 0, Left wraps to
        // (page 0, row 0, col 3) = 3. No page change.
        fillModel(24)
        compare(grid.moveSelection(-1, 0), true)
        compare(grid.currentIndex, 3)
    }

    function test_right_on_partial_row_wraps_within_filled(): void {
        // 14 items: page 1 row 0 has (12, 13). From idx 13, Right
        // wraps within the row to col 0 = 12.
        fillModel(14)
        grid.setCurrentIndexImmediate(13)
        compare(grid.moveSelection(1, 0), true)
        compare(grid.currentIndex, 12)
    }

    function test_left_on_partial_row_wraps_within_filled(): void {
        // 14 items. From idx 12 (page 1, row 0, col 0), Left wraps
        // to last filled col on the row = idx 13.
        fillModel(14)
        grid.setCurrentIndexImmediate(12)
        compare(grid.moveSelection(-1, 0), true)
        compare(grid.currentIndex, 13)
    }

    function test_single_page_left_wrap_to_last_col_when_row_full(): void {
        // 6 items at 4-cols: row 0 is full (0..3), row 1 partial (4..5).
        // From idx 0, Left wraps to last col on full row 0 = idx 3.
        fillModel(6)
        compare(grid.pageCount, 1)
        compare(grid.moveSelection(-1, 0), true)
        compare(grid.currentIndex, 3)
    }

    function test_single_page_left_wrap_partial_row_clamps_to_last_item(): void {
        // 2 items at 4-cols: row 0 partial (0..1). From idx 0, Left
        // wraps to last filled col on this row (col 1) = idx 1.
        fillModel(2)
        compare(grid.pageCount, 1)
        compare(grid.moveSelection(-1, 0), true)
        compare(grid.currentIndex, 1)
    }

    function test_single_page_right_at_last_filled_wraps_to_row_start(): void {
        // 6 items. From (row 1, col 1) = 5, Right wraps within the
        // partial row to col 0 = idx 4.
        fillModel(6)
        grid.setCurrentIndexImmediate(5)
        compare(grid.moveSelection(1, 0), true)
        compare(grid.currentIndex, 4)
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

    // ── pageBy (L/R shoulder shortcut, unchanged) ────────────────────────

    function test_pageBy_advances_one_page(): void {
        fillModel(24)
        grid.setCurrentIndexImmediate(2) // (row 0, col 2)
        compare(grid.pageBy(1), true)
        compare(grid.currentPage, 1)
        // Preserves (row, col): (page 1, row 0, col 2) = 14.
        compare(grid.currentIndex, 14)
    }

    function test_pageBy_wraps_negative(): void {
        fillModel(24)
        compare(grid.pageBy(-1), true)
        compare(grid.currentPage, 1)
    }

    function test_pageBy_single_page_returns_false(): void {
        fillModel(6)
        compare(grid.pageCount, 1)
        compare(grid.pageBy(1), false)
        compare(grid.pageBy(-1), false)
    }

    function test_pageBy_partial_target_clamps_to_last_item(): void {
        // 14 items, currentIndex 5 (row 1, col 1) on page 0. pageBy(1)
        // targets (page 1, row 1, col 1) = 17 — a hole. Clamps to
        // last on page 1 (13).
        fillModel(14)
        grid.setCurrentIndexImmediate(5)
        compare(grid.pageBy(1), true)
        compare(grid.currentIndex, 13)
    }

    // ── Page-stack flags (gutter arrows / scrollbar derivations) ─────────

    function test_hasPages_flags_track_currentPage(): void {
        fillModel(36) // 3 pages
        grid.setCurrentIndexImmediate(0)
        compare(grid.hasPagesAbove, false)
        compare(grid.hasPagesBelow, true)
        grid.setCurrentIndexImmediate(12) // page 1
        compare(grid.hasPagesAbove, true)
        compare(grid.hasPagesBelow, true)
        grid.setCurrentIndexImmediate(24) // page 2
        compare(grid.hasPagesAbove, true)
        compare(grid.hasPagesBelow, false)
    }

    function test_hasPages_flags_single_page_dataset(): void {
        fillModel(6)
        compare(grid.pageCount, 1)
        compare(grid.hasPagesAbove, false)
        compare(grid.hasPagesBelow, false)
    }

    // ── Scroll thumb sizing (totalItemsOverride) ─────────────────────────

    function test_totalPageCount_uses_override(): void {
        // 24 items loaded — 2 pages on the 4×3 grid. With an override
        // saying total is 60 (5 pages), totalPageCount must reflect 5
        // so the scroll thumb sizes from the dataset's true total
        // rather than the loaded slice.
        fillModel(24)
        compare(grid.pageCount, 2)
        grid.totalItemsOverride = 60
        compare(grid.totalPageCount, 5)
        grid.totalItemsOverride = -1
        compare(grid.totalPageCount, 2)
    }
}
