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

// Hub screen — categories carousel on top, systems paged grid below once
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

    // Stash the chosen category here when the user drills in. The
    // wrapper's hidden→shown Transition (below) consumes it after the
    // carousel slide+shrink has finished, so the synchronous
    // SystemsModel reset (which rebuilds every Tile delegate and
    // blocks the main thread for ~200 ms) lands AFTER the carousel
    // animation completes and BEFORE the grid fade-in begins. Empty
    // string means "no pending reset" — the wrapper's ScriptAction
    // skips the call so the initial Component.onCompleted restore
    // (driven by Main.qml) isn't double-fired.
    property string _pendingCategory: ""

    // If the user escapes during the wrapper's 250 ms PauseAnimation,
    // the hidden→shown Transition is interrupted before its
    // ScriptAction runs and _pendingCategory keeps its drill-in value.
    // Clear it here so the invariant "non-empty == reset still
    // pending" stays honest.
    onSectionChanged: {
        if (hub.section !== hub.focusSystems)
            hub._pendingCategory = ""
    }

    // Exposed so MainLayout/tests can reach carousel/grid state without
    // reaching through nested item ids.
    property alias categoriesCarousel: categoriesCarousel
    property alias systemsGrid: systemsGrid

    // Emitted when the user presses Enter on a populated systems grid —
    // Main.qml handles the screen flip via ScreenManager and persistence
    // writes. Emitted on empty grids too so the user's intent to switch
    // screens is still honoured.
    signal requestGamesScreen()

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
        } else if (action === "accept" || action === "down") {
            // Both Accept and Down drill into the systems grid. Down
            // matches d-pad / gamepad expectations (the systems grid
            // sits visually below); Accept stays for keyboard users.
            //
            // The systems-model reset is queued onto the wrapper's
            // hidden→shown Transition (see ScriptAction below) so the
            // synchronous Repeater rebuild lands AFTER the carousel
            // slide+shrink has fully completed and BEFORE the grid
            // fade-in begins — not mid-animation, where the ~200 ms
            // main-thread block would otherwise pause the carousel
            // halfway through its size change.
            if (hub.categoriesCarousel.itemCount > 0) {
                const chosen =
                    Browse.CategoriesModel.category_at(hub.categoriesCarousel.currentIndex)
                hub._pendingCategory = chosen
                Browse.HubState.category = chosen
            }
            hub.section = hub.focusSystems
        } else if (action === "cancel") {
            hub.requestQuit()
        }
    }

    function _handleSystems(action: string): void {
        if (action === "left") {
            if (hub.systemsGrid.moveSelection(-1, 0))
                Browse.HubState.system_id =
                    Browse.SystemsModel.system_id_at(hub.systemsGrid.currentIndex)
        } else if (action === "right") {
            if (hub.systemsGrid.moveSelection(1, 0))
                Browse.HubState.system_id =
                    Browse.SystemsModel.system_id_at(hub.systemsGrid.currentIndex)
        } else if (action === "up") {
            // Up inside the grid moves a row; Up on the top row escapes
            // back to the categories carousel. moveSelection refuses an
            // out-of-range row, so we use that as the trigger.
            if (hub.systemsGrid.moveSelection(0, -1)) {
                Browse.HubState.system_id =
                    Browse.SystemsModel.system_id_at(hub.systemsGrid.currentIndex)
            } else {
                hub.section = hub.focusCategories
            }
        } else if (action === "down") {
            if (hub.systemsGrid.moveSelection(0, 1))
                Browse.HubState.system_id =
                    Browse.SystemsModel.system_id_at(hub.systemsGrid.currentIndex)
        } else if (action === "accept") {
            if (hub.systemsGrid.itemCount > 0) {
                const chosen =
                    Browse.SystemsModel.system_id_at(hub.systemsGrid.currentIndex)
                Browse.GamesModel.set_system(chosen)
                Browse.HubState.system_id = chosen
                Browse.GamesState.system_id = chosen
            }
            hub.requestGamesScreen()
        } else if (action === "cancel") {
            hub.section = hub.focusCategories
        }
    }

    // ── Visual tree ───────────────────────────────────────────────────────────

    Carousel {
        id: categoriesCarousel

        // Carousel grows when categories has focus and shrinks when the
        // user drills into the systems grid, so the focused section
        // always feels like the centre of attention. The animated
        // shrink runs alongside the y-slide so the carousel "tucks
        // away" smoothly. Sizes/spacings stay in pctH so 240p MiSTer
        // and 720p+ desktop both scale.
        readonly property int _heightFocused: Sizing.pctH(28)
        readonly property int _heightCompact: Sizing.pctH(20)
        readonly property int _spacingFocused: Sizing.pctH(32)
        readonly property int _spacingCompact: Sizing.pctH(23)

        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width
        height: hub.section === hub.focusSystems
                ? _heightCompact
                : _heightFocused
        y: hub.section === hub.focusSystems ? Sizing.pctH(4) : Sizing.pctH(30)
        coverWidth: hub.section === hub.focusSystems
                    ? _heightCompact
                    : _heightFocused
        coverHeight: hub.section === hub.focusSystems
                     ? _heightCompact
                     : _heightFocused
        coverSpacing: hub.section === hub.focusSystems
                      ? _spacingCompact
                      : _spacingFocused
        focused: hub.section === hub.focusCategories

        model: Browse.CategoriesModel
        delegate: Tile {}

        Behavior on y {
            NumberAnimation {
                duration: 250
                easing.type: Easing.OutQuad
            }
        }
        Behavior on height {
            NumberAnimation {
                duration: 250
                easing.type: Easing.OutQuad
            }
        }
        Behavior on coverWidth {
            NumberAnimation {
                duration: 250
                easing.type: Easing.OutQuad
            }
        }
        Behavior on coverHeight {
            NumberAnimation {
                duration: 250
                easing.type: Easing.OutQuad
            }
        }
        Behavior on coverSpacing {
            NumberAnimation {
                duration: 250
                easing.type: Easing.OutQuad
            }
        }
    }

    // Wrapper that drives a sequenced reveal: when focus enters the
    // systems section, the categories carousel slides up first (its
    // 250 ms y-Behavior above) and only then does the grid fade in,
    // so the freshly-built grid never paints over the moving carousel.
    // Container.opacity multiplies with the inner systemsGrid.opacity
    // (driven by Main.qml on category-switch model resets) so first
    // entry pays the wrapper transition and later category switches
    // pay only the inner reset fade.
    Item {
        id: systemsContainer

        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width
        height: Sizing.pctH(58)
        // Sits just below the compacted carousel (carousel y=4 + h=20 =
        // 24, with a 2-pct gap before the grid). Earlier value of 30
        // pushed the bottom system caption under the instructions bar.
        y: Sizing.pctH(26)
        // Stop painting (and stop capturing reset-driven repaints)
        // when fully hidden. opacity > 0 keeps the grid in the
        // scenegraph for the entire transition window.
        visible: opacity > 0

        states: [
            State {
                name: "shown"
                when: hub.section === hub.focusSystems
                PropertyChanges {
                    systemsContainer.opacity: 1.0
                }
            },
            State {
                name: "hidden"
                when: hub.section !== hub.focusSystems
                PropertyChanges {
                    systemsContainer.opacity: 0.0
                }
            }
        ]
        transitions: [
            Transition {
                from: "hidden"
                to: "shown"
                SequentialAnimation {
                    // Wait for the carousel's 250 ms y-slide and size
                    // shrink to finish. PauseAnimation +
                    // NumberAnimation is software-rendering safe.
                    PauseAnimation {
                        duration: 250
                    }
                    // Reset SystemsModel only after the carousel's
                    // animations have completed. set_category blocks
                    // the main thread for ~200 ms while the systems
                    // Repeater rebuilds every Tile delegate; running
                    // it here means the freeze lands between the
                    // carousel finishing and the grid fading in,
                    // instead of mid-animation. SequentialAnimation
                    // waits for the ScriptAction to return before
                    // advancing to the next step, so the opacity ramp
                    // below only starts once the new tiles are ready.
                    ScriptAction {
                        script: {
                            if (hub._pendingCategory !== "") {
                                Browse.SystemsModel.set_category(hub._pendingCategory)
                                hub._pendingCategory = ""
                            }
                        }
                    }
                    NumberAnimation {
                        property: "opacity"
                        duration: 150
                        easing.type: Easing.OutQuad
                    }
                }
            },
            Transition {
                from: "shown"
                to: "hidden"
                NumberAnimation {
                    property: "opacity"
                    duration: 100
                    easing.type: Easing.OutQuad
                }
            }
        ]

        PagedGrid {
            id: systemsGrid

            anchors.fill: parent
            focused: hub.section === hub.focusSystems

            model: Browse.SystemsModel
            delegate: Tile {}

            // Inner opacity is multiplied with the wrapper opacity
            // above, so the visible value is `wrapper * inner`. Main.qml
            // toggles this 1→0→1 on every SystemsModel reset to mask
            // the Repeater rebuild flash; on the first drill-in the
            // wrapper is also ramping 0→1, and the product stays
            // monotonically increasing.
            Behavior on opacity {
                NumberAnimation {
                    duration: 100
                    easing.type: Easing.OutQuad
                }
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            // Caption sits directly under the grid; the grid reserves
            // its own dot band internally so this lands in clean
            // space. topMargin gives breathing room between the dots
            // and the caption.
            anchors.top: systemsGrid.bottom
            anchors.topMargin: Sizing.pctH(2.5)
            // Reading Browse.SystemsModel.count registers the binding
            // for model resets; the comparison is always true so the
            // result is the system name at the current grid index.
            text: Browse.SystemsModel.count >= 0
                  ? Browse.SystemsModel.system_name_at(systemsGrid.currentIndex)
                  : ""
            font.family: Theme.fontUi
            font.pixelSize: Sizing.fontSize(4)
            font.weight: Font.Medium
            color: Theme.textPrimary
            renderType: Text.NativeRendering
        }
    }
}
