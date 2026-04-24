// Zaparoo Launcher
// Copyright (c) 2026 The Zaparoo Project Contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0

import QtQuick
import QtQuick.Window
import QtQuick.Controls
import Zaparoo.Ui
import Zaparoo.Theme
import Zaparoo.Browse as Browse

// cxx-qt 0.7 doesn't emit FINAL markers in plugin.qmltypes, so qmllint
// flags every call on a Zaparoo.Browse singleton as "can be shadowed".
// Nearly every binding in this form touches one, so silence the whole
// category here. Remove after the cxx-qt 0.8 upgrade (which fixes the
// qmltypes emission).
// qmllint disable compiler

// Visual tree. Edit this file in Qt Design Studio; the state machine
// and side-effects live in Main.qml which extends this layout. Keep
// this file declarative — property bindings and child objects only,
// no imperative JS or signal-handler bodies, so the designer sees
// everything in the 2D view.
ApplicationWindow {
    id: root

    // Screen/focus state constants — referenced by bindings below and
    // by Main.qml. Declared here so the layout's own bindings resolve
    // without depending on the wrapper.
    readonly property string screenHub: "hub"
    readonly property string screenGames: "games"
    readonly property string focusCategories: "categories"
    readonly property string focusSystems: "systems"

    // Runtime state the wrapper mutates; the layout binds against them.
    property bool fullScreen: false
    property string activeScreen: root.screenHub
    property string hubFocus: root.focusCategories

    // Drives the hub↔games slide transition. 0 = hub centred; width = games centred.
    property real screenOffset: root.activeScreen === root.screenGames ? root.width : 0

    // Defaults keep the design canvas at a sensible aspect for Design
    // Studio. Main.qml overrides these at runtime with Screen.width /
    // Screen.height, so the live launcher still fills the screen.
    width: 1280
    height: 720
    visible: true
    visibility: root.fullScreen ? Window.FullScreen : Window.Windowed
    title: "Zaparoo Launcher"

    // Aliases so the Main.qml wrapper can drive the carousels (ids
    // declared inside this file aren't visible from the extending file).
    property alias categoriesCarousel: categoriesCarousel
    property alias systemsCarousel: systemsCarousel
    property alias gamesCarousel: gamesCarousel

    Behavior on screenOffset {
        NumberAnimation {
            duration: 220
            easing.type: Easing.OutCubic
        }
    }

    // ── Background ────────────────────────────────────────────────────────────

    Rectangle {
        anchors.fill: parent
        color: Theme.bgDeep
    }

    // ── Logo ──────────────────────────────────────────────────────────────────

    Image {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.leftMargin: Sizing.pctW(2)
        anchors.topMargin: Sizing.pctH(2)
        height: Sizing.pctH(7)
        fillMode: Image.PreserveAspectFit
        source: "qrc:/qt/qml/Zaparoo/App/resources/images/logo.png"
    }

    // ── Hub screen ────────────────────────────────────────────────────────────

    Item {
        id: hubContainer
        x: -root.screenOffset
        width: parent.width
        height: parent.height

        Carousel {
            id: categoriesCarousel

            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            height: Sizing.pctH(20)
            y: root.hubFocus === root.focusSystems ? Sizing.pctH(12) : Sizing.pctH(35)
            coverWidth: Sizing.pctH(20)
            coverHeight: Sizing.pctH(20)
            coverSpacing: Sizing.pctH(23)

            model: Browse.CategoriesModel
            delegate: TextTileDelegate {}
            placeholderCover: ""

            Behavior on y {
                NumberAnimation {
                    duration: 250
                    easing.type: Easing.OutQuad
                }
            }
        }

        Carousel {
            id: systemsCarousel

            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            height: Sizing.pctH(20)
            y: Sizing.pctH(36)
            visible: root.hubFocus === root.focusSystems
            coverWidth: Sizing.pctH(20)
            coverHeight: Sizing.pctH(20)
            coverSpacing: Sizing.pctH(23)

            model: Browse.SystemsModel
            delegate: TextTileDelegate {}
            placeholderCover: ""
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: systemsCarousel.y + systemsCarousel.height + Sizing.pctH(1)
            visible: root.hubFocus === root.focusSystems
            // Reading Browse.SystemsModel.count registers the binding for
            // model resets; the comparison is always true so the result
            // is the system name at the current carousel index.
            text: Browse.SystemsModel.count >= 0
                  ? Browse.SystemsModel.system_name_at(systemsCarousel.currentIndex)
                  : ""
            font.family: Theme.fontRetro
            font.pixelSize: Sizing.fontSize(4)
            color: Theme.textPrimary
            renderType: Text.NativeRendering
        }
    }

    // ── Games screen ──────────────────────────────────────────────────────────

    Item {
        id: gamesContainer
        x: parent.width - root.screenOffset
        width: parent.width
        height: parent.height

        Carousel {
            id: gamesCarousel

            anchors.horizontalCenter: parent.horizontalCenter
            y: Sizing.pctH(12)
            width: parent.width
            height: Sizing.pctH(55)
            opacity: Browse.GamesModel.loading ? 0.5 : 1.0
            model: root.activeScreen === root.screenGames ? Browse.GamesModel : null
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
            // See _selectedSystemName note above — reading count here
            // registers the binding for model-reset updates.
            text: Browse.GamesModel.count >= 0
                  ? Browse.GamesModel.name_at(gamesCarousel.currentIndex)
                  : ""
            font.family: Theme.fontRetro
            font.pixelSize: Sizing.fontSize(4)
            color: Theme.textPrimary
            renderType: Text.NativeRendering
        }
    }

    // ── FPS counter ───────────────────────────────────────────────────────────

    FpsCounter {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: Sizing.pctH(1)
        anchors.rightMargin: Sizing.pctW(1)
        z: 200
    }

    // ── Instructions bar ──────────────────────────────────────────────────────

    Rectangle {
        id: instructionsBar

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Sizing.pctH(6)
        color: Theme.bgBar
        border.width: 1
        border.color: Theme.borderSubtle

        Text {
            anchors.centerIn: parent
            text: root.activeScreen === root.screenGames
                  ? "[<>] GAME  [OK] PLAY  [ESC] BACK"
                  : (root.hubFocus === root.focusSystems
                     ? "[<>] SYSTEM  [OK] GAMES  [ESC] BACK"
                     : "[<>] CATEGORY  [OK] SELECT  [ESC] QUIT")
            font.family: Theme.fontRetro
            font.pixelSize: Sizing.fontSize(2.5)
            color: Theme.textDim
            renderType: Text.NativeRendering
        }
    }
}
