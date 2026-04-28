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

// Systems screen — paged grid driven by `Browse.SystemsModel`. Owns the
// action dispatch for the systems subset; emits `requestHubScreen` on
// Escape (or Up at the top row) and `requestGamesScreen` on Accept so
// Main.qml can drive the cross-screen transition.
Item {
    id: systems

    property alias systemsGrid: systemsGrid

    // Set by the compositor (MainLayout) from `ScreenManager.activeScreen`.
    // Gates the systems-model binding so the off-screen instance doesn't
    // pay for delegate instantiation while it's not in view.
    property bool active: false

    signal requestHubScreen()
    signal requestGamesScreen()
    signal requestSystemCardWrite(int index)

    // Move selection by (dx, dy) and commit the new system id on
    // success. Returns the moveSelection result so callers can use the
    // false branch to escape (Up at the top row falls through to the
    // hub).
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
            // Up inside the grid moves a row; Up at the top row falls
            // through to the hub. Mirrors the pre-split UX where Up
            // at row 0 escaped the embedded systems section back to
            // categories — preserved here as a peer-screen back-jump
            // so d-pad muscle memory still works.
            if (!systems._performMove(0, -1))
                systems.requestHubScreen()
        } else if (action === "accept") {
            // Accept routing depends on the screen's data state, matching
            // the help bar vocabulary in MainLayout.qml. Loading swallows
            // the press (load is in flight); Error/Empty re-fires the
            // current load (the [OK] RETRY behavior the help bar
            // promises); Ready drills into Games as before. The retry is
            // gated on a non-empty current_category so an Accept on a
            // first-launch screen with no category set doesn't flush the
            // model.
            const state = systems._state()
            if (state === "loading")
                return
            if (state === "error" || state === "empty") {
                const cat = Browse.SystemsModel.current_category
                if (cat !== "")
                    Browse.SystemsModel.set_category(cat)
                return
            }
            const chosen =
                Browse.SystemsModel.system_id_at(systems.systemsGrid.currentIndex)
            Browse.GamesModel.set_system(chosen)
            Browse.SystemsState.system_id = chosen
            Browse.GamesState.system_id = chosen
            systems.requestGamesScreen()
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
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Sizing.pctH(2)
        text: Browse.SystemsModel.current_category
        font.family: Theme.fontUi
        font.pixelSize: Sizing.fontSize(4)
        font.weight: Font.Medium
        color: Theme.textPrimary
        renderType: Text.NativeRendering
    }

    PagedGrid {
        id: systemsGrid

        anchors.horizontalCenter: parent.horizontalCenter
        y: Sizing.pctH(8)
        width: parent.width
        height: Sizing.pctH(72)
        model: systems.active ? Browse.SystemsModel : null
        delegate: Tile {}
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
