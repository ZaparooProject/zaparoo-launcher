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

// Paged grid of tiles. Items flow row-major within a page; pages stack
// **vertically** — pressing Down at the bottom row swaps in the next
// page instantly (same column, top row), Up at the top row swaps in
// the previous page (same column, bottom row). Crossing past the last
// page wraps to page 0; mirror for Up at page 0. Left/Right wrap
// **within the current row** and never change pages, so a partial last
// row cycles among its own filled cells.
//
// Selection is `currentIndex` over the source model; (page, row, col)
// are derived. Cells size themselves to the available container minus
// reserved chrome — callers pass a model and delegate, the grid
// handles layout. The right gutter renders a scroll indicator (up/down
// arrows + free-floating thumb) sized and positioned from
// `totalItemsOverride` (with `itemCount` fallback), so paginated
// callers like `GamesScreen` get a thumb that reflects the dataset's
// true total page count rather than the loaded slice.
//
// Page changes are instant cuts (no fade, no slide). On Qt Quick's
// Software adaptation the renderer cannot keep up with a per-frame
// alpha ramp over a busy grid — translucent overlays don't subtract
// from the dirty region, so every cell underneath re-rasterizes per
// frame (cover images, card bodies). See docs/qml-gotchas.md →
// "Software-renderer animation costs" for the full reasoning.
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

    // Emitted when the user is sitting on the last loaded page after a
    // selection move. Models with more data fetch the next page in
    // response; models without ignore it. The grid does not know
    // whether the model has more data — that is a model concern, kept
    // out of this component so it stays generic.
    signal loadMoreRequested()
    // Mouse entry points. Screens own persistence and activation side
    // effects, so the grid only updates its focused index and reports the
    // row the pointer targeted.
    signal itemHovered(int index)
    signal itemClicked(int index)

    // Per-instance shape overrides. -1 means "use the global Sizing
    // default" — Systems screen leaves these alone so the systems grid
    // stays at gridColumns × gridRows; Games screen wires them to
    // gamesGridColumns × gamesGridRows so its taller cover art gets the
    // vertical room a 3-row layout would starve.
    property int columnsOverride: -1
    property int rowsOverride: -1
    readonly property int columns:
        columnsOverride > 0 ? columnsOverride : Sizing.gridColumns
    readonly property int rows:
        rowsOverride > 0 ? rowsOverride : Sizing.gridRows
    readonly property int pageSize: columns * rows
    readonly property int pageCount: Math.max(1, Math.ceil(itemCount / pageSize))
    readonly property int currentPage: Math.floor(currentIndex / pageSize)
    readonly property int currentColumn: (currentIndex % pageSize) % columns
    readonly property int currentRow: Math.floor((currentIndex % pageSize) / columns)

    // Page-stack indicators. Used by the right-gutter scroll cue (and
    // by callers that want to drive their own indicator) to gate the
    // up/down arrows. Both are false on a single-page dataset.
    // These intentionally track loaded `pageCount` — they reflect what
    // the user can actually navigate to right now, not a paginated
    // model's reported total.
    readonly property bool hasPagesAbove: currentPage > 0
    readonly property bool hasPagesBelow: currentPage < pageCount - 1

    // Caller-supplied total item count, used by the scroll thumb so its
    // size and position reflect the full dataset rather than the loaded
    // slice. Default -1 means "fall back to itemCount" — fine for
    // non-paginated models (Systems, Categories, Recents) where the
    // loaded count IS the total. Paginated callers (GamesScreen) bind
    // this to their model's authoritative total so the thumb stays
    // stable while `fetch_more` grows the slice in the background.
    property int totalItemsOverride: -1
    readonly property int totalItems:
        totalItemsOverride >= 0 ? totalItemsOverride : itemCount
    readonly property int totalPageCount:
        Math.max(1, Math.ceil(totalItems / pageSize))

    // Reserved chrome around the cell area. Vertical insets must be
    // large enough to contain the focused tile's 1.06× scale bleed
    // (~3% of cellHeight per side) — without them, top-row and
    // bottom-row tiles get clipped when focused. The scrollbar gutter
    // (`gutterWidth`) is treated as part of the grid for edge-spacing
    // purposes: it sits inboard of `rightInset` (which matches
    // `leftInset` so the cells+gutter block has equal margin on each
    // screen edge) with `gutterGap` of breathing room between the
    // rightmost cell and the gutter. `gutterGap` is intentionally
    // tighter than `cellSpacingX` — the scrollbar reads as chrome,
    // not as another cell, so a full inter-cell gap looks like wasted
    // space next to it. The gutter stays reserved on a single page
    // (just hidden) so cells don't reflow when paging activates.
    readonly property int leftInset: Sizing.pctW(5)
    readonly property int rightInset: Sizing.pctW(5)
    readonly property int gutterWidth: Sizing.pctW(3)
    readonly property int gutterGap: Sizing.pctW(1.5)
    readonly property int topInset: Sizing.pctH(2)
    readonly property int bottomInset: Sizing.pctH(2)
    readonly property int cellSpacingX: Sizing.pctW(3)
    readonly property int cellSpacingY: Sizing.pctH(4)

    // Computed cell dimensions — fill the available area, divided by
    // gridColumns × gridRows. Callers don't override. The cell area
    // also reserves `gutterGap + gutterWidth` on the right for the
    // tight-gap-then-scrollbar layout described above.
    readonly property int _availableWidth:
        Math.max(0,
                 width - leftInset - rightInset - gutterGap - gutterWidth)
    readonly property int _availableHeight:
        Math.max(0, height - topInset - bottomInset)
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

    function currentCellRectIn(target: Item): rect {
        if (root.itemCount <= 0)
            return Qt.rect(0, 0, 0, 0)
        const local = root.currentIndex % root.pageSize
        const row = Math.floor(local / root.columns)
        const col = local % root.columns
        const p = root.mapToItem(
            target,
            root.leftInset + col * (root.cellWidth + root.cellSpacingX),
            root.topInset + row * (root.cellHeight + root.cellSpacingY))
        return Qt.rect(p.x, p.y, root.cellWidth, root.cellHeight)
    }

    // Jump the selection by `delta` whole pages. Wraps in both
    // directions to mirror moveSelection's column-edge behavior:
    // - delta > 0 past the last page wraps to page 0
    // - delta < 0 from page 0 wraps to the last page
    // The target lands on (targetPage, currentRow, currentColumn) when
    // that slot exists; on a partial last page it clamps to the last
    // existing item on that page so the user always moves rather than
    // sticking on a hole. Returns true if the index actually changed.
    // No-op (returns false) on a single-page dataset since wrap on
    // page 0 ↔ page 0 wouldn't move anything.
    function pageBy(delta: int): bool {
        if (root.itemCount <= 0 || root.pageCount <= 1 || delta === 0)
            return false
        const total = root.pageCount
        // JS `%` keeps sign on negatives — normalise into [0, total).
        const targetPage = ((root.currentPage + delta) % total + total) % total
        const targetSlot =
            targetPage * root.pageSize
            + root.currentRow * root.columns
            + root.currentColumn
        const lastIdxOnPage =
            Math.min((targetPage + 1) * root.pageSize, root.itemCount) - 1
        if (lastIdxOnPage < 0)
            return false
        const newIndex = Math.min(targetSlot, lastIdxOnPage)
        if (newIndex === root.currentIndex)
            return false
        root.currentIndex = newIndex
        // Mirror moveSelection's pre-fetch: when we cross into the
        // second-to-last loaded page, kick a fetch so the next page
        // boundary lands on freshly loaded rows.
        if (root.currentPage >= root.pageCount - 2)
            root.loadMoreRequested()
        return true
    }

    // Step the selection by (dCol, dRow). Returns true if the index
    // actually moved. Cardinal moves only — diagonals (dCol and dRow
    // both nonzero) are not produced by any caller and behaviour for
    // them is undefined.
    //
    // Horizontal axis — within-row wrap, never changes page or row:
    // - dCol > 0 at the row's last filled column: wrap to col 0.
    // - dCol < 0 at column 0: wrap to the row's last filled column.
    //   On a partial last row, the "last filled column" is bounded by
    //   the row's actual item count so wraps land on real cells.
    //
    // Vertical axis — page advance/retreat with wrap and partial-page
    // clamp:
    // - dRow > 0 past the last *filled* row on the current page:
    //   advance to (next page, row 0, same col). On the last page, wrap
    //   to (page 0, row 0, same col). On a partial last page this
    //   triggers as soon as Down would step into the empty rows below
    //   the content, not just when stepping off the grid grid-shape.
    // - dRow < 0 above row 0: retreat to (previous page, last row,
    //   same col). On page 0, wrap to (last page, last row, same col).
    // - Landing on a hole on a partial target page (column doesn't
    //   exist there): clamp to the last existing item on the target
    //   page so the user always moves rather than sticking on a hole.
    function moveSelection(dCol: int, dRow: int): bool {
        if (root.itemCount <= 0)
            return false

        let newPage = root.currentPage
        let newRow = root.currentRow
        let newCol = root.currentColumn

        // Horizontal wrap stays on the source row; clamp the wrap target
        // to the row's actual filled span so a partial last row cycles
        // among its own items rather than walking through a hole.
        if (dCol !== 0) {
            const rowFirstIndex =
                root.currentPage * root.pageSize
                + root.currentRow * root.columns
            const rowLastIndex =
                Math.min(root.itemCount - 1,
                         rowFirstIndex + root.columns - 1)
            const maxColOnRow = rowLastIndex - rowFirstIndex
            const colCandidate = root.currentColumn + dCol
            if (colCandidate < 0)
                newCol = maxColOnRow
            else if (colCandidate > maxColOnRow)
                newCol = 0
            else
                newCol = colCandidate
        }

        // Vertical wrap crosses page boundaries; the partial-page hole
        // clamp below covers the case where the target column doesn't
        // exist on the destination page.
        //
        // A Down step that lands in an empty row of a partial last
        // page (rowCandidate fits inside `rows` but is past the page's
        // last filled row) must trigger the same page advance as
        // stepping off the grid — otherwise the hole-clamp at the end
        // of this function lands on the user's current cell and the
        // press appears to do nothing.
        if (dRow !== 0) {
            const rowCandidate = root.currentRow + dRow
            const itemsOnPage = Math.min(
                root.pageSize,
                root.itemCount - root.currentPage * root.pageSize)
            const lastFilledRowOnPage =
                Math.floor((itemsOnPage - 1) / root.columns)
            if (rowCandidate < 0) {
                newPage = root.currentPage === 0
                          ? root.pageCount - 1
                          : root.currentPage - 1
                newRow = root.rows - 1
            } else if (rowCandidate >= root.rows
                       || rowCandidate > lastFilledRowOnPage) {
                newPage = root.currentPage === root.pageCount - 1
                          ? 0
                          : root.currentPage + 1
                newRow = 0
            } else {
                newRow = rowCandidate
            }
        }

        let newIndex = newPage * root.pageSize + newRow * root.columns + newCol
        if (newIndex < 0)
            return false
        if (newIndex >= root.itemCount) {
            // Target slot is a hole on a partial page. Clamp to the
            // page's last existing item.
            const lastIdxOnPage =
                Math.min((newPage + 1) * root.pageSize, root.itemCount) - 1
            if (lastIdxOnPage < 0)
                return false
            newIndex = lastIdxOnPage
        }
        if (newIndex === root.currentIndex) {
            // Selection didn't move because the user is at an edge with
            // no data beyond it on this side. If they're at or past the
            // penultimate loaded page, ask the model to fetch more so a
            // subsequent press can land on freshly-loaded rows.
            if (root.currentPage >= root.pageCount - 2)
                root.loadMoreRequested()
            return false
        }
        root.currentIndex = newIndex
        // Pre-fetch one page early — when the user enters the
        // second-to-last loaded page, kick off the next fetch so the
        // network round-trip overlaps with a full page of cell
        // traversal and the new page lands before they cross the
        // boundary. The model's own debounce (loading_more guard)
        // collapses repeated emissions while a fetch is in flight.
        if (root.currentPage >= root.pageCount - 2)
            root.loadMoreRequested()
        return true
    }

    // Defensive clamp on shrinkage only: if the model shed rows below
    // the saved index, keep us in-bounds. Don't clamp on growth — page
    // appends from cumulative pagination must leave the user's
    // currentIndex untouched.
    property int _previousItemCount: 0

    onItemCountChanged: {
        if (root.itemCount < root._previousItemCount &&
            root.currentIndex >= root.itemCount) {
            root.currentIndex = Math.max(0, root.itemCount - 1)
        }
        root._previousItemCount = root.itemCount
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

                // Cover-load gate. PagedGrid's Repeater materialises every
                // model row at construction, so without a gate every loaded
                // cell would fire its image-provider request immediately
                // and saturate the async pool — visible-page covers then
                // can't finish decoding before the cover gate releases,
                // which produces the per-tile pop-in we tried to fix in
                // v1.
                //
                // Two-tier gate:
                //   - request range (±2 pages): cells inside this radius
                //     fire image-provider requests. Bounds the initial
                //     fanout to a fixed ~50 covers while still
                //     pre-decoding pages N+1 and N+2 so a forward PgDn
                //     lands on already-cached pixmaps.
                //   - retention range (±5 pages): cells already requested
                //     keep their TileLoader coverKey set so Tile's Image
                //     keeps the decoded texture *referenced*. That
                //     prevents QQuickPixmapCache from evicting it when
                //     the user pages on, so a back-nav within the
                //     retention window doesn't pay re-decode. Cells that
                //     are in retention range but were never requested
                //     stay gated to "" — retention doesn't get to trigger
                //     new requests, only to keep already-loaded ones
                //     alive.
                //
                // Off-radius cells (outside both ranges, or in retention
                // range without ever having been requested) set their
                // coverKey to "" so Tile's Image collapses to source: ""
                // and the texture reference drops; Qt may evict.
                //
                // Memory ceiling: ±5 around currentPage = up to 11 pages
                // × pageSize covers ≈ 110 covers ≈ 40 MB decoded — OK on
                // MiSTer's shared 512 MB. The decoders run at nice +10
                // (see media_image_provider.cpp), so a re-decode after
                // crossing past the retention edge is invisible to the
                // renderer.
                readonly property bool _coverInRange:
                    Math.abs(cellPage - root.currentPage) <= 2
                readonly property bool _coverInRetentionRange:
                    Math.abs(cellPage - root.currentPage) <= 5
                property bool _coverEverRequested: false
                Binding on _coverEverRequested {
                    when: cellItem._coverInRange
                    value: true
                    restoreMode: Binding.RestoreNone
                }
                readonly property string _gatedCoverKey:
                    (_coverInRange
                     || (_coverEverRequested && _coverInRetentionRange))
                        ? coverKey : ""

                width: root.cellWidth
                height: root.cellHeight
                x: root.leftInset
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
                    coverKey: cellItem._gatedCoverKey
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton
                    enabled: cellItem.visible

                    onEntered: {
                        if (root.currentIndex !== cellItem.index)
                            root.currentIndex = cellItem.index
                        root.itemHovered(cellItem.index)
                    }

                    onClicked: {
                        if (root.currentIndex !== cellItem.index)
                            root.currentIndex = cellItem.index
                        root.itemClicked(cellItem.index)
                    }
                }
            }
        }
    }

    // ── Right-gutter scroll indicator ────────────────────────────────────
    // Up arrow at the top, down arrow at the bottom, free-floating thumb
    // in between. No painted track — the indicator is just the arrows
    // and the thumb. Hidden when the dataset fits on a single page.
    // Snaps page-by-page; no animation on the thumb (matches the instant
    // page flip and keeps the software renderer's dirty rect off the
    // cell area). Sits after the cell `track` in the visual tree so the
    // indicator paints on top of any focus-scale bleed at the right edge.
    Item {
        id: scrollGutter

        anchors.right: parent.right
        anchors.rightMargin: root.rightInset
        anchors.top: parent.top
        anchors.topMargin: root.topInset
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.bottomInset
        width: root.gutterWidth
        visible: root.totalPageCount > 1

        readonly property int arrowSize:
            Math.min(width, Sizing.pctH(4))

        Image {
            id: upArrow
            source: Resources.iconUrl("ScrollUp")
            width: scrollGutter.arrowSize
            height: scrollGutter.arrowSize
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            fillMode: Image.PreserveAspectFit
            smooth: true
            visible: root.hasPagesAbove
        }

        Image {
            id: downArrow
            source: Resources.iconUrl("ScrollDown")
            width: scrollGutter.arrowSize
            height: scrollGutter.arrowSize
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            fillMode: Image.PreserveAspectFit
            smooth: true
            visible: root.hasPagesBelow
        }

        // Geometry-only Item between the arrows; nothing paints.
        // `scrollThumb` derives its size and position from this region's
        // height and the grid's `totalPageCount` / `currentPage`.
        Item {
            id: scrollRegion
            anchors.top: parent.top
            anchors.topMargin: scrollGutter.arrowSize + Sizing.pctH(1)
            anchors.bottom: parent.bottom
            anchors.bottomMargin: scrollGutter.arrowSize + Sizing.pctH(1)
            anchors.horizontalCenter: parent.horizontalCenter

            // Standard paginated-scrollbar formulas (cf. Qt
            // `ScrollBar.size`/`position`, GTK `Gtk.Scrollbar`, Apple
            // HIG): thumb length = trackLen * (visible / total) with one
            // page visible at a time, position = (page / (total - 1)) *
            // remaining range. Floor on thumb height keeps it visible
            // when `totalPageCount` is large.
            readonly property int _minThumbHeight: Sizing.pctH(4)
            readonly property int _thumbHeight:
                Math.max(_minThumbHeight,
                         Math.round(scrollRegion.height / root.totalPageCount))
            readonly property real _thumbY:
                root.totalPageCount <= 1
                    ? 0
                    : (root.currentPage / (root.totalPageCount - 1))
                      * (scrollRegion.height - _thumbHeight)

            Rectangle {
                id: scrollThumb
                width: Sizing.pctW(1.2)
                height: scrollRegion._thumbHeight
                anchors.horizontalCenter: parent.horizontalCenter
                y: scrollRegion._thumbY
                color: Theme.textPrimary
                radius: width / 2
            }
        }
    }
}
