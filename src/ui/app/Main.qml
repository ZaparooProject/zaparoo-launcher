// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
// SPDX-FileCopyrightText: 2026 Callan Barrett

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

    // Slow rainbow hue cycle for the retro aesthetic.
    property real rainbowHue

    NumberAnimation on rainbowHue {
        from: 0
        to: 1
        duration: 12000
        loops: Animation.Infinite
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

    // ── FPS counter ───────────────────────────────────────────────────────────

    FpsCounter {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: Sizing.pctH(1)
        anchors.rightMargin: Sizing.pctW(1)
        z: 200
    }

    // ── Title ─────────────────────────────────────────────────────────────────

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Sizing.pctH(3)
        text: "ZAPAROO"
        font.family: Theme.fontRetro
        font.pixelSize: Sizing.fontSize(5)
        color: Qt.hsla(root.rainbowHue, 0.9, 0.65, 1)
    }

    // ── Categories carousel ───────────────────────────────────────────────────

    Carousel {
        id: categoriesCarousel

        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width
        height: Sizing.pctH(30)
        y: root.hubFocus === root.focusSystems ? Sizing.pctH(5) : Sizing.pctH(28)
        opacity: root.activeScreen === root.screenHub ? 1 : 0

        model: root.categoriesRef
        delegate: TextTileDelegate {}
        placeholderCover: ""
        rainbowHue: root.rainbowHue

        Behavior on y {
            NumberAnimation {
                duration: 250
                easing.type: Easing.OutQuad
            }
        }
        Behavior on opacity {
            NumberAnimation {
                duration: 250
                easing.type: Easing.OutQuad
            }
        }
    }

    // ── Systems carousel ──────────────────────────────────────────────────────

    Carousel {
        id: systemsCarousel

        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width
        height: Sizing.pctH(30)
        y: root.hubFocus === root.focusSystems ? Sizing.pctH(40) : Sizing.pctH(62)
        opacity: root.activeScreen === root.screenHub && root.hubFocus === root.focusSystems ? 1 : 0

        model: root.systemsRef
        delegate: TextTileDelegate {}
        placeholderCover: ""
        rainbowHue: root.rainbowHue

        Behavior on y {
            NumberAnimation {
                duration: 250
                easing.type: Easing.OutQuad
            }
        }
        Behavior on opacity {
            NumberAnimation {
                duration: 250
                easing.type: Easing.OutQuad
            }
        }
    }

    // ── Games carousel ────────────────────────────────────────────────────────

    Carousel {
        id: gamesCarousel

        anchors.horizontalCenter: parent.horizontalCenter
        y: Sizing.pctH(12)
        width: parent.width
        height: Sizing.pctH(55)
        // qmllint disable compiler
        opacity: root.activeScreen === root.screenGames ? (root.gamesRef.loading ? 0.5 : 1.0) : 0

        model: root.gamesRef
        // qmllint enable compiler
        delegate: CoverDelegate {}
        placeholderCover: "qrc:/qt/qml/Zaparoo/App/resources/images/placeholder/cover_generic.png"
        rainbowHue: root.rainbowHue

        onCurrentIndexChanged: {
            // qmllint disable compiler
            root.gamesRef.setSelectedIndex(currentIndex)
            // qmllint enable compiler
        }

        Behavior on opacity {
            NumberAnimation {
                duration: 200
                easing.type: Easing.OutQuad
            }
        }
    }

    // ── Games error message ───────────────────────────────────────────────────

    Text {
        anchors.centerIn: gamesCarousel
        // qmllint disable compiler
        opacity: root.activeScreen === root.screenGames && root.gamesRef.errorMessage !== "" ? 1 : 0
        text: root.gamesRef.errorMessage
        // qmllint enable compiler
        font.family: Theme.fontRetro
        font.pixelSize: Sizing.fontSize(3)
        color: Theme.textDim
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHCenter
        width: parent.width * 0.7
    }

    // ── Context title text ────────────────────────────────────────────────────

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: gamesCarousel.bottom
        anchors.topMargin: Sizing.pctH(1)
        opacity: root.activeScreen === root.screenGames ? 1 : 0
        // qmllint disable compiler
        text: {
            root.gamesRef.count // read count so this binding re-evaluates on model reset
            return root.gamesRef.nameAt(gamesCarousel.currentIndex)
        }
        // qmllint enable compiler
        font.family: Theme.fontRetro
        font.pixelSize: Sizing.fontSize(4)
        color: Theme.textPrimary

        Behavior on opacity {
            NumberAnimation {
                duration: 200
            }
        }
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        y: systemsCarousel.y + systemsCarousel.height + Sizing.pctH(1)
        opacity: root.activeScreen === root.screenHub && root.hubFocus === root.focusSystems ? 1 : 0
        // qmllint disable compiler
        text: {
            root.systemsRef.count // read count so this binding re-evaluates on model reset
            return root.systemsRef.systemNameAt(systemsCarousel.currentIndex)
        }
        // qmllint enable compiler
        font.family: Theme.fontRetro
        font.pixelSize: Sizing.fontSize(4)
        color: Theme.textPrimary

        Behavior on opacity {
            NumberAnimation {
                duration: 200
            }
        }
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
        }
    }

    // ── Keyboard input ────────────────────────────────────────────────────────

    Item {
        focus: true

        // qmllint disable compiler
        function navigateCarousel(carousel, delta) {
            if (carousel.itemCount > 0)
                carousel.currentIndex = (carousel.currentIndex + delta + carousel.itemCount) % carousel.itemCount
        }

        Keys.onPressed: function (event) {
            if (root.activeScreen === root.screenGames) {
                if (event.key === Qt.Key_Left) {
                    navigateCarousel(gamesCarousel, -1)
                } else if (event.key === Qt.Key_Right) {
                    navigateCarousel(gamesCarousel, 1)
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    root.gamesRef.launchAt(gamesCarousel.currentIndex)
                } else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Backspace) {
                    root.activeScreen = root.screenHub
                }
            } else if (root.hubFocus === root.focusSystems) {
                if (event.key === Qt.Key_Left) {
                    navigateCarousel(systemsCarousel, -1)
                } else if (event.key === Qt.Key_Right) {
                    navigateCarousel(systemsCarousel, 1)
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    root.gamesRef.setSystem(root.systemsRef.systemIdAt(systemsCarousel.currentIndex))
                    gamesCarousel.currentIndex = 0
                    root.activeScreen = root.screenGames
                } else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Backspace) {
                    root.hubFocus = root.focusCategories
                }
            } else {
                if (event.key === Qt.Key_Left) {
                    navigateCarousel(categoriesCarousel, -1)
                } else if (event.key === Qt.Key_Right) {
                    navigateCarousel(categoriesCarousel, 1)
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    systemsCarousel.currentIndex = 0
                    root.systemsRef.setCategory(root.categoriesRef.categoryAt(categoriesCarousel.currentIndex))
                    root.hubFocus = root.focusSystems
                } else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Backspace) {
                    Qt.quit()
                }
            }
        }
        // qmllint enable compiler
    }
}
