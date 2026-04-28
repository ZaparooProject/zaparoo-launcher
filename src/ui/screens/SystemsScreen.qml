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
            if (systems.systemsGrid.itemCount > 0) {
                const chosen =
                    Browse.SystemsModel.system_id_at(systems.systemsGrid.currentIndex)
                Browse.GamesModel.set_system(chosen)
                Browse.SystemsState.system_id = chosen
                Browse.GamesState.system_id = chosen
            }
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

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: systemsGrid.bottom
        anchors.topMargin: Sizing.pctH(2.5)
        // Reading Browse.SystemsModel.count registers the binding so
        // a model reset re-evaluates the lookup. The bounds check is
        // honest (count is always >= 0, but currentIndex can stale-out
        // across resets) and matches the Rust-side out-of-range
        // fallback in system_name_at.
        text: systemsGrid.currentIndex >= 0
              && systemsGrid.currentIndex < Browse.SystemsModel.count
              ? Browse.SystemsModel.system_name_at(systemsGrid.currentIndex)
              : ""
        font.family: Theme.fontUi
        font.pixelSize: Sizing.fontSize(4)
        font.weight: Font.Medium
        color: Theme.textPrimary
        renderType: Text.NativeRendering
    }
}
