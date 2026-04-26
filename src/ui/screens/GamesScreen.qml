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

// Games screen — covers carousel driven by `Browse.GamesModel`. Owns
// the action dispatch for the games subset; emits `requestHubScreen`
// on Escape so Main.qml can drive the cross-screen transition.
Item {
    id: games

    property alias gamesCarousel: gamesCarousel

    // Set by the compositor (MainLayout) from `ScreenManager.activeScreen`.
    // Gates the games-model binding so the hub screen doesn't pay for
    // delegate instantiation while it's not in view.
    property bool active: false

    // Emitted when the user presses Escape — Main.qml flips the
    // active screen back to the hub.
    signal requestHubScreen()

    function navigateCarousel(carousel, delta): bool {
        if (carousel.itemCount <= 0)
            return false
        carousel.currentIndex =
            (carousel.currentIndex + delta + carousel.itemCount) % carousel.itemCount
        return true
    }

    function handleAction(action: string): void {
        if (action === "left") {
            if (games.navigateCarousel(games.gamesCarousel, -1))
                Browse.GamesState.game_path =
                    Browse.GamesModel.path_at(games.gamesCarousel.currentIndex)
        } else if (action === "right") {
            if (games.navigateCarousel(games.gamesCarousel, 1))
                Browse.GamesState.game_path =
                    Browse.GamesModel.path_at(games.gamesCarousel.currentIndex)
        } else if (action === "accept") {
            if (games.gamesCarousel.itemCount > 0) {
                // Persist before handing control away. Left/Right already
                // writes game_path on every move, but the user may press
                // Accept on the first highlighted game without navigating,
                // leaving game_path stale from a prior system. Writing
                // here makes the commit explicit so a kill during launch
                // resumes on the correct game.
                Browse.GamesState.game_path =
                    Browse.GamesModel.path_at(games.gamesCarousel.currentIndex)
                Browse.GamesModel.launch_at(games.gamesCarousel.currentIndex)
            }
        } else if (action === "cancel") {
            games.requestHubScreen()
        }
    }

    // ── Visual tree ───────────────────────────────────────────────────────────

    Carousel {
        id: gamesCarousel

        anchors.horizontalCenter: parent.horizontalCenter
        y: Sizing.pctH(12)
        width: parent.width
        height: Sizing.pctH(55)
        opacity: Browse.GamesModel.loading ? 0.5 : 1.0
        model: games.active ? Browse.GamesModel : null
        delegate: CoverDelegate {}
        placeholderCover: "qrc:/qt/qml/Zaparoo/App/resources/images/placeholder/cover_generic.png"

        Behavior on opacity {
            NumberAnimation {
                duration: 100
            }
        }
    }

    Text {
        anchors.centerIn: gamesCarousel
        visible: (Browse.GamesModel.error_message ?? "") !== ""
        text: Browse.GamesModel.error_message ?? ""
        font.family: Theme.fontRetro
        font.pixelSize: Sizing.fontSize(3)
        color: Theme.textDim
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHCenter
        width: parent.width * 0.7
        renderType: Text.NativeRendering
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: gamesCarousel.bottom
        anchors.topMargin: Sizing.pctH(1)
        // Reading count registers the binding for model-reset updates.
        text: Browse.GamesModel.count >= 0
              ? Browse.GamesModel.name_at(gamesCarousel.currentIndex)
              : ""
        font.family: Theme.fontRetro
        font.pixelSize: Sizing.fontSize(4)
        color: Theme.textPrimary
        renderType: Text.NativeRendering
    }
}
