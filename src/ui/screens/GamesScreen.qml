// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0

import QtQuick
import Zaparoo.Theme
import Zaparoo.Ui
import Zaparoo.Browse as Browse

// cxx-qt 0.8 patches `isFinal: true` on singleton properties but the
// qmltypes schema has no `isFinal` slot for Method, so every qinvokable
// call on a Zaparoo.Browse singleton (path_at, set_system, etc.) still
// trips qmllint's "Member can be shadowed" check. Until the schema grows
// method-level finality, suppress the compiler category file-wide.
// qmllint disable compiler

// Games screen — paged grid driven by `Browse.GamesModel`. Owns the
// action dispatch for the games subset; emits `requestHubScreen` on
// Escape so Main.qml can drive the cross-screen transition.
Item {
    id: games

    property alias gamesGrid: gamesGrid

    // Set by the compositor (MainLayout) from `ScreenManager.activeScreen`.
    // Gates the games-model binding so the hub screen doesn't pay for
    // delegate instantiation while it's not in view.
    property bool active: false

    // Emitted when the user presses Escape — Main.qml flips the
    // active screen back to the hub.
    signal requestHubScreen()
    signal requestGameCardWrite(int index)

    // Move selection by (dx, dy) and commit the new game path on
    // success. Unlike HubScreen's _handleSystems, none of the games-grid
    // directions have a row-edge escape branch, so all four cardinal
    // actions share this exact body.
    function _performMove(dx: int, dy: int): void {
        if (games.gamesGrid.moveSelection(dx, dy))
            Browse.GamesState.game_path =
                Browse.GamesModel.path_at(games.gamesGrid.currentIndex)
    }

    function handleAction(action: string): void {
        if (action === "left") {
            games._performMove(-1, 0)
        } else if (action === "right") {
            games._performMove(1, 0)
        } else if (action === "up") {
            games._performMove(0, -1)
        } else if (action === "down") {
            games._performMove(0, 1)
        } else if (action === "accept") {
            if (games.gamesGrid.itemCount > 0) {
                // Persist before handing control away. Directional moves
                // already write game_path on every step, but the user may
                // press Accept on the first highlighted game without
                // navigating, leaving game_path stale from a prior system.
                // Writing here makes the commit explicit so a kill during
                // launch resumes on the correct game.
                Browse.GamesState.game_path =
                    Browse.GamesModel.path_at(games.gamesGrid.currentIndex)
                Browse.GamesModel.launch_at(games.gamesGrid.currentIndex)
            }
        } else if (action === "write_card") {
            if (games.gamesGrid.itemCount > 0) {
                Browse.GamesState.game_path =
                    Browse.GamesModel.path_at(games.gamesGrid.currentIndex)
                games.requestGameCardWrite(games.gamesGrid.currentIndex)
            }
        } else if (action === "cancel") {
            games.requestHubScreen()
        }
    }

    // ── Visual tree ───────────────────────────────────────────────────────────

    PagedGrid {
        id: gamesGrid

        anchors.horizontalCenter: parent.horizontalCenter
        y: Sizing.pctH(8)
        width: parent.width
        height: Sizing.pctH(72)
        opacity: Browse.GamesModel.loading ? 0.5 : 1.0
        model: games.active ? Browse.GamesModel : null
        delegate: Tile {}

        Behavior on opacity {
            NumberAnimation {
                duration: 100
            }
        }
    }

    Text {
        anchors.centerIn: gamesGrid
        visible: (Browse.GamesModel.error_message ?? "") !== ""
        text: Browse.GamesModel.error_message ?? ""
        font.family: Theme.fontUi
        font.pixelSize: Sizing.fontSize(3)
        color: Theme.textDim
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHCenter
        width: parent.width * 0.7
        renderType: Text.NativeRendering
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        // Caption sits directly under the grid (the grid reserves its
        // own dot band internally so this lands in clean space).
        anchors.top: gamesGrid.bottom
        anchors.topMargin: Sizing.pctH(1)
        // Reading count registers the binding for model-reset updates;
        // the bounds check guards against a stale currentIndex during
        // the reset window.
        text: gamesGrid.currentIndex >= 0
              && gamesGrid.currentIndex < Browse.GamesModel.count
              ? Browse.GamesModel.name_at(gamesGrid.currentIndex)
              : ""
        font.family: Theme.fontUi
        font.pixelSize: Sizing.fontSize(2.5)
        color: Theme.textPrimary
        renderType: Text.NativeRendering
    }
}
