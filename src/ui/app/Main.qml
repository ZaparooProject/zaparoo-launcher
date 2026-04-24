// Zaparoo Launcher
// Copyright (c) 2026 The Zaparoo Project Contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0

import QtQuick
import QtQuick.Window
import Zaparoo.Theme
import Zaparoo.Browse as Browse

// cxx-qt 0.7 doesn't emit FINAL markers in plugin.qmltypes, so qmllint
// flags every call on a Zaparoo.Browse singleton as "can be shadowed".
// Remove after the cxx-qt 0.8 upgrade.
// qmllint disable compiler

// Runtime wrapper around MainLayout. The visual tree lives in
// MainLayout.qml (editable by designers in Qt Design Studio); this
// file carries the state machine, key input, and persistence.
MainLayout {
    id: root

    width: Screen.width
    height: Screen.height

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
        root.categoriesCarousel.currentIndex = chosenIndex
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
            root.systemsCarousel.currentIndex = idx >= 0 ? idx : 0
            if (idx >= 0)
                Browse.GamesModel.set_system(savedSystem)
        }
    }
    Connections {
        target: Browse.GamesModel
        function onModelReset(): void {
            const savedPath = Browse.GamesState.game_path
            const idx = savedPath === "" ? -1 : Browse.GamesModel.index_for_game_path(savedPath)
            root.gamesCarousel.currentIndex = idx >= 0 ? idx : 0
        }
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
                if (navigateCarousel(root.gamesCarousel, -1))
                    Browse.GamesState.game_path = Browse.GamesModel.path_at(root.gamesCarousel.currentIndex)
            } else if (key === Qt.Key_Right) {
                if (navigateCarousel(root.gamesCarousel, 1))
                    Browse.GamesState.game_path = Browse.GamesModel.path_at(root.gamesCarousel.currentIndex)
            } else if (key === Qt.Key_Return || key === Qt.Key_Enter) {
                if (root.gamesCarousel.itemCount > 0) {
                    // Persist before handing control away. Left/Right already
                    // writes game_path on every move, but the user may press
                    // Enter on the first highlighted game without navigating,
                    // leaving game_path stale from a prior system. Writing
                    // here makes the commit explicit so a kill during launch
                    // resumes on the correct game.
                    Browse.GamesState.game_path = Browse.GamesModel.path_at(root.gamesCarousel.currentIndex)
                    Browse.GamesModel.launch_at(root.gamesCarousel.currentIndex)
                }
            } else if (key === Qt.Key_Escape || key === Qt.Key_Backspace) {
                root.activeScreen = root.screenHub
                Browse.AppState.active_screen = root.screenHub
            }
        } else if (root.hubFocus === root.focusSystems) {
            if (key === Qt.Key_Left) {
                if (navigateCarousel(root.systemsCarousel, -1))
                    Browse.HubState.system_id = Browse.SystemsModel.system_id_at(root.systemsCarousel.currentIndex)
            } else if (key === Qt.Key_Right) {
                if (navigateCarousel(root.systemsCarousel, 1))
                    Browse.HubState.system_id = Browse.SystemsModel.system_id_at(root.systemsCarousel.currentIndex)
            } else if (key === Qt.Key_Return || key === Qt.Key_Enter) {
                if (root.systemsCarousel.itemCount > 0) {
                    const chosen = Browse.SystemsModel.system_id_at(root.systemsCarousel.currentIndex)
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
                if (navigateCarousel(root.categoriesCarousel, -1))
                    Browse.HubState.category = Browse.CategoriesModel.category_at(root.categoriesCarousel.currentIndex)
            } else if (key === Qt.Key_Right) {
                if (navigateCarousel(root.categoriesCarousel, 1))
                    Browse.HubState.category = Browse.CategoriesModel.category_at(root.categoriesCarousel.currentIndex)
            } else if (key === Qt.Key_Return || key === Qt.Key_Enter) {
                if (root.categoriesCarousel.itemCount > 0) {
                    const chosen = Browse.CategoriesModel.category_at(root.categoriesCarousel.currentIndex)
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

    Item {
        focus: true
        Keys.onPressed: event => root.handleKey(event.key)
    }
}
