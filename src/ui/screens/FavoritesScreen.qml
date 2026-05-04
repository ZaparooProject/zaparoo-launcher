// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0

import QtQuick
import Zaparoo.Theme
import Zaparoo.Ui
import Zaparoo.Browse as Browse

// cxx-qt 0.8 patches `isFinal: true` on singleton properties but the
// qmltypes schema has no `isFinal` slot for Method, so every qinvokable
// call on a Zaparoo.Browse singleton (launch_at, name_at, etc.) still
// trips qmllint's "Member can be shadowed" check. Until the schema
// grows method-level finality, suppress the compiler category file-wide.
// qmllint disable compiler

// Favorites screen — flat paged grid driven by
// `Browse.FavoritesModel`. Pure input dispatcher: emits
// `requestHubScreen()` on Escape and launches the highlighted entry on
// Accept by calling the model's `launch_at` (which fans out to Core's
// `run` endpoint).
//
// Favorites is a flat list — no folder navigation, no card-write flow —
// so this screen is much simpler than `GamesScreen.qml`.
Item {
    id: favorites

    property alias favoritesGrid: favoritesGrid

    // Bound by MainLayout to `root.pendingTransition !== ""`. Favorites is
    // a destination, never a source, so this is currently always false
    // when the screen is visible — kept for parity with the other
    // screens so the convention holds when a future routing change adds
    // a Favorites-as-source path.
    property bool transitioning: false

    // True while either the cross-screen router is mid-flip
    // (`transitioning`) or the in-screen cover gate is holding
    // `FavoritesModel.loading`. The grid + active-label hide on this so
    // the centred `ScreenStateOverlay` paints alone on a cleared band
    // during cold-launch / model-reset, matching `GamesScreen.qml`.
    // Pagination uses a separate `loading_more` flag and is unaffected.
    readonly property bool _gateHide:
        favorites.transitioning || Browse.FavoritesModel.loading

    signal requestHubScreen()
    signal requestContextMenu(int index, var anchorRect)

    // Restore the previously focused entry when the model is Ready.
    // Called by the router after the Hub→Favorites transition lands;
    // also runs whenever the model count changes so tag changes keep
    // the user's previously highlighted row if it's still in the page.
    function restoreSelection(): void {
        if (Browse.FavoritesModel.count <= 0)
            return
        const path = Browse.FavoritesState.selected_path
        if (path === "")
            return
        const idx = Browse.FavoritesModel.index_for_path(path)
        if (idx >= 0 && idx !== favoritesGrid.currentIndex)
            favoritesGrid.currentIndex = idx
    }

    // Persist the focused entry's path on every focus move so a
    // kill-resume puts the highlight back. `path_at` returns "" for
    // out-of-range indices; skip writes on those so PagedGrid's
    // shrinkage clamp (currentIndex → 0 when itemCount drops to 0)
    // doesn't clobber the saved path with the empty fallback.
    function _persistFocus(): void {
        const idx = favoritesGrid.currentIndex
        if (idx < 0)
            return
        const path = Browse.FavoritesModel.path_at(idx)
        if (path === "")
            return
        Browse.FavoritesState.selected_path = path
    }

    function _focusIndex(index: int): void {
        if (index < 0 || index >= favorites.favoritesGrid.itemCount)
            return
        favorites.favoritesGrid.currentIndex = index
        favorites._persistFocus()
    }

    function _state(): string {
        if (Browse.FavoritesModel.loading)
            return "loading"
        if ((Browse.FavoritesModel.error_message ?? "") !== "")
            return "error"
        if (Browse.FavoritesModel.count === 0)
            return "empty"
        return "ready"
    }

    function handleAction(action: string): void {
        if (action === "left") {
            favorites.favoritesGrid.moveSelection(-1, 0)
        } else if (action === "right") {
            favorites.favoritesGrid.moveSelection(1, 0)
        } else if (action === "up") {
            favorites.favoritesGrid.moveSelection(0, -1)
        } else if (action === "down") {
            favorites.favoritesGrid.moveSelection(0, 1)
        } else if (action === "page_prev") {
            if (favorites._state() === "ready")
                favorites.favoritesGrid.pageBy(-1)
        } else if (action === "page_next") {
            if (favorites._state() === "ready")
                favorites.favoritesGrid.pageBy(1)
        } else if (action === "accept") {
            // Loading swallows the press at the screen layer; Empty/Error
            // re-fires the current load by calling `fetch_more` (a stale
            // cursor still triggers the fetch — the model's seq guard
            // discards a result that no longer matches the chain).
            const state = favorites._state()
            if (state === "loading")
                return
            if (state === "error" || state === "empty") {
                Browse.FavoritesModel.fetch_more()
                return
            }
            Browse.FavoritesModel.launch_at(favorites.favoritesGrid.currentIndex)
        } else if (action === "write_card") {
            if (favorites.favoritesGrid.itemCount > 0) {
                const idx = favorites.favoritesGrid.currentIndex
                favorites._persistFocus()
                const rect = favorites.favoritesGrid.currentCellRectIn(favorites)
                favorites.requestContextMenu(idx, rect)
            }
        } else if (action === "cancel") {
            favorites.requestHubScreen()
        }
    }

    // ── Visual tree ───────────────────────────────────────────────────────────

    // Top status strip — page counter, screen title, total entries.
    // The total badge reads `count` directly: favorites is a flat list,
    // so the rendered count tracks the loaded slice rather than a
    // server-side total. Good enough until Core surfaces a total.
    TopStatusStrip {
        id: topStrip
        visible: !favorites._gateHide
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: Sizing.pctH(11)
        height: Sizing.pctH(7)
        title: qsTr("Favorites")
        currentPage: favoritesGrid.currentPage
        totalPages: Math.max(1,
            Math.ceil(Browse.FavoritesModel.count / favoritesGrid.pageSize))
        totalText: Browse.FavoritesModel.count > 0
                   ? qsTr("%1 entries").arg(Browse.FavoritesModel.count)
                   : ""
    }

    PagedGrid {
        id: favoritesGrid

        visible: !favorites._gateHide
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: topStrip.bottom
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Sizing.pctH(15)
        model: Browse.FavoritesModel
        delegate: Tile { showCaption: true }
        // Match games-grid layout (taller cover-art tiles); the systems
        // grid's 5x3 starves vertical space on these covers.
        columnsOverride: Sizing.gamesGridColumns
        rowsOverride: Sizing.gamesGridRows
        onLoadMoreRequested: Browse.FavoritesModel.fetch_more()
        onCurrentIndexChanged: favorites._persistFocus()
        onItemHovered: (index) => favorites._focusIndex(index)
        onItemClicked: (index) => {
            favorites._focusIndex(index)
            favorites.handleAction("accept")
        }
        onItemRightClicked: (index) => {
            favorites._focusIndex(index)
            favorites.handleAction("write_card")
        }
        onEmptyRightClicked: favorites.handleAction("cancel")
        onPageWheelRequested: (delta) => favorites.handleAction(
            delta > 0 ? "page_next" : "page_prev")
    }

    ActiveLabel {
        id: activeLabel
        visible: !favorites._gateHide
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: favoritesGrid.bottom
        height: Sizing.pctH(7)
        text: favoritesGrid.itemCount > 0
              ? Browse.FavoritesModel.name_at(favoritesGrid.currentIndex)
              : ""
    }

    ScreenStateOverlay {
        anchors.centerIn: favoritesGrid
        width: favoritesGrid.width
        height: favoritesGrid.height
        loading: Browse.FavoritesModel.loading
        errorMessage: Browse.FavoritesModel.error_message ?? ""
        count: Browse.FavoritesModel.count
        emptyText: qsTr("No favorites yet")
        loadingText: qsTr("Loading favorites…")
    }
}
