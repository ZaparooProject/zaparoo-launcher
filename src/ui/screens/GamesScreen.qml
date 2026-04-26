// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0

import QtQuick
import Zaparoo.Theme
import Zaparoo.Ui
import Zaparoo.Browse as Browse

// cxx-qt 0.7 doesn't emit FINAL markers in plugin.qmltypes, so qmllint
// flags every call on a Zaparoo.Browse singleton as "can be shadowed".
// Remove after the cxx-qt 0.8 upgrade.
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

    function handleAction(action: string): void {
        if (action === "left") {
            if (games.gamesGrid.moveSelection(-1, 0))
                Browse.GamesState.game_path =
                    Browse.GamesModel.path_at(games.gamesGrid.currentIndex)
        } else if (action === "right") {
            if (games.gamesGrid.moveSelection(1, 0))
                Browse.GamesState.game_path =
                    Browse.GamesModel.path_at(games.gamesGrid.currentIndex)
        } else if (action === "up") {
            if (games.gamesGrid.moveSelection(0, -1))
                Browse.GamesState.game_path =
                    Browse.GamesModel.path_at(games.gamesGrid.currentIndex)
        } else if (action === "down") {
            if (games.gamesGrid.moveSelection(0, 1))
                Browse.GamesState.game_path =
                    Browse.GamesModel.path_at(games.gamesGrid.currentIndex)
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
        // Reading count registers the binding for model-reset updates.
        text: Browse.GamesModel.count >= 0
              ? Browse.GamesModel.name_at(gamesGrid.currentIndex)
              : ""
        font.family: Theme.fontUi
        font.pixelSize: Sizing.fontSize(2.5)
        color: Theme.textPrimary
        renderType: Text.NativeRendering
    }
}
