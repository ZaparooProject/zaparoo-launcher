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

    signal requestHubScreen()

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
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: Sizing.pctH(9)
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

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: topStrip.bottom
        anchors.topMargin: Sizing.pctH(2)
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Sizing.pctH(15)
        model: Browse.RecentsModel
        delegate: Tile {}
        // Match games-grid layout (taller cover-art tiles); the systems
        // grid's 5x3 starves vertical space on these covers.
        columnsOverride: Sizing.gamesGridColumns
        rowsOverride: Sizing.gamesGridRows
        onLoadMoreRequested: Browse.RecentsModel.fetch_more()
    }

    ActiveLabel {
        id: activeLabel
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: recentsGrid.bottom
        anchors.topMargin: Sizing.pctH(1)
        height: Sizing.pctH(7)
        text: recentsGrid.itemCount > 0
              ? Browse.RecentsModel.name_at(recentsGrid.currentIndex)
              : ""
    }

    // "Loading more…" cue, parked on the left edge of the active-label
    // band — same placement as GamesScreen so users see the same pattern.
    LoadingIndicator {
        anchors.left: parent.left
        anchors.leftMargin: Sizing.pctW(5)
        anchors.verticalCenter: activeLabel.verticalCenter
        visible: Browse.RecentsModel.loading_more
        z: 1
        text: qsTr("Loading more…")
    }

    ScreenStateOverlay {
        anchors.centerIn: recentsGrid
        width: recentsGrid.width
        height: recentsGrid.height
        loading: Browse.RecentsModel.loading
        errorMessage: Browse.RecentsModel.error_message ?? ""
        count: Browse.RecentsModel.count
        emptyText: qsTr("Nothing played yet")
    }
}
