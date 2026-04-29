// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0

import QtQuick
import Zaparoo.Theme
import Zaparoo.Ui
import Zaparoo.Browse as Browse

// cxx-qt 0.8 patches `isFinal: true` on singleton properties but the
// qmltypes schema has no `isFinal` slot for Method, so every qinvokable
// call on a Zaparoo.Browse singleton (system_id_at, set_system, etc.)
// still trips qmllint's "Member can be shadowed" check. Until the
// schema grows method-level finality, suppress the compiler category
// file-wide.
// qmllint disable compiler

// Systems screen — paged grid driven by `Browse.SystemsModel`. Pure
// input dispatcher: emits `requestAccept(systemId)` on Accept (with
// "" payload to signal Empty/Error retry intent),
// `requestSystemCardWrite(index)` on the card-write action, and
// `requestHubScreen()` on Escape. Cross-screen orchestration (model
// fills, transition overlay, screen flip) lives in Main.qml;
// `transitioning` is written by the router so the grid hides during
// the loading wait.
Item {
    id: systems

    property alias systemsGrid: systemsGrid
    property bool transitioning: false

    signal requestAccept(systemId: string)
    signal requestHubScreen()
    signal requestSystemCardWrite(int index)

    // Move selection by (dx, dy) and commit the new system id on
    // success. Returns the moveSelection result; row/column moves wrap
    // within the grid (no row-edge escape), so callers don't need to
    // act on the false branch — Esc is the only back path.
    function _performMove(dx: int, dy: int): bool {
        if (systems.systemsGrid.moveSelection(dx, dy)) {
            Browse.SystemsState.system_id =
                Browse.SystemsModel.system_id_at(systems.systemsGrid.currentIndex)
            return true
        }
        return false
    }

    // Mirrors ScreenStateOverlay's `state` ternary so accept routing and
    // the in-screen overlay agree on which state we're in.
    function _state(): string {
        if (Browse.SystemsModel.loading)
            return "loading"
        if ((Browse.SystemsModel.error_message ?? "") !== "")
            return "error"
        if (Browse.SystemsModel.count === 0)
            return "empty"
        return "ready"
    }

    function handleAction(action: string): void {
        if (action === "left") {
            systems._performMove(-1, 0)
        } else if (action === "right") {
            systems._performMove(1, 0)
        } else if (action === "down") {
            systems._performMove(0, 1)
        } else if (action === "up") {
            // Up inside the grid moves a row; at the top row it wraps
            // to the bottom row of the same page. Use Escape to back
            // out to the hub.
            systems._performMove(0, -1)
        } else if (action === "accept") {
            // Accept routing depends on the screen's data state, matching
            // the help bar vocabulary in MainLayout.qml. Loading swallows
            // the press at the screen layer (no signal emitted).
            // Empty/Error emit `requestAccept("")` to signal the router
            // to retry the current load (the [OK] RETRY contract).
            // Ready emits `requestAccept(systemId)` to drill into Games.
            const state = systems._state()
            if (state === "loading")
                return
            if (state === "error" || state === "empty") {
                systems.requestAccept("")
                return
            }
            const chosen =
                Browse.SystemsModel.system_id_at(systems.systemsGrid.currentIndex)
            systems.requestAccept(chosen)
        } else if (action === "write_card") {
            if (systems.systemsGrid.itemCount > 0) {
                Browse.SystemsState.system_id =
                    Browse.SystemsModel.system_id_at(systems.systemsGrid.currentIndex)
                systems.requestSystemCardWrite(systems.systemsGrid.currentIndex)
            }
        } else if (action === "cancel") {
            systems.requestHubScreen()
        }
    }

    // ── Visual tree ───────────────────────────────────────────────────────────

    // Top label — active category. Replaces the pre-Step-8 below-grid
    // focused-system caption; the unified Tile labels each system itself,
    // so the on-screen context the caption was carrying (which category
    // the user drilled into) moves up here.
    //
    // The screen Item fills the whole window, so the label has to clear
    // the MainLayout logo (topMargin pctH(2) + height pctH(7) — bottom
    // edge at pctH(9)) with a pctH(2) gap.
    Text {
        id: topLabel
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Sizing.pctH(11)
        text: Browse.SystemsModel.current_category
        font.family: Theme.fontUi
        font.pixelSize: Sizing.fontSize(4)
        font.weight: Font.Medium
        color: Theme.textPrimary
        renderType: Text.NativeRendering
    }

    // Grid fills the safe zone between the top label and the help bar.
    // bottomMargin = MainLayout's instructionsBar height (pctH(6)) +
    // pctH(2) gap. If you change the help-bar height, update this too.
    PagedGrid {
        id: systemsGrid

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: topLabel.bottom
        anchors.topMargin: Sizing.pctH(2)
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Sizing.pctH(8)
        model: Browse.SystemsModel
        delegate: Tile {}

        // Hide the tiles while the router holds us here on a forward
        // transition (Systems → Games) so the centred "Loading…" cue
        // (painted from Main.qml) reads alone over the cleared grid.
        visible: !systems.transitioning
    }

    ScreenStateOverlay {
        anchors.centerIn: systemsGrid
        width: systemsGrid.width
        height: systemsGrid.height
        loading: Browse.SystemsModel.loading
        errorMessage: Browse.SystemsModel.error_message ?? ""
        count: Browse.SystemsModel.count
        emptyText: qsTr("No systems in this category")
    }
}
