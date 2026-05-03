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

// Recently Played screen — flat paged grid driven by
// `Browse.RecentsModel`. Pure input dispatcher: emits
// `requestHubScreen()` on Escape and launches the highlighted entry on
// Accept by calling the model's `launch_at` (which fans out to Core's
// `run` endpoint).
//
// History is a flat list — no folder navigation, no card-write flow —
// so this screen is much simpler than `GamesScreen.qml`.
Item {
    id: recents

    property alias recentsGrid: recentsGrid

    // Bound by MainLayout to `root.pendingTransition !== ""`. Recents is
    // a destination, never a source, so this is currently always false
    // when the screen is visible — kept for parity with the other
    // screens so the convention holds when a future routing change adds
    // a Recents-as-source path.
    property bool transitioning: false

    // True while either the cross-screen router is mid-flip
    // (`transitioning`) or the in-screen cover gate is holding
    // `RecentsModel.loading`. The grid + active-label hide on this so
    // the centred `ScreenStateOverlay` paints alone on a cleared band
    // during cold-launch / model-reset, matching `GamesScreen.qml`.
    // Pagination uses a separate `loading_more` flag and is unaffected.
    readonly property bool _gateHide:
        recents.transitioning || Browse.RecentsModel.loading

    signal requestHubScreen()

    // Restore the previously focused entry when the model is Ready.
    // Called by the router after the Hub→Recents transition lands;
    // also runs whenever the model count changes so a freshly-played
    // game (which prepends to history and resets the model) keeps the
    // user's previously highlighted row if it's still in the page.
    function restoreSelection(): void {
        if (Browse.RecentsModel.count <= 0)
            return
        const path = Browse.RecentsState.selected_path
        if (path === "")
            return
        const idx = Browse.RecentsModel.index_for_path(path)
        if (idx >= 0 && idx !== recentsGrid.currentIndex)
            recentsGrid.currentIndex = idx
    }

    // Persist the focused entry's path on every focus move so a
    // kill-resume puts the highlight back. `path_at` returns "" for
    // out-of-range indices; skip writes on those so PagedGrid's
    // shrinkage clamp (currentIndex → 0 when itemCount drops to 0)
    // doesn't clobber the saved path with the empty fallback.
    function _persistFocus(): void {
        const idx = recentsGrid.currentIndex
        if (idx < 0)
            return
        const path = Browse.RecentsModel.path_at(idx)
        if (path === "")
            return
        Browse.RecentsState.selected_path = path
    }

    function _focusIndex(index: int): void {
        if (index < 0 || index >= recents.recentsGrid.itemCount)
            return
        recents.recentsGrid.currentIndex = index
        recents._persistFocus()
    }

    function _state(): string {
        if (Browse.RecentsModel.loading)
            return "loading"
        if ((Browse.RecentsModel.error_message ?? "") !== "")
            return "error"
        if (Browse.RecentsModel.count === 0)
            return "empty"
        return "ready"
    }

    function handleAction(action: string): void {
        if (action === "left") {
            recents.recentsGrid.moveSelection(-1, 0)
        } else if (action === "right") {
            recents.recentsGrid.moveSelection(1, 0)
        } else if (action === "up") {
            recents.recentsGrid.moveSelection(0, -1)
        } else if (action === "down") {
            recents.recentsGrid.moveSelection(0, 1)
        } else if (action === "page_prev") {
            if (recents._state() === "ready")
                recents.recentsGrid.pageBy(-1)
        } else if (action === "page_next") {
            if (recents._state() === "ready")
                recents.recentsGrid.pageBy(1)
        } else if (action === "accept") {
            // Loading swallows the press at the screen layer; Empty/Error
            // re-fires the current load by calling `fetch_more` (a stale
            // cursor still triggers the fetch — the model's seq guard
            // discards a result that no longer matches the chain).
            const state = recents._state()
            if (state === "loading")
                return
            if (state === "error" || state === "empty") {
                Browse.RecentsModel.fetch_more()
                return
            }
            Browse.RecentsModel.launch_at(recents.recentsGrid.currentIndex)
        } else if (action === "cancel") {
            recents.requestHubScreen()
        }
    }

    // ── Visual tree ───────────────────────────────────────────────────────────

    // Top status strip — page counter, screen title, total entries.
    // The total badge reads `count` directly: history is a flat list,
    // so the rendered count tracks the loaded slice rather than a
    // server-side total. Good enough until Core surfaces a total.
    TopStatusStrip {
        id: topStrip
        visible: !recents._gateHide
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: Sizing.pctH(11)
        height: Sizing.pctH(7)
        title: qsTr("Recently Played")
        currentPage: recentsGrid.currentPage
        totalPages: Math.max(1,
            Math.ceil(Browse.RecentsModel.count / recentsGrid.pageSize))
        totalText: Browse.RecentsModel.count > 0
                   ? qsTr("%1 entries").arg(Browse.RecentsModel.count)
                   : ""
    }

    PagedGrid {
        id: recentsGrid

        visible: !recents._gateHide
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: topStrip.bottom
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Sizing.pctH(15)
        model: Browse.RecentsModel
        delegate: Tile { showCaption: true }
        // Match games-grid layout (taller cover-art tiles); the systems
        // grid's 5x3 starves vertical space on these covers.
        columnsOverride: Sizing.gamesGridColumns
        rowsOverride: Sizing.gamesGridRows
        onLoadMoreRequested: Browse.RecentsModel.fetch_more()
        onCurrentIndexChanged: recents._persistFocus()
        onItemHovered: (index) => recents._focusIndex(index)
        onItemClicked: (index) => {
            recents._focusIndex(index)
            recents.handleAction("accept")
        }
    }

    ActiveLabel {
        id: activeLabel
        visible: !recents._gateHide
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: recentsGrid.bottom
        height: Sizing.pctH(7)
        text: recentsGrid.itemCount > 0
              ? Browse.RecentsModel.name_at(recentsGrid.currentIndex)
              : ""
    }

    ScreenStateOverlay {
        anchors.centerIn: recentsGrid
        width: recentsGrid.width
        height: recentsGrid.height
        loading: Browse.RecentsModel.loading
        errorMessage: Browse.RecentsModel.error_message ?? ""
        count: Browse.RecentsModel.count
        emptyText: qsTr("Nothing played yet")
        loadingText: qsTr("Loading recently played…")
    }
}
