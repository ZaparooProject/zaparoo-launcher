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
// Nearly every statement in this file touches one, so silence the whole
// category here rather than sprinkling block pragmas. Remove after the
// cxx-qt 0.8 upgrade (which fixes the qmltypes emission).
// qmllint disable compiler

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
        // If Core responded before Main.qml finished loading, CategoriesModel
        // has already emitted modelReset and the Connections below missed it.
        // Kick the restore chain manually; the set_category cascade re-fires
        // SystemsModel.modelReset (now wired) which cascades into GamesModel.
        if (Browse.CategoriesModel.count > 0)
            root.restoreFromCategoriesReset()
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

    // Seed carousel indices from persisted state when models deliver new data.
    // A miss (category renamed, ROM deleted) falls back to index 0 and leaves
    // the saved identifier untouched on disk — so the user's intent survives
    // a transient catalog gap. State writes only happen in handleKey (user
    // navigation); these programmatic seeds are inert with respect to state.
    //
    // Always cascade into set_category (even on a miss or first-launch empty
    // HubState.category): SystemsModel is the only way to drive the next
    // onModelReset handler, and a games-screen restore depends on that chain
    // firing so GamesModel.set_system runs.
    function restoreFromCategoriesReset(): void {
        const savedCategory = Browse.HubState.category
        const idx = savedCategory === "" ? -1 : Browse.CategoriesModel.index_for_category(savedCategory)
        const chosenIndex = idx >= 0 ? idx : 0
        const chosenCategory = idx >= 0 ? savedCategory : Browse.CategoriesModel.category_at(chosenIndex)
        categoriesCarousel.currentIndex = chosenIndex
        Browse.SystemsModel.set_category(chosenCategory)
    }

    Connections {
        target: Browse.CategoriesModel
        function onModelReset(): void {
            root.restoreFromCategoriesReset()
        }
    }
    Connections {
        target: Browse.SystemsModel
        // On a games-screen restore, GamesState.system_id is authoritative;
        // fall back to HubState.system_id only if it's empty (edge case: user
        // pressed Enter on an empty systems carousel and we flipped the
        // screen without ever committing a system). On a hub restore,
        // HubState.system_id is authoritative — don't peek at GamesState, or
        // we'd override the user's hub position with a stale games target
        // from a prior escape-back-to-hub.
        function onModelReset(): void {
            const savedSystem = root.activeScreen === root.screenGames
                ? (Browse.GamesState.system_id !== "" ? Browse.GamesState.system_id : Browse.HubState.system_id)
                : Browse.HubState.system_id
            const idx = savedSystem === "" ? -1 : Browse.SystemsModel.index_for_system_id(savedSystem)
            systemsCarousel.currentIndex = idx >= 0 ? idx : 0
            if (idx >= 0)
                Browse.GamesModel.set_system(savedSystem)
        }
    }
    Connections {
        target: Browse.GamesModel
        function onModelReset(): void {
            const savedPath = Browse.GamesState.game_path
            const idx = savedPath === "" ? -1 : Browse.GamesModel.index_for_game_path(savedPath)
            gamesCarousel.currentIndex = idx >= 0 ? idx : 0
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
            text: {
                Browse.SystemsModel.count
                return Browse.SystemsModel.system_name_at(systemsCarousel.currentIndex)
            }
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
            text: {
                Browse.GamesModel.count
                return Browse.GamesModel.name_at(gamesCarousel.currentIndex)
            }
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

    // Returns true if the carousel actually moved. Callers use this to gate
    // persistence writes — navigating an empty carousel must not overwrite
    // saved state with "" (the `_at(-1)` or `_at(0)` fallback on an empty
    // model).
    function navigateCarousel(carousel, delta): bool {
        if (carousel.itemCount <= 0)
            return false
        carousel.currentIndex = (carousel.currentIndex + delta + carousel.itemCount) % carousel.itemCount
        return true
    }

    // Navigation key router. Called by the focus Item's Keys.onPressed and
    // directly from tests (offscreen key routing is unreliable). Every
    // user-initiated selection change writes through to the persisted state
    // singletons *here* — the carousels themselves don't persist on index
    // change, so programmatic seeds during restore leave disk state intact.
    function handleKey(key) {
        if (root.activeScreen === root.screenGames) {
            if (key === Qt.Key_Left) {
                if (navigateCarousel(gamesCarousel, -1))
                    Browse.GamesState.game_path = Browse.GamesModel.path_at(gamesCarousel.currentIndex)
            } else if (key === Qt.Key_Right) {
                if (navigateCarousel(gamesCarousel, 1))
                    Browse.GamesState.game_path = Browse.GamesModel.path_at(gamesCarousel.currentIndex)
            } else if (key === Qt.Key_Return || key === Qt.Key_Enter) {
                if (gamesCarousel.itemCount > 0) {
                    // Persist before handing control away. Left/Right already
                    // writes game_path on every move, but the user may press
                    // Enter on the first highlighted game without navigating,
                    // leaving game_path stale from a prior system. Writing
                    // here makes the commit explicit so a kill during launch
                    // resumes on the correct game.
                    Browse.GamesState.game_path = Browse.GamesModel.path_at(gamesCarousel.currentIndex)
                    Browse.GamesModel.launch_at(gamesCarousel.currentIndex)
                }
            } else if (key === Qt.Key_Escape || key === Qt.Key_Backspace) {
                root.activeScreen = root.screenHub
                Browse.AppState.active_screen = root.screenHub
            }
        } else if (root.hubFocus === root.focusSystems) {
            if (key === Qt.Key_Left) {
                if (navigateCarousel(systemsCarousel, -1))
                    Browse.HubState.system_id = Browse.SystemsModel.system_id_at(systemsCarousel.currentIndex)
            } else if (key === Qt.Key_Right) {
                if (navigateCarousel(systemsCarousel, 1))
                    Browse.HubState.system_id = Browse.SystemsModel.system_id_at(systemsCarousel.currentIndex)
            } else if (key === Qt.Key_Return || key === Qt.Key_Enter) {
                if (systemsCarousel.itemCount > 0) {
                    const chosen = Browse.SystemsModel.system_id_at(systemsCarousel.currentIndex)
                    Browse.GamesModel.set_system(chosen)
                    Browse.HubState.system_id = chosen
                    Browse.GamesState.system_id = chosen
                }
                root.activeScreen = root.screenGames
                Browse.AppState.active_screen = root.screenGames
            } else if (key === Qt.Key_Escape || key === Qt.Key_Backspace) {
                root.hubFocus = root.focusCategories
                Browse.HubState.focus = root.focusCategories
            }
        } else {
            if (key === Qt.Key_Left) {
                if (navigateCarousel(categoriesCarousel, -1))
                    Browse.HubState.category = Browse.CategoriesModel.category_at(categoriesCarousel.currentIndex)
            } else if (key === Qt.Key_Right) {
                if (navigateCarousel(categoriesCarousel, 1))
                    Browse.HubState.category = Browse.CategoriesModel.category_at(categoriesCarousel.currentIndex)
            } else if (key === Qt.Key_Return || key === Qt.Key_Enter) {
                if (categoriesCarousel.itemCount > 0) {
                    const chosen = Browse.CategoriesModel.category_at(categoriesCarousel.currentIndex)
                    Browse.SystemsModel.set_category(chosen)
                    Browse.HubState.category = chosen
                }
                root.hubFocus = root.focusSystems
                Browse.HubState.focus = root.focusSystems
            } else if (key === Qt.Key_Escape || key === Qt.Key_Backspace) {
                Qt.quit()
            }
        }
    }
}
