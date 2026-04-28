// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0

import QtQuick
import QtQuick.Window
import Zaparoo.Theme
import Zaparoo.Screens
import Zaparoo.Browse as Browse

// cxx-qt 0.8 patches `isFinal: true` on singleton properties but the
// qmltypes schema has no `isFinal` slot for Method, so every qinvokable
// call on a Zaparoo.Browse singleton still trips qmllint's "Member can
// be shadowed" check. Until the schema grows method-level finality,
// suppress the compiler category file-wide.
// qmllint disable compiler

// Runtime wrapper around MainLayout. The visual tree lives in
// MainLayout.qml (editable by designers in Qt Design Studio) and the
// individual screens in Zaparoo.Screens; this file is a thin router
// that translates raw Qt key events into actions, dispatches them to
// the active screen (or topmost modal), and persists user-visible
// navigation state across kills.
MainLayout {
    id: root

    width: Screen.width
    height: Screen.height

    readonly property string modalCardWrite: "card_write"
    property string cardWriteOwner: ""
    readonly property bool activeCardWritePending:
        root.cardWriteOwner === "systems" ? Browse.SystemsModel.card_write_pending
        : root.cardWriteOwner === "games" ? Browse.GamesModel.card_write_pending
        : false
    readonly property string activeCardWriteError:
        root.cardWriteOwner === "systems" ? Browse.SystemsModel.card_write_error
        : root.cardWriteOwner === "games" ? Browse.GamesModel.card_write_error
        : ""

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
        // Restore screen synchronously before first paint. The parent
        // process on MiSTer kills the launcher without notice, so we
        // resume exactly where we left off. Selection restore happens
        // asynchronously in the modelReset handlers below as catalog
        // data arrives.
        const savedScreen = Browse.AppState.active_screen
        if (savedScreen === root.screenGames
            || savedScreen === root.screenSystems
            || savedScreen === root.screenHub)
            root.activeScreen = savedScreen
        // If the catalog is already ready, fire the restore here so
        // the cascade (set_category → SystemsModel reset → seed
        // currentIndex → set_system → GamesModel reset) lands before
        // first paint. Otherwise the CategoriesModel.onModelReset
        // Connection below fires it on first delivery.
        if (Browse.CategoriesModel.count > 0)
            root.hubScreen.restoreFromCategoriesReset()
    }

    // Seed carousel indices from persisted state when models deliver new data.
    // A miss (category renamed, ROM deleted) falls back to index 0 and leaves
    // the saved identifier untouched on disk — so the user's intent survives
    // a transient catalog gap. State writes only happen in each screen's
    // handleAction (user navigation); these programmatic seeds are inert.
    //
    // Always cascade into set_category (even on a miss or first-launch empty
    // HubState.category): SystemsModel is the only way to drive the next
    // onModelReset handler, and a games-screen restore depends on that chain
    // firing so GamesModel.set_system runs.
    Connections {
        target: Browse.CategoriesModel
        function onModelReset(): void {
            root.hubScreen.restoreFromCategoriesReset()
        }
    }
    Connections {
        target: Browse.SystemsModel
        // On a games-screen restore, GamesState.system_id is authoritative;
        // fall back to SystemsState.system_id only if it's empty (edge case:
        // user pressed Enter on an empty systems carousel and we flipped the
        // screen without ever committing a system). On a hub or systems
        // restore, SystemsState.system_id is authoritative — don't peek at
        // GamesState, or we'd override the user's position with a stale
        // games target from a prior escape-back-up-the-stack.
        function onModelReset(): void {
            const savedSystem = root.activeScreen === root.screenGames
                ? (Browse.GamesState.system_id !== "" ? Browse.GamesState.system_id : Browse.SystemsState.system_id)
                : Browse.SystemsState.system_id
            const idx = savedSystem === "" ? -1 : Browse.SystemsModel.index_for_system_id(savedSystem)
            // Seed without animating the page-snap — a fresh model is a
            // category switch, not user navigation, so the previous
            // page's slide-out would just be a distracting swoop.
            root.systemsScreen.systemsGrid.setCurrentIndexImmediate(idx >= 0 ? idx : 0)
            if (idx >= 0)
                Browse.GamesModel.set_system(savedSystem)
        }
    }
    Connections {
        target: Browse.GamesModel
        function onModelReset(): void {
            const savedPath = Browse.GamesState.game_path
            const idx = savedPath === "" ? -1 : Browse.GamesModel.index_for_game_path(savedPath)
            root.gamesScreen.gamesGrid.setCurrentIndexImmediate(idx >= 0 ? idx : 0)
        }
    }

    // Cross-screen transitions: each screen signals its intent and this
    // router writes persistence + flips ScreenManager. Keeps the screens
    // themselves ignorant of AppState so they can be reused in test
    // harnesses that don't wire the full persistence layer.
    Connections {
        target: root.hubScreen
        function onRequestSystemsScreen(): void {
            ScreenManager.activeScreen = root.screenSystems
            Browse.AppState.active_screen = root.screenSystems
        }
        function onRequestQuit(): void {
            Qt.quit()
        }
    }
    Connections {
        target: root.systemsScreen
        function onRequestHubScreen(): void {
            ScreenManager.activeScreen = root.screenHub
            Browse.AppState.active_screen = root.screenHub
        }
        function onRequestGamesScreen(): void {
            ScreenManager.activeScreen = root.screenGames
            Browse.AppState.active_screen = root.screenGames
        }
        function onRequestSystemCardWrite(index: int): void {
            root.beginCardWrite("systems")
            Browse.SystemsModel.write_card_at(index)
        }
    }
    Connections {
        target: root.gamesScreen
        function onRequestSystemsScreen(): void {
            ScreenManager.activeScreen = root.screenSystems
            Browse.AppState.active_screen = root.screenSystems
        }
        function onRequestGameCardWrite(index: int): void {
            root.beginCardWrite("games")
            Browse.GamesModel.write_card_at(index)
        }
    }
    onActiveCardWritePendingChanged: root.handleCardWriteStatus()
    onActiveCardWriteErrorChanged: root.handleCardWriteStatus()
    onCancelCardWriteRequested: root.cancelCardWrite()

    function beginCardWrite(owner: string): void {
        if (owner === "systems")
            Browse.SystemsModel.cancel_card_write()
        else if (owner === "games")
            Browse.GamesModel.cancel_card_write()
        root.cardWriteOwner = owner
        root.cardWriteFailed = false
        root.cardWriteModalVisible = true
        cardWriteFailureTimer.stop()
        if (ScreenManager.topModal !== root.modalCardWrite)
            ScreenManager.pushModal(root.modalCardWrite)
    }

    function handleCardWriteStatus(): void {
        if (!root.cardWriteModalVisible || root.cardWriteOwner === "")
            return
        if (root.activeCardWritePending)
            return
        if (root.activeCardWriteError !== "") {
            root.cardWriteFailed = true
            cardWriteFailureTimer.restart()
        } else {
            root.hideCardWriteModal()
        }
    }

    function cancelCardWrite(): void {
        if (root.cardWriteOwner === "systems")
            Browse.SystemsModel.cancel_card_write()
        else if (root.cardWriteOwner === "games")
            Browse.GamesModel.cancel_card_write()
        root.hideCardWriteModal()
    }

    function hideCardWriteModal(): void {
        cardWriteFailureTimer.stop()
        root.cardWriteModalVisible = false
        root.cardWriteFailed = false
        root.cardWriteOwner = ""
        if (ScreenManager.topModal === root.modalCardWrite)
            ScreenManager.popModal()
    }

    // Action router. Called from handleKey (which translates Qt key
    // codes via Browse.Input.action_for_key) and directly from tests.
    // Dispatches to the top modal if any, otherwise the active screen.
    function handleAction(action: string): void {
        if (ScreenManager.hasModal) {
            if (ScreenManager.topModal === root.modalCardWrite
                    && (action === "cancel" || action === "accept")) {
                root.cancelCardWrite()
            }
            // While a modal owns input, swallow everything not handled
            // above rather than leak it to the root screen.
            return
        }
        if (root.activeScreen === root.screenGames) {
            root.gamesScreen.handleAction(action)
        } else if (root.activeScreen === root.screenSystems) {
            root.systemsScreen.handleAction(action)
        } else {
            root.hubScreen.handleAction(action)
        }
    }

    // Thin boundary shim kept for back-compat with tst_navigation.qml.
    // Delegates to handleAction so the state machine has a single entry
    // point regardless of input source.
    function handleKey(key): void {
        const action = Browse.Input.action_for_key(key)
        if (action !== "")
            root.handleAction(action)
    }

    Timer {
        id: cardWriteFailureTimer
        interval: 1500
        repeat: false
        onTriggered: root.hideCardWriteModal()
    }

    Item {
        focus: true
        // Drop auto-repeated key events. A held Escape — or a brief
        // stuck press while the main thread is blocked on a model
        // reset — would otherwise queue a burst of `cancel` actions
        // that walk back through games → systems → hub → quit on
        // a single press. Real intent only.
        Keys.onPressed: event => {
            if (event.isAutoRepeat)
                return
            root.handleKey(event.key)
        }
    }
}
