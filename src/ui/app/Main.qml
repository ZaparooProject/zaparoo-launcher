// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
// SPDX-FileCopyrightText: 2026 Callan Barrett

import QtQuick
import QtQuick.Window
import QtQuick.Controls
import Zaparoo.Ui
import Zaparoo.Theme

ApplicationWindow {
    id: root

    width: Screen.width
    height: Screen.height
    visible: true
    visibility: Window.FullScreen
    title: "Zaparoo Launcher"

    // Keep Sizing singleton informed of the current resolution.
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

    // Placeholder game data — will be replaced by a C++ model.
    readonly property list<url> coverImages: [
        "qrc:/qt/qml/Zaparoo/App/resources/images/placeholder/cover1.png",
        "qrc:/qt/qml/Zaparoo/App/resources/images/placeholder/cover2.png",
        "qrc:/qt/qml/Zaparoo/App/resources/images/placeholder/cover3.png",
        "qrc:/qt/qml/Zaparoo/App/resources/images/placeholder/cover4.png",
        "qrc:/qt/qml/Zaparoo/App/resources/images/placeholder/cover5.png",
        "qrc:/qt/qml/Zaparoo/App/resources/images/placeholder/cover6.png"
    ]
    readonly property list<string> gameNames: [
        "Super Mario World",
        "Sonic the Hedgehog",
        "Street Fighter II",
        "The Legend of Zelda",
        "Metroid",
        "Castlevania"
    ]

    property bool inMenu: false
    property int menuIndex: 0
    property bool crtEnabled: false

    // Slow rainbow hue cycle for the retro aesthetic.
    property real rainbowHue

    NumberAnimation on rainbowHue {
        from: 0
        to: 1
        duration: 12000
        loops: Animation.Infinite
    }

    // ── Background ────────────────────────────────────────────────────────────

    Rectangle {
        anchors.fill: parent
        color: Theme.bgDeep
    }

    Starfield {
        anchors.fill: parent
        z: 0
    }

    // ── FPS counter ───────────────────────────────────────────────────────────

    FpsCounter {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: Sizing.pctH(8)
        anchors.rightMargin: Sizing.pctW(8)
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

    // ── Carousel ──────────────────────────────────────────────────────────────

    Carousel {
        id: carousel

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Sizing.pctH(12)
        width: parent.width
        height: Sizing.pctH(55)
        opacity: root.inMenu ? 0.3 : 1.0

        coverImages: root.coverImages
        rainbowHue: root.rainbowHue

        Behavior on opacity {
            NumberAnimation {
                duration: 150
            }
        }
    }

    // ── Game title ────────────────────────────────────────────────────────────

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: carousel.bottom
        anchors.topMargin: Sizing.pctH(1)
        text: root.gameNames[carousel.currentIndex]
        font.family: Theme.fontRetro
        font.pixelSize: Sizing.fontSize(4)
        color: Theme.textPrimary
        opacity: root.inMenu ? 0.3 : 1.0

        Behavior on opacity {
            NumberAnimation {
                duration: 200
            }
        }
    }

    // ── Selection dots ────────────────────────────────────────────────────────

    SelectionDots {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: carousel.bottom
        anchors.topMargin: Sizing.pctH(8)
        count: root.gameNames.length
        currentIndex: carousel.currentIndex
        rainbowHue: root.rainbowHue
        opacity: root.inMenu ? 0.3 : 1.0

        Behavior on opacity {
            NumberAnimation {
                duration: 200
            }
        }
    }

    // ── Separator ─────────────────────────────────────────────────────────────

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: menuBar.top
        anchors.bottomMargin: Sizing.pctH(1)
        width: Sizing.pctW(60)
        height: 1
        color: Theme.borderFaint
    }

    // ── Menu bar ──────────────────────────────────────────────────────────────

    MenuBar {
        id: menuBar

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: instructionsBar.top
        anchors.bottomMargin: Sizing.pctH(1)
        inMenu: root.inMenu
        menuIndex: root.menuIndex
        rainbowHue: root.rainbowHue
        menuItems: ["PLAY", root.crtEnabled ? "CRT:ON" : "CRT:OFF", "EXIT"]
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
            text: root.inMenu ? "[<>] SEL  [OK] GO  [^] BACK" : "[<>] BROWSE  [v] MENU"
            font.family: Theme.fontRetro
            font.pixelSize: Sizing.fontSize(2.5)
            color: Theme.textDim
        }
    }

    // ── CRT overlay ───────────────────────────────────────────────────────────

    CrtOverlay {
        anchors.fill: parent
        visible: root.crtEnabled
        z: 100
    }

    // ── Keyboard input ────────────────────────────────────────────────────────

    Item {
        focus: true

        Keys.onPressed: function (event) {
            if (root.inMenu) {
                if (event.key === Qt.Key_Left) {
                    root.menuIndex = (root.menuIndex - 1 + 3) % 3
                } else if (event.key === Qt.Key_Right) {
                    root.menuIndex = (root.menuIndex + 1) % 3
                } else if (event.key === Qt.Key_Up) {
                    root.inMenu = false
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    if (root.menuIndex === 0) {
                        console.log("Playing:", root.gameNames[carousel.currentIndex])
                    } else if (root.menuIndex === 1) {
                        root.crtEnabled = !root.crtEnabled
                    } else if (root.menuIndex === 2) {
                        Qt.quit()
                    }
                } else if (event.key === Qt.Key_Escape) {
                    root.inMenu = false
                }
            } else {
                if (event.key === Qt.Key_Left) {
                    carousel.currentIndex = (carousel.currentIndex - 1 + carousel.itemCount) % carousel.itemCount
                } else if (event.key === Qt.Key_Right) {
                    carousel.currentIndex = (carousel.currentIndex + 1) % carousel.itemCount
                } else if (event.key === Qt.Key_Down) {
                    root.inMenu = true
                    root.menuIndex = 0
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    console.log("Selected:", root.gameNames[carousel.currentIndex])
                } else if (event.key === Qt.Key_Escape) {
                    Qt.quit()
                }
            }
        }
    }
}
