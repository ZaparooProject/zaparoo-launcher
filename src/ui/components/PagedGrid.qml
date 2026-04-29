// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0

// Bound component behavior is required because the inner Repeater +
// Loader bind to root.* properties (delegate, focused, cellWidth, …)
// across component boundaries. Keep all enclosing-scope reads explicit
// via the file-scope `root` id so qmllint can verify them; do not
// introduce intermediate Items that rely on implicit lookups.
pragma ComponentBehavior: Bound

import QtQuick
import Zaparoo.Theme

// Paged grid of tiles. Items flow row-major within a page; reaching the
// rightmost column on a non-last page swaps in the next page instantly,
// crossing past the last page wraps back to page 0 (mirror for left).
// Selection is `currentIndex` over the source model; (page, row, col)
// are derived. Cells size themselves to the available container minus
// reserved chrome — callers pass a model and delegate, the grid
// handles layout.
//
// Page changes are instant cuts (no fade, no slide). On Qt Quick's
// Software adaptation the renderer cannot keep up with a per-frame
// alpha ramp over a busy grid — translucent overlays don't subtract
// from the dirty region, so every cell underneath re-rasterizes per
// frame (text labels, cover images, card bodies). The only animated
// cue on a page change is a brief scale pulse on the page-dot for
// the new page: small element, small dirty rect, partial-update
// friendly. See docs/qml-gotchas.md → "Software-renderer animation
// costs" for the full reasoning.
Item {
    id: root

    required property var model
    required property Component delegate

    property int currentIndex: 0
    readonly property int itemCount: itemRepeater.count

    // Whether this section currently owns user focus. Tile uses this to
    // gate the selection card so only one section shows the focus cue
    // at a time on screens that host more than one tile section.
    // Defaults to true so call sites that don't care keep working
    // untouched.
    property bool focused: true

    readonly property int columns: Sizing.gridColumns
    readonly property int rows: Sizing.gridRows
    readonly property int pageSize: columns * rows
    readonly property int pageCount: Math.max(1, Math.ceil(itemCount / pageSize))
    readonly property int currentPage: Math.floor(currentIndex / pageSize)
    readonly property int currentColumn: (currentIndex % pageSize) % columns
    readonly property int currentRow: Math.floor((currentIndex % pageSize) / columns)

    // Reserved chrome around the cell area. The dot band is reserved even
    // when pageCount === 1 so cell metrics stay stable when the model is
    // swapped for one with a different pageCount — e.g. switching from a
    // single-page category like "Arcade" to a multi-page one like
    // "Consoles", or between systems whose game counts straddle pageSize.
    // Without the reservation, cellWidth/cellHeight would jump as the dot
    // band appears or disappears.
    readonly property int sideInset: Sizing.pctW(5)
    readonly property int topInset: Sizing.pctH(1)
    readonly property int dotsBandHeight: Sizing.pctH(4)
    readonly property int cellSpacingX: Sizing.pctW(3)
    readonly property int cellSpacingY: Sizing.pctH(4)

    // Computed cell dimensions — fill the available area, divided by
    // gridColumns × gridRows. Callers don't override.
    readonly property int _availableWidth: Math.max(0, width - 2 * sideInset)
    readonly property int _availableHeight:
        Math.max(0, height - dotsBandHeight - topInset)
    readonly property int cellWidth:
        Math.max(0,
                 Math.floor((root._availableWidth - (root.columns - 1) * root.cellSpacingX)
                            / root.columns))
    readonly property int cellHeight:
        Math.max(0,
                 Math.floor((root._availableHeight - (root.rows - 1) * root.cellSpacingY)
                            / root.rows))

    function setCurrentIndexImmediate(idx: int): void {
        root.currentIndex = idx
    }

    // Step the selection by (dCol, dRow). Returns true if the index
    // actually moved.
    //
    // - dCol < 0 at column 0: snap to last column of the previous page.
    //   On page 0 this wraps to (lastPage, currentRow, lastCol).
    // - dCol > 0 at last column: snap to column 0 of the next page. On
    //   the last page this wraps to (page 0, currentRow, 0).
    // - dRow < 0 at row 0: snap to last row of the same page (column
    //   preserved). Same-page cycle so Down/Up on a single screen
    //   stays predictable; Esc is the cross-screen back path.
    // - dRow > 0 at last row: snap to row 0 of the same page.
    // - Crossing a page boundary into a partial target page: clamp to
    //   the last existing item on that page (NOT necessarily on
    //   currentRow) so right at a page edge always advances rather
    //   than refusing on a hole.
    // - Wrapping vertically onto a hole on a partial last page (e.g.
    //   Down on the only filled row of a 1-row last page): clamp to
    //   the last existing item on the same page rather than refusing.
    function moveSelection(dCol: int, dRow: int): bool {
        if (root.itemCount <= 0)
            return false
        const newColAbs = root.currentColumn + dCol
        let newPage = root.currentPage
        let newCol = newColAbs
        if (newColAbs < 0) {
            // Wrap to last column of the previous page; on page 0, wrap
            // all the way to the last column of the last page.
            newPage = root.currentPage === 0
                      ? root.pageCount - 1
                      : root.currentPage - 1
            newCol = root.columns - 1
        } else if (newColAbs >= root.columns) {
            // Wrap to column 0 of the next page; on the last page, wrap
            // back to column 0 of page 0.
            newPage = root.currentPage === root.pageCount - 1
                      ? 0
                      : root.currentPage + 1
            newCol = 0
        }
        const newRowAbs = root.currentRow + dRow
        let newRow = newRowAbs
        if (newRowAbs < 0)
            newRow = root.rows - 1
        else if (newRowAbs >= root.rows)
            newRow = 0
        let newIndex = newPage * root.pageSize + newRow * root.columns + newCol
        if (newIndex < 0)
            return false
        if (newIndex >= root.itemCount) {
            if (newPage !== root.currentPage) {
                // Page-change overshoot — partial target page. Land on
                // its last existing item rather than refusing.
                const lastIdxOnPage =
                    Math.min((newPage + 1) * root.pageSize, root.itemCount) - 1
                if (lastIdxOnPage < 0)
                    return false
                newIndex = lastIdxOnPage
            } else if (dCol > 0) {
                // Stepped past the dataset's last item without crossing
                // a page (last page didn't reach the right column) —
                // wrap forward to item 0.
                newIndex = 0
            } else if (dCol < 0) {
                // Single-page partial row: left-wrap from col 0 lands
                // out of bounds on the same page. Wrap to last item.
                newIndex = root.itemCount - 1
            } else if (dRow !== 0) {
                // Row wrap on a partial last page that doesn't have a
                // slot at this column. Clamp to the page's last
                // existing item so the user still moves rather than
                // sticking on a hole.
                const lastIdxOnPage =
                    Math.min((newPage + 1) * root.pageSize, root.itemCount) - 1
                if (lastIdxOnPage < 0)
                    return false
                newIndex = lastIdxOnPage
            } else {
                return false
            }
        }
        if (newIndex === root.currentIndex)
            return false
        root.currentIndex = newIndex
        return true
    }

    // Defensive clamp: if the model shrinks below the saved index, keep
    // us in-bounds. The screens' onModelReset handlers re-seed
    // currentIndex immediately afterwards via setCurrentIndexImmediate,
    // but we shouldn't render with a stale index in the gap.
    onItemCountChanged: {
        if (root.currentIndex >= root.itemCount)
            root.currentIndex = Math.max(0, root.itemCount - 1)
    }

    clip: true

    Item {
        id: track

        // One page wide. Cells whose `cellPage !== root.currentPage`
        // gate themselves invisible; nothing slides or scales.
        anchors.fill: parent

        Repeater {
            id: itemRepeater

            model: root.model

            Item {
                id: cellItem

                required property int index
                required property string name
                // Every Browse model exposes `coverKey` — the relative path
                // under `resources/images/` without extension (e.g.
                // `systems/snes`, `categories/Consoles`). Tile resolves an
                // embedded PNG from the key or shows the procedural
                // fallback with `name` rendered large.
                required property string coverKey

                readonly property int cellPage: Math.floor(index / root.pageSize)
                readonly property int cellLocal: index % root.pageSize
                readonly property int cellRow: Math.floor(cellLocal / root.columns)
                readonly property int cellCol: cellLocal % root.columns
                readonly property bool isSelected: index === root.currentIndex

                width: root.cellWidth
                height: root.cellHeight
                x: root.sideInset
                   + cellCol * (root.cellWidth + root.cellSpacingX)
                y: root.topInset
                   + cellRow * (root.cellHeight + root.cellSpacingY)
                // Selected tile draws on top so its scale-up tween isn't
                // clipped by neighbours below/right of it.
                z: isSelected ? 1 : 0
                visible: cellPage === root.currentPage

                TileLoader {
                    anchors.fill: parent
                    sourceComponent: root.delegate
                    isSelected: cellItem.isSelected
                    isFocused: root.focused
                    name: cellItem.name
                    coverKey: cellItem.coverKey
                }
            }
        }
    }

    // Page indicator dots. The dot for the current page brightens AND
    // briefly pulses larger, drawing the eye to the new position after
    // an instant cell swap. Hidden for a single-page model; the band
    // height is still reserved above so hiding the row doesn't reflow
    // cells.
    Row {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Sizing.pctH(0.5)
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Sizing.pctW(1)
        visible: root.pageCount > 1

        Repeater {
            model: root.pageCount

            Rectangle {
                id: dot

                required property int index

                readonly property bool isCurrent: index === root.currentPage

                width: Sizing.pctH(1.8)
                height: width
                radius: width / 2
                color: dot.isCurrent ? Theme.textPrimary : Theme.textDim
                scale: 1

                // Pulse on the dot that just became current. Small
                // element, small dirty rect — partial-update friendly
                // even when the cell area was busy with a fresh layout
                // this frame. `running: dot.isCurrent` retriggers the
                // animation each time a new dot becomes current.
                // `alwaysRunToEnd: true` lets the previous-current
                // dot's pulse complete its cycle back to scale 1 when
                // the user mashes through pages, instead of being cut
                // off mid-bounce and leaving the dot at an
                // intermediate size.
                SequentialAnimation on scale {
                    running: dot.isCurrent
                    alwaysRunToEnd: true
                    NumberAnimation {
                        from: 1; to: 1.4
                        duration: 80
                        easing.type: Easing.OutQuad
                    }
                    NumberAnimation {
                        from: 1.4; to: 1
                        duration: 120
                        easing.type: Easing.InQuad
                    }
                }
            }
        }
    }
}
