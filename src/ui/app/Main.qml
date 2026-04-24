// Zaparoo Launcher
// Copyright (c) 2026 The Zaparoo Project Contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0

import QtQuick
import QtQuick.Window
import QtQuick.Controls
import Zaparoo.Ui
import Zaparoo.Theme
import Zaparoo.Browse as Browse

ApplicationWindow {
    id: root

    // Typed local references to singletons — required for property access in tooling.
    // qmllint disable compiler
    readonly property Browse.CategoriesModel categoriesRef: Browse.CategoriesModel
    readonly property Browse.SystemsModel systemsRef: Browse.SystemsModel
    readonly property Browse.GamesModel gamesRef: Browse.GamesModel
    // qmllint enable compiler

    // Screen/focus state constants — use these instead of bare string literals.
    readonly property string screenHub: "hub"
    readonly property string screenGames: "games"
    readonly property string focusCategories: "categories"
    readonly property string focusSystems: "systems"

    property bool fullScreen: false

    width: Screen.width
    height: Screen.height
    visible: true
    visibility: fullScreen ? Window.FullScreen : Window.Windowed
    title: "Zaparoo Launcher"

    onWidthChanged: {
        Sizing.screenWidth = width
        Sizing.screenHeight = height
    }
    onHeightChanged: {
        Sizing.screenHeight = height
        Sizing.screenWidth = width
    }
    Component.onCompleted: {
        Sizing.screenWidth = width
        Sizing.screenHeight = height
    }

    // Screen state.
    property string activeScreen: root.screenHub       // screenHub | screenGames
    property string hubFocus: root.focusCategories     // focusCategories | focusSystems

    // Drives the hub↔games slide transition. 0 = hub centred; width = games centred.
    property real screenOffset: root.activeScreen === root.screenGames ? width : 0

    Behavior on screenOffset {
        NumberAnimation {
            duration: 220
            easing.type: Easing.OutCubic
        }
    }

    // Reset carousel indices when models deliver new data.
    Connections {
        target: root.categoriesRef
        function onModelReset(): void {
            categoriesCarousel.currentIndex = 0
        }
    }
    Connections {
        target: root.systemsRef
        function onModelReset(): void {
            systemsCarousel.currentIndex = 0
        }
    }
    // qmllint disable compiler
    Connections {
        target: root.gamesRef
        function onModelReset(): void {
            gamesCarousel.currentIndex = 0
        }
    }
    // qmllint enable compiler

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

            model: root.categoriesRef
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

            model: root.systemsRef
            delegate: TextTileDelegate {}
            placeholderCover: ""
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: systemsCarousel.y + systemsCarousel.height + Sizing.pctH(1)
            visible: root.hubFocus === root.focusSystems
            // qmllint disable compiler
            text: {
                root.systemsRef.count
                return root.systemsRef.system_name_at(systemsCarousel.currentIndex)
            }
            // qmllint enable compiler
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
            // qmllint disable compiler
            opacity: root.gamesRef.loading ? 0.5 : 1.0
            model: root.activeScreen === root.screenGames ? root.gamesRef : null
            // qmllint enable compiler
            delegate: CoverDelegate {}
            placeholderCover: "qrc:/qt/qml/Zaparoo/App/resources/images/placeholder/cover_generic.png"

            onCurrentIndexChanged: {
                // qmllint disable compiler
                root.gamesRef.set_selected_index(currentIndex)
                // qmllint enable compiler
            }

            Behavior on opacity {
                NumberAnimation {
                    duration: 100
                }
            }
        }

        Text {
            anchors.centerIn: gamesCarousel
            // qmllint disable compiler
            visible: (root.gamesRef.errorMessage ?? "") !== ""
            text: root.gamesRef.errorMessage ?? ""
            // qmllint enable compiler
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
            // qmllint disable compiler
            text: {
                root.gamesRef.count
                return root.gamesRef.name_at(gamesCarousel.currentIndex)
            }
            // qmllint enable compiler
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
            text: {
                if (root.activeScreen === root.screenGames)
                    return "[<>] GAME  [OK] PLAY  [ESC] BACK"
                if (root.hubFocus === root.focusSystems)
                    return "[<>] SYSTEM  [OK] GAMES  [ESC] BACK"
                return "[<>] CATEGORY  [OK] SELECT  [ESC] QUIT"
            }
            font.family: Theme.fontRetro
            font.pixelSize: Sizing.fontSize(2.5)
            color: Theme.textDim
            renderType: Text.NativeRendering
        }
    }

    // ── Keyboard input ────────────────────────────────────────────────────────

    Item {
        focus: true
        Keys.onPressed: event => root.handleKey(event.key)
    }

    // qmllint disable compiler
    function navigateCarousel(carousel, delta) {
        if (carousel.itemCount > 0)
            carousel.currentIndex = (carousel.currentIndex + delta + carousel.itemCount) % carousel.itemCount
    }

    // Navigation key router. Called by the focus Item's Keys.onPressed and
    // directly from tests (offscreen key routing is unreliable). Kept as a
    // pure function of root state + the three carousel ids.
    function handleKey(key) {
        if (root.activeScreen === root.screenGames) {
            if (key === Qt.Key_Left) {
                navigateCarousel(gamesCarousel, -1)
            } else if (key === Qt.Key_Right) {
                navigateCarousel(gamesCarousel, 1)
            } else if (key === Qt.Key_Return || key === Qt.Key_Enter) {
                root.gamesRef.launch_at(gamesCarousel.currentIndex)
            } else if (key === Qt.Key_Escape || key === Qt.Key_Backspace) {
                root.activeScreen = root.screenHub
            }
        } else if (root.hubFocus === root.focusSystems) {
            if (key === Qt.Key_Left) {
                navigateCarousel(systemsCarousel, -1)
            } else if (key === Qt.Key_Right) {
                navigateCarousel(systemsCarousel, 1)
            } else if (key === Qt.Key_Return || key === Qt.Key_Enter) {
                root.gamesRef.set_system(root.systemsRef.system_id_at(systemsCarousel.currentIndex))
                gamesCarousel.currentIndex = 0
                root.activeScreen = root.screenGames
            } else if (key === Qt.Key_Escape || key === Qt.Key_Backspace) {
                root.hubFocus = root.focusCategories
            }
        } else {
            if (key === Qt.Key_Left) {
                navigateCarousel(categoriesCarousel, -1)
            } else if (key === Qt.Key_Right) {
                navigateCarousel(categoriesCarousel, 1)
            } else if (key === Qt.Key_Return || key === Qt.Key_Enter) {
                systemsCarousel.currentIndex = 0
                root.systemsRef.set_category(root.categoriesRef.category_at(categoriesCarousel.currentIndex))
                root.hubFocus = root.focusSystems
            } else if (key === Qt.Key_Escape || key === Qt.Key_Backspace) {
                Qt.quit()
            }
        }
    }
    // qmllint enable compiler
}
