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
        // Restore screen/focus synchronously before first paint. The parent
        // process on MiSTer kills the launcher without notice, so we resume
        // exactly where we left off. Selection restore happens asynchronously
        // in the modelReset handlers below as catalog data arrives.
        const savedScreen = Browse.AppState.active_screen
        if (savedScreen === root.screenGames || savedScreen === root.screenHub)
            root.activeScreen = savedScreen
        const savedFocus = Browse.HubState.focus
        if (savedFocus === root.focusCategories || savedFocus === root.focusSystems)
            root.hubFocus = savedFocus
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

    // Reset carousel indices when models deliver new data, then restore the
    // last-saved identifier if it's still present. A miss (system removed, ROM
    // deleted) silently falls back to index 0. Each handler also cascades to
    // the next model so the full hub→systems→games chain restores in order.
    //
    // Each handler body sits inside a qmllint `disable compiler` block.
    // cxx-qt 0.7 can't mark #[qinvokable] methods final in plugin.qmltypes,
    // so every call below trips "can be shadowed" even though these
    // singletons are non-subclassable. Drop the pragmas after the cxx-qt
    // 0.8 upgrade, which adds proper qmllint/qmlls support.
    Connections {
        target: Browse.CategoriesModel
        // qmllint disable compiler
        function onModelReset(): void {
            const savedCategory = Browse.HubState.category
            const idx = savedCategory === "" ? -1 : Browse.CategoriesModel.index_for_category(savedCategory)
            categoriesCarousel.currentIndex = idx >= 0 ? idx : 0
            if (savedCategory !== "")
                Browse.SystemsModel.set_category(savedCategory)
        }
        // qmllint enable compiler
    }
    Connections {
        target: Browse.SystemsModel
        // qmllint disable compiler
        // On a games-screen restore, the saved system lives in GamesState —
        // the hub's own system_id may be stale or unset. Fall back to
        // HubState otherwise (resume into hub, or first launch).
        function onModelReset(): void {
            const savedSystem = root.activeScreen === root.screenGames
                ? Browse.GamesState.system_id
                : Browse.HubState.system_id
            const idx = savedSystem === "" ? -1 : Browse.SystemsModel.index_for_system_id(savedSystem)
            systemsCarousel.currentIndex = idx >= 0 ? idx : 0
            if (idx >= 0)
                Browse.GamesModel.set_system(savedSystem)
        }
        // qmllint enable compiler
    }
    Connections {
        target: Browse.GamesModel
        // qmllint disable compiler
        function onModelReset(): void {
            const savedPath = Browse.GamesState.game_path
            const idx = savedPath === "" ? -1 : Browse.GamesModel.index_for_game_path(savedPath)
            gamesCarousel.currentIndex = idx >= 0 ? idx : 0
        }
        // qmllint enable compiler
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

            // qmllint disable compiler
            onCurrentIndexChanged: {
                Browse.HubState.category = Browse.CategoriesModel.category_at(currentIndex)
            }
            // qmllint enable compiler

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

            // qmllint disable compiler
            onCurrentIndexChanged: {
                Browse.HubState.system_id = Browse.SystemsModel.system_id_at(currentIndex)
            }
            // qmllint enable compiler
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: systemsCarousel.y + systemsCarousel.height + Sizing.pctH(1)
            visible: root.hubFocus === root.focusSystems
            // qmllint disable compiler
            text: {
                Browse.SystemsModel.count
                return Browse.SystemsModel.system_name_at(systemsCarousel.currentIndex)
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
            opacity: Browse.GamesModel.loading ? 0.5 : 1.0
            model: root.activeScreen === root.screenGames ? Browse.GamesModel : null
            // qmllint enable compiler
            delegate: CoverDelegate {}
            placeholderCover: "qrc:/qt/qml/Zaparoo/App/resources/images/placeholder/cover_generic.png"

            // qmllint disable compiler
            onCurrentIndexChanged: {
                Browse.GamesModel.set_selected_index(currentIndex)
                Browse.GamesState.game_path = Browse.GamesModel.path_at(currentIndex)
            }
            // qmllint enable compiler

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
            // qmllint disable compiler
            text: {
                Browse.GamesModel.count
                return Browse.GamesModel.name_at(gamesCarousel.currentIndex)
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
                Browse.GamesModel.launch_at(gamesCarousel.currentIndex)
            } else if (key === Qt.Key_Escape || key === Qt.Key_Backspace) {
                root.activeScreen = root.screenHub
                Browse.AppState.active_screen = root.screenHub
            }
        } else if (root.hubFocus === root.focusSystems) {
            if (key === Qt.Key_Left) {
                navigateCarousel(systemsCarousel, -1)
            } else if (key === Qt.Key_Right) {
                navigateCarousel(systemsCarousel, 1)
            } else if (key === Qt.Key_Return || key === Qt.Key_Enter) {
                const chosen = Browse.SystemsModel.system_id_at(systemsCarousel.currentIndex)
                Browse.GamesModel.set_system(chosen)
                Browse.GamesState.system_id = chosen
                gamesCarousel.currentIndex = 0
                root.activeScreen = root.screenGames
                Browse.AppState.active_screen = root.screenGames
            } else if (key === Qt.Key_Escape || key === Qt.Key_Backspace) {
                root.hubFocus = root.focusCategories
                Browse.HubState.focus = root.focusCategories
            }
        } else {
            if (key === Qt.Key_Left) {
                navigateCarousel(categoriesCarousel, -1)
            } else if (key === Qt.Key_Right) {
                navigateCarousel(categoriesCarousel, 1)
            } else if (key === Qt.Key_Return || key === Qt.Key_Enter) {
                systemsCarousel.currentIndex = 0
                Browse.SystemsModel.set_category(Browse.CategoriesModel.category_at(categoriesCarousel.currentIndex))
                root.hubFocus = root.focusSystems
                Browse.HubState.focus = root.focusSystems
            } else if (key === Qt.Key_Escape || key === Qt.Key_Backspace) {
                Qt.quit()
            }
        }
    }
    // qmllint enable compiler
}
