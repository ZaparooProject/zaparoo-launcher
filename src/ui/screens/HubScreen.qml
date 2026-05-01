// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
pragma ComponentBehavior: Bound

import QtQuick
import Zaparoo.Theme
import Zaparoo.Ui
import Zaparoo.Browse as Browse

// cxx-qt 0.8 patches `isFinal: true` on singleton properties but the
// qmltypes schema has no `isFinal` slot for Method, so every qinvokable
// call on a Zaparoo.Browse singleton (set_category, index_for_category,
// etc.) still trips qmllint's "Member can be shadowed" check. Until
// the schema grows method-level finality, suppress the compiler
// category file-wide.
// qmllint disable compiler

// Hub screen — two centered rows the user navigates as one grid:
//
//   * Top row: dynamic categories from Browse.CategoriesModel (Arcade,
//     Computer, Console, Handheld). Wraps left/right.
//   * Bottom row: fixed actions — Recently Played and Settings.
//     Clamps left/right (no wrap on a short row).
//
// Cross-row navigation is index-aligned with clamp:
//   Down top[i] → bottom[min(i, count-1)]
//   Up bottom[i] → top[min(i, count-1)]
// so any column past the bottom row's last entry collapses onto that
// last entry, and on the way up the same clamp applies to the
// categories row.
//
// Pure input dispatcher: emits one of `requestAccept(category)`,
// `requestRecentsScreen`, `requestSettingsScreen`, or `requestQuit`.
//
// All cross-screen orchestration (model fills, deferred set_category,
// cover prefetch, transition overlay, screen flip) lives in Main.qml.
// `transitioning` is written by the router so both rows hide during
// the loading wait.
Item {
    id: hub

    property bool transitioning: false
    // 0 = categories row, 1 = actions row. `final` so external
    // consumers (the test harness) don't trip qmllint shadow warnings
    // accessing through MainLayout's untyped alias.
    final property int currentRow: 0
    // Index within the active row.
    final property int currentIndex: 0

    signal requestAccept(category: string)
    signal requestQuit()
    signal requestRecentsScreen()
    signal requestSettingsScreen()

    // Static action-row data. Three fixed entries; order matches
    // left-to-right reading. The `qsTr()` calls live directly in this
    // binding so a `LanguageChange` event re-evaluates `actionEntries`
    // and rebuilds the array with newly-translated strings — consumers
    // bound to `actionEntries[i].text` pick up the new values
    // automatically.
    readonly property var actionEntries: [
        { id: "recents",  coverKey: "icons/History",  text: qsTr("Recently Played") },
        { id: "settings", coverKey: "icons/Settings", text: qsTr("Settings") }
    ]

    function _actionIndexForId(id: string): int {
        for (let i = 0; i < hub.actionEntries.length; i++)
            if (hub.actionEntries[i].id === id)
                return i
        return 0
    }

    // Restore the hub from the persisted `Browse.HubState`. Always
    // cascades into `SystemsModel.set_category` because the cascade
    // drives the next onModelReset handler that a games-screen restore
    // depends on; the call is idempotent when the model already holds
    // the right category.
    //
    // Called from two sites in Main.qml — the Component.onCompleted
    // early-arrival path (catalog already seeded synchronously) and the
    // CategoriesModel.onModelReset listener (later refreshes). On a
    // refresh the category list can reorder, so the row index MUST be
    // re-seeded even when SystemsModel is already on the chosen
    // category — otherwise the visible focus drifts off whichever
    // screen the user is on.
    function restoreFromCategoriesReset(): void {
        const savedCategory = Browse.HubState.category
        const idx = savedCategory === ""
                    ? -1
                    : Browse.CategoriesModel.index_for_category(savedCategory)
        const chosenCategoryIndex = idx >= 0 ? idx : 0
        const chosenCategory = idx >= 0
                               ? savedCategory
                               : Browse.CategoriesModel.category_at(chosenCategoryIndex)

        // Restore which row the user was on, then point currentIndex
        // at the right slot for that row. Saved row outside [0, 1] is
        // treated as 0 — same belt-and-braces stance as the category
        // fallback above.
        const savedRow = Browse.HubState.selected_row
        if (savedRow === 1) {
            hub.currentRow = 1
            hub.currentIndex = hub._actionIndexForId(Browse.HubState.selected_action)
        } else {
            hub.currentRow = 0
            hub.currentIndex = chosenCategoryIndex
        }

        if (Browse.SystemsModel.current_category === chosenCategory
            && Browse.SystemsModel.count > 0)
            return
        Browse.SystemsModel.set_category(chosenCategory)
    }

    // Returns true if the focus actually moved. Empty rows leave disk
    // state alone — see tst_persistence.qml for the regression guarded
    // against. Top row wraps modulo count (3-6 items, far end whips
    // back); bottom row clamps because three items don't need wrap.
    function _navigate(delta: int): bool {
        if (hub.currentRow === 0) {
            const count = Browse.CategoriesModel.count
            if (count <= 0)
                return false
            const next = ((hub.currentIndex + delta) % count + count) % count
            if (next === hub.currentIndex)
                return false
            hub.currentIndex = next
            return true
        }
        const count = hub.actionEntries.length
        const next = Math.max(0, Math.min(count - 1, hub.currentIndex + delta))
        if (next === hub.currentIndex)
            return false
        hub.currentIndex = next
        return true
    }

    // Cross-row jump. Returns true when focus moved (always true for a
    // non-no-op direction; up from top or down from bottom is a no-op).
    function _crossRow(direction: int): bool {
        if (direction > 0 && hub.currentRow === 0) {
            // Down from categories: clamp into actions[0..2].
            hub.currentRow = 1
            hub.currentIndex = Math.min(hub.currentIndex,
                                        hub.actionEntries.length - 1)
            return true
        }
        if (direction < 0 && hub.currentRow === 1) {
            // Up from actions: clamp into categories[0..count-1].
            const count = Browse.CategoriesModel.count
            if (count <= 0)
                return false
            hub.currentRow = 0
            hub.currentIndex = Math.min(hub.currentIndex, count - 1)
            return true
        }
        return false
    }

    // Side-effect of every focus move: persist HubState. We do NOT call
    // SystemsModel.set_category here — that one's reserved for Accept
    // (and the router orchestrates it). Calling it on every left/right
    // press fires two model resets per press, each destroying-and-
    // recreating SystemsScreen's bound delegates on the UI thread —
    // choppy on MiSTer even though SystemsScreen is `visible: false`.
    function _commitCategorySelection(): void {
        Browse.HubState.selected_row = 0
        if (Browse.CategoriesModel.count > 0)
            Browse.HubState.category =
                Browse.CategoriesModel.category_at(hub.currentIndex)
    }

    function _commitActionSelection(): void {
        Browse.HubState.selected_row = 1
        Browse.HubState.selected_action =
            hub.actionEntries[hub.currentIndex].id
    }

    function _commitCurrent(): void {
        if (hub.currentRow === 0)
            hub._commitCategorySelection()
        else
            hub._commitActionSelection()
    }

    function handleAction(action: string): void {
        if (action === "left") {
            if (hub._navigate(-1))
                hub._commitCurrent()
        } else if (action === "right") {
            if (hub._navigate(1))
                hub._commitCurrent()
        } else if (action === "down") {
            if (hub._crossRow(1))
                hub._commitCurrent()
        } else if (action === "up") {
            if (hub._crossRow(-1))
                hub._commitCurrent()
        } else if (action === "accept") {
            if (hub.currentRow === 0) {
                // Empty row sends "" — router treats that as the committed
                // "Enter on empty hub goes to Systems" passthrough.
                const chosen = Browse.CategoriesModel.count <= 0
                    ? ""
                    : Browse.CategoriesModel.category_at(hub.currentIndex)
                hub.requestAccept(chosen)
            } else {
                const id = hub.actionEntries[hub.currentIndex].id
                if (id === "recents")
                    hub.requestRecentsScreen()
                else if (id === "settings")
                    hub.requestSettingsScreen()
            }
        } else if (action === "cancel") {
            hub.requestQuit()
        }
    }

    // ── Visual tree ───────────────────────────────────────────────────────────

    Item {
        id: categoriesRow

        // Cell layout. Tiles are icon-only (no label inside), so the
        // cell is a roughly-square image area. The category name for
        // the focused tile renders below the grid in `activeLabel`,
        // not inside the tile.
        readonly property int spacing: Sizing.pctW(3)
        readonly property int sideInset: Sizing.pctW(5)
        readonly property int maxCellWidth: Sizing.pctH(22)
        readonly property int n: Browse.CategoriesModel.count
        readonly property int rawCellWidth:
            n > 0
                ? Math.floor((width - 2 * sideInset - (n - 1) * spacing) / n)
                : 0
        readonly property int cellWidth: Math.min(maxCellWidth, rawCellWidth)
        // Square cell with a hair of breathing room top and bottom
        // for the focused tile's 1.06× scale bleed.
        readonly property int cellHeight: Sizing.pctH(22) + Sizing.pctH(2)
        readonly property int totalRowWidth:
            n > 0 ? n * cellWidth + (n - 1) * spacing : 0
        readonly property int rowOriginX: (width - totalRowWidth) / 2

        // Symmetric padding contains the focused tile's 1.06× scale
        // bleed inside the row's own bounds.
        readonly property int verticalPadding: Sizing.pctH(2)

        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width
        height: cellHeight + 2 * verticalPadding
        // Sits high enough that the second row + activeLabel stay
        // clear of the help bar at the bottom.
        y: Sizing.pctH(14)

        // Hide the tiles while the router holds us here on a forward
        // transition so the centred "Loading…" cue (painted from
        // Main.qml) reads alone.
        visible: !hub.transitioning

        Component {
            id: tileDelegate
            Tile {}
        }

        Repeater {
            id: itemRepeater

            model: Browse.CategoriesModel

            Item {
                id: cellItem

                required property int index
                required property string name
                required property string coverKey

                x: categoriesRow.rowOriginX
                   + index * (categoriesRow.cellWidth + categoriesRow.spacing)
                y: categoriesRow.verticalPadding
                width: categoriesRow.cellWidth
                height: categoriesRow.cellHeight

                readonly property bool isSelected:
                    hub.currentRow === 0 && index === hub.currentIndex
                // Focused tile draws on top so its 1.06× scale-up isn't
                // clipped by neighbours to the right.
                z: isSelected ? 1 : 0

                TileLoader {
                    anchors.fill: parent
                    sourceComponent: tileDelegate
                    isSelected: cellItem.isSelected
                    isFocused: hub.currentRow === 0
                    name: cellItem.name
                    coverKey: cellItem.coverKey
                }
            }
        }
    }

    // Action row. Same cell geometry and centring formula as
    // categoriesRow so the two rows visually read as one grid; the
    // only difference is a static three-entry array model and clamp-
    // not-wrap navigation. Positioned directly below categoriesRow
    // with a vertical gap equal to categoriesRow.spacing so the
    // visual gutter between rows matches the gutter between tiles
    // within a row.
    Item {
        id: actionsRow

        // Mirror categoriesRow's cell metrics so both rows line up
        // pixel-for-pixel.
        readonly property int spacing: categoriesRow.spacing
        readonly property int cellWidth: categoriesRow.cellWidth
        readonly property int cellHeight: categoriesRow.cellHeight
        readonly property int verticalPadding: categoriesRow.verticalPadding
        readonly property int n: hub.actionEntries.length
        readonly property int totalRowWidth:
            n > 0 ? n * cellWidth + (n - 1) * spacing : 0
        readonly property int rowOriginX: (width - totalRowWidth) / 2

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: categoriesRow.bottom
        // Visual gap between the bottom edge of a category cell and the
        // top edge of an action cell must equal the horizontal `spacing`
        // between tiles within a row. Both rows reserve `verticalPadding`
        // above and below their cells (to contain the focused tile's
        // 1.06× scale bleed); without compensating here the visible gap
        // would be `spacing + 2 × verticalPadding`.
        anchors.topMargin: categoriesRow.spacing - categoriesRow.verticalPadding - actionsRow.verticalPadding
        width: parent.width
        height: cellHeight + 2 * verticalPadding
        visible: !hub.transitioning

        Component {
            id: actionTileDelegate
            Tile {}
        }

        Repeater {
            model: hub.actionEntries

            Item {
                id: actionCellItem

                required property int index
                required property var modelData

                x: actionsRow.rowOriginX
                   + index * (actionsRow.cellWidth + actionsRow.spacing)
                y: actionsRow.verticalPadding
                width: actionsRow.cellWidth
                height: actionsRow.cellHeight

                readonly property bool isSelected:
                    hub.currentRow === 1 && index === hub.currentIndex
                z: isSelected ? 1 : 0

                TileLoader {
                    anchors.fill: parent
                    sourceComponent: actionTileDelegate
                    isSelected: actionCellItem.isSelected
                    isFocused: hub.currentRow === 1
                    name: actionCellItem.modelData.text
                    coverKey: actionCellItem.modelData.coverKey
                }
            }
        }
    }

    // Active label — single big line under the bottom row, swaps text
    // on every move. Reads from whichever row owns focus. Hidden during
    // a forward transition, mirroring the rows.
    ActiveLabel {
        id: activeLabel

        anchors.top: actionsRow.bottom
        anchors.topMargin: Sizing.pctH(3)
        anchors.left: parent.left
        anchors.right: parent.right
        height: Sizing.pctH(7)
        text: {
            if (hub.currentRow === 1)
                return hub.actionEntries[hub.currentIndex].text
            if (Browse.CategoriesModel.count > 0)
                return Browse.CategoriesModel.category_at(hub.currentIndex)
            return ""
        }
        visible: !hub.transitioning
    }

    // CategoriesModel has no `loading` qproperty — the catalog is
    // fetched eagerly via bind_to_endpoint!. The brief cold-launch
    // window where count===0 surfaces as "No categories" is acceptable
    // per the "Loading is brief" locked decision in MVP_PLAN.md.
    ScreenStateOverlay {
        anchors.centerIn: categoriesRow
        width: categoriesRow.width
        height: categoriesRow.height
        loading: false
        errorMessage: Browse.CategoriesModel.error_message ?? ""
        count: Browse.CategoriesModel.count
        emptyText: qsTr("No categories")
    }
}
