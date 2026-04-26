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

// Hub screen — categories carousel on top, systems carousel below once
// the user drills in. Owns its own focus state and navigation actions.
// See `handleAction` for the state machine and the Connections blocks
// for the persistence restore cascade.
Item {
    id: hub

    readonly property string focusCategories: "categories"
    readonly property string focusSystems: "systems"
    // Named `section` — not `focus` — because `Item.focus` is a
    // built-in bool. Redeclaring it here would override a FINAL
    // base-class property and fail QML compile.
    property string section: hub.focusCategories

    // Exposed so MainLayout/tests can reach carousel state without
    // reaching through nested item ids.
    property alias categoriesCarousel: categoriesCarousel
    property alias systemsCarousel: systemsCarousel

    // Emitted when the user presses Enter on a populated systems
    // carousel — Main.qml handles the screen flip via ScreenManager
    // and persistence writes. Emitted on empty carousels too so the
    // user's intent to switch screens is still honoured.
    signal requestGamesScreen()
    signal requestSystemCardWrite(int index)

    // Emitted when the user presses Escape from the categories focus.
    // Main.qml decides whether to quit or dismiss a modal.
    signal requestQuit()

    // Restore the hub from the persisted `Browse.HubState.category`
    // (or index 0 if the saved value is missing from the model). Always
    // cascades into `SystemsModel.set_category` so the systems-model
    // reset handler fires and drives the next step of the restore chain.
    function restoreFromCategoriesReset(): void {
        const savedCategory = Browse.HubState.category
        const idx = savedCategory === ""
                    ? -1
                    : Browse.CategoriesModel.index_for_category(savedCategory)
        const chosenIndex = idx >= 0 ? idx : 0
        const chosenCategory = idx >= 0
                               ? savedCategory
                               : Browse.CategoriesModel.category_at(chosenIndex)
        hub.categoriesCarousel.currentIndex = chosenIndex
        Browse.SystemsModel.set_category(chosenCategory)
    }

    // Returns true if the carousel actually moved. Empty carousels leave
    // disk state alone — see tst_persistence.qml for the regression
    // guarded against.
    function navigateCarousel(carousel, delta): bool {
        if (carousel.itemCount <= 0)
            return false
        carousel.currentIndex =
            (carousel.currentIndex + delta + carousel.itemCount) % carousel.itemCount
        return true
    }

    function handleAction(action: string): void {
        if (hub.section === hub.focusSystems) {
            hub._handleSystems(action)
        } else {
            hub._handleCategories(action)
        }
    }

    function _handleCategories(action: string): void {
        if (action === "left") {
            if (hub.navigateCarousel(hub.categoriesCarousel, -1))
                Browse.HubState.category =
                    Browse.CategoriesModel.category_at(hub.categoriesCarousel.currentIndex)
        } else if (action === "right") {
            if (hub.navigateCarousel(hub.categoriesCarousel, 1))
                Browse.HubState.category =
                    Browse.CategoriesModel.category_at(hub.categoriesCarousel.currentIndex)
        } else if (action === "accept") {
            if (hub.categoriesCarousel.itemCount > 0) {
                const chosen =
                    Browse.CategoriesModel.category_at(hub.categoriesCarousel.currentIndex)
                Browse.SystemsModel.set_category(chosen)
                Browse.HubState.category = chosen
            }
            hub.section = hub.focusSystems
        } else if (action === "cancel") {
            hub.requestQuit()
        }
    }

    function _handleSystems(action: string): void {
        if (action === "left") {
            if (hub.navigateCarousel(hub.systemsCarousel, -1))
                Browse.HubState.system_id =
                    Browse.SystemsModel.system_id_at(hub.systemsCarousel.currentIndex)
        } else if (action === "right") {
            if (hub.navigateCarousel(hub.systemsCarousel, 1))
                Browse.HubState.system_id =
                    Browse.SystemsModel.system_id_at(hub.systemsCarousel.currentIndex)
        } else if (action === "accept") {
            if (hub.systemsCarousel.itemCount > 0) {
                const chosen =
                    Browse.SystemsModel.system_id_at(hub.systemsCarousel.currentIndex)
                Browse.GamesModel.set_system(chosen)
                Browse.HubState.system_id = chosen
                Browse.GamesState.system_id = chosen
            }
            hub.requestGamesScreen()
        } else if (action === "write_card") {
            if (hub.systemsCarousel.itemCount > 0) {
                Browse.HubState.system_id =
                    Browse.SystemsModel.system_id_at(hub.systemsCarousel.currentIndex)
                hub.requestSystemCardWrite(hub.systemsCarousel.currentIndex)
            }
        } else if (action === "cancel") {
            hub.section = hub.focusCategories
        }
    }

    // ── Visual tree ───────────────────────────────────────────────────────────

    Carousel {
        id: categoriesCarousel

        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width
        height: Sizing.pctH(20)
        y: hub.section === hub.focusSystems ? Sizing.pctH(12) : Sizing.pctH(35)
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
        visible: hub.section === hub.focusSystems
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
        visible: hub.section === hub.focusSystems
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
