// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0

import QtQuick
import Zaparoo.Theme
import Zaparoo.Ui
import Zaparoo.Browse as Browse

// cxx-qt 0.8 patches `isFinal: true` on singleton properties but the
// qmltypes schema has no `isFinal` slot for Method, so every qinvokable
// call on a Zaparoo.Browse singleton (set_category, set_system,
// index_for_category, etc.) still trips qmllint's "Member can be
// shadowed" check. Until the schema grows method-level finality,
// suppress the compiler category file-wide.
// qmllint disable compiler

// Hub screen — categories carousel on top, systems paged grid below once
// the user drills in. Owns its own focus state and navigation actions.
// See `handleAction` for the state machine and the Connections blocks
// for the persistence restore cascade.
//
// ── Systems-reveal orchestration ────────────────────────────────────────
//
// Driving the systems grid is the most fragile area in this file. It
// coordinates five animation primitives, three properties, and two
// reset signals to hide a ~200 ms synchronous model rebuild behind a
// single perceived transition. The contract:
//
//   1. Drill-in (focusCategories → focusSystems with a chosen category):
//      `_pendingCategory` is stashed first; `section` flips after.
//      The wrapper Transition sequences:
//          PauseAnimation (Theme.transitionDuration)
//        → ScriptAction    (consume `_pendingCategory`, call
//                           SystemsModel.set_category which triggers
//                           the synchronous model reset)
//        → NumberAnimation (opacity 0→1, 150 ms).
//      The PauseAnimation matches the carousel's y-Behavior so the
//      grid never fades in over a still-travelling carousel.
//
//   2. Escape (focusSystems → focusCategories):
//      `onSectionChanged` clears `_pendingCategory` so a mid-drill-in
//      cancellation can't queue a stale category for the next drill-in.
//      The wrapper Transition runs in reverse (opacity 1→0).
//
//   3. Category-switch refetch (`runSystemsReseedDip`, called on
//      SystemsModel.modelReset from Main.qml's restore cascade):
//      Dips `systemsGrid.opacity` 1→0→1 via the gridFadeIn Timer
//      so the user sees a fade rather than a flash on in-section
//      category changes. Guarded by `systemsContainerOpacity < 1`
//      so it doesn't fire during the wrapper Transition itself.
//
// `Theme.transitionDuration` is the single source of truth for the
// 250 ms coupling between (1)'s PauseAnimation and the carousel's
// y-Behavior. Bumping one without the other reopens the freeze-mid-
// animation bug the wrapper exists to hide.
Item {
    id: hub

    readonly property string focusCategories: "categories"
    readonly property string focusSystems: "systems"
    // Named `section` — not `focus` — because `Item.focus` is a
    // built-in bool. Redeclaring it here would override a FINAL
    // base-class property and fail QML compile.
    property string section: hub.focusCategories

    // Single source of truth for the carousel slide+shrink duration.
    // The wrapper Transition's PauseAnimation must wait for the same
    // interval, otherwise the grid would fade in over a still-moving
    // carousel. `Theme.transitionDuration` carries the canonical value;
    // alias it here so the rest of the file reads `_carouselTransitionMs`
    // (matches the historical name and signals scope).
    readonly property int _carouselTransitionMs: Theme.transitionDuration

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
        if (hub.section !== hub.focusSystems) {
            hub._pendingCategory = ""
            // Arm the cancel-debounce: a second `cancel` arriving
            // within 300 ms of returning to focusCategories shouldn't
            // quit the app. Covers fast double-tap and any
            // post-section-flip key burst that slipped past the
            // autorepeat filter in Main.qml.
            hub._quitGuard = true
            quitGuardTimer.restart()
        }
    }

    // Window where a `cancel` arriving on focusCategories is treated
    // as part of the "leave systems" press rather than an intent to
    // quit. Cleared 300 ms after the section flip — long enough to
    // absorb stragglers, short enough that a deliberate Escape still
    // quits.
    property bool _quitGuard: false

    Timer {
        id: quitGuardTimer
        interval: 300
        onTriggered: hub._quitGuard = false
    }

    // Exposed so MainLayout/tests can reach carousel/grid state without
    // reaching through nested item ids.
    property alias categoriesCarousel: categoriesCarousel
    property alias systemsGrid: systemsGrid
    // Wrapper opacity, surfaced so Main.qml's reset handler can decide
    // whether to run the inner-dip animation. When the wrapper is
    // mid-transition (< 1), it already masks the Repeater rebuild;
    // stacking the inner dip on top would produce a non-monotonic
    // product opacity.
    readonly property real systemsContainerOpacity: systemsContainer.opacity

    // Emitted when the user presses Enter on a populated systems grid —
    // Main.qml handles the screen flip via ScreenManager and persistence
    // writes. Emitted on empty grids too so the user's intent to switch
    // screens is still honoured.
    signal requestGamesScreen()
    signal requestSystemCardWrite(int index)

    // Emitted when the user presses Escape from the categories focus.
    // Main.qml decides whether to quit or dismiss a modal.
    signal requestQuit()

    // Mask the Repeater rebuild flash that follows an in-section
    // category switch by dipping `systemsGrid.opacity` 1→0→1. The 50 ms
    // hold gives the Repeater time to rebuild before the 100 ms opacity
    // Behavior on `systemsGrid` ramps it back up. No-op when the wrapper
    // `systemsContainer` is mid-transition: the wrapper's own 0→1 ramp
    // already hides the rebuild, and stacking the inner dip on top
    // would multiply into a non-monotonic visible opacity. Main.qml
    // calls this from `Browse.SystemsModel.onModelReset`.
    function runSystemsReseedDip(): void {
        if (hub.systemsContainerOpacity < 1)
            return
        systemsGrid.opacity = 0
        gridFadeIn.restart()
    }

    Timer {
        id: gridFadeIn
        interval: 50
        onTriggered: systemsGrid.opacity = 1
    }

    // Restore the hub from the persisted `Browse.HubState.category`
    // (or index 0 if the saved value is missing from the model). Always
    // cascades into `SystemsModel.set_category` so the systems-model
    // reset handler fires and drives the next step of the restore chain.
    //
    // Called from two sites in Main.qml — the Component.onCompleted
    // early-arrival path (catalog already seeded synchronously) and the
    // CategoriesModel.onModelReset listener (later refreshes). On a
    // refresh the category list can reorder, so the carousel index
    // MUST be re-seeded even when SystemsModel is already on the
    // chosen category — otherwise the visible carousel slot drifts
    // off the systems grid below it. Only the expensive set_category
    // call is gated; the QML-side index assignment is cheap and
    // idempotent. The `is_empty` clause mirrors Rust's same-named
    // recovery in SystemsModel::set_category so a stale-but-empty
    // model still gets a retry shot.
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
        if (Browse.SystemsModel.current_category === chosenCategory
            && Browse.SystemsModel.count > 0)
            return
        Browse.SystemsModel.set_category(chosenCategory)
    }

    // Returns true if the carousel actually moved. Empty carousels leave
    // disk state alone — see tst_persistence.qml for the regression
    // guarded against. Past either end the index wraps modulo itemCount
    // so right-at-end whips to 0 and left-at-start whips to itemCount-1;
    // the existing `Behavior on x` in Carousel.qml animates the long
    // sweep so the user sees the focus snap back to the opposite end.
    function _navigateCarousel(carousel, delta): bool {
        if (carousel.itemCount <= 0)
            return false
        const count = carousel.itemCount
        const next = ((carousel.currentIndex + delta) % count + count) % count
        if (next === carousel.currentIndex)
            return false
        carousel.currentIndex = next
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
            if (hub._navigateCarousel(hub.categoriesCarousel, -1))
                Browse.HubState.category =
                    Browse.CategoriesModel.category_at(hub.categoriesCarousel.currentIndex)
        } else if (action === "right") {
            if (hub._navigateCarousel(hub.categoriesCarousel, 1))
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
            if (hub._quitGuard)
                return
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
        } else if (action === "write_card") {
            if (hub.systemsGrid.itemCount > 0) {
                Browse.HubState.system_id =
                    Browse.SystemsModel.system_id_at(hub.systemsGrid.currentIndex)
                hub.requestSystemCardWrite(hub.systemsGrid.currentIndex)
            }
        } else if (action === "cancel") {
            hub.section = hub.focusCategories
        }
    }

    // ── Visual tree ───────────────────────────────────────────────────────────

    Carousel {
        id: categoriesCarousel

        // Cell layout is constant across the activation transition: only
        // y and imagesOpacity animate. The image area is a square equal
        // to coverWidth; the label sits inside the cell below it.
        // _labelHeight and _gap mirror HubCategoryTile's internal
        // constants so the cell box fits its contents exactly and the
        // _yActivated math lands the label row at pctH(12) — clear of
        // the logo (bottom at pctH(9)) and the top-right HUD.
        readonly property int _gap: Sizing.pctH(1)
        readonly property int _labelHeight:
            Sizing.fontSize(2.4) + Sizing.pctH(0.8)
        readonly property int _imageSide: Sizing.pctH(22)
        readonly property int _coverWidth: _imageSide
        readonly property int _coverHeight: _imageSide + _gap + _labelHeight
        readonly property int _coverSpacing: Sizing.pctH(28)
        // Band has a small extra strip beyond the cell so the selected
        // tile's 1.1× scale doesn't get clipped by the band edges.
        readonly property int _bandHeight: _coverHeight + Sizing.pctH(2)
        readonly property int _yFocused: Sizing.pctH(30)
        // Translate the carousel up so the label row (which sits at
        // imageSide + gap below the cell top) lands at pctH(12) —
        // pctH(3) of breathing room below the logo's pctH(9) bottom.
        readonly property int _yActivated:
            Sizing.pctH(12) - _imageSide - _gap

        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width
        height: _bandHeight
        y: hub.section === hub.focusSystems ? _yActivated : _yFocused
        coverWidth: _coverWidth
        coverHeight: _coverHeight
        coverSpacing: _coverSpacing
        imagesOpacity: hub.section === hub.focusSystems ? 0.0 : 1.0
        focused: hub.section === hub.focusCategories

        model: Browse.CategoriesModel
        delegate: HubCategoryTile {}

        Behavior on y {
            NumberAnimation {
                duration: hub._carouselTransitionMs
                easing.type: Easing.OutQuad
            }
        }
        Behavior on imagesOpacity {
            NumberAnimation {
                duration: hub._carouselTransitionMs
                easing.type: Easing.OutQuad
            }
        }
    }

    // Wrapper that drives a sequenced reveal: when focus enters the
    // systems section, the categories carousel slides up first (its
    // 250 ms y-Behavior above) and only then does the grid fade in,
    // so the freshly-built grid never paints over the moving carousel.
    // Container.opacity multiplies with the inner systemsGrid.opacity
    // (driven by `runSystemsReseedDip` on category-switch model resets)
    // so first entry pays the wrapper transition and later category
    // switches pay only the inner reset fade.
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
                    // Wait for the carousel's slide + shrink to finish
                    // before the heavy reset and the fade-in. Pinned to
                    // the same constant as the carousel Behaviors so a
                    // pacing tweak there doesn't desync this pause.
                    // PauseAnimation + NumberAnimation is
                    // software-rendering safe.
                    PauseAnimation {
                        duration: hub._carouselTransitionMs
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
            // above. Main.qml toggles this 1→0→1 *only* on in-section
            // category switches (wrapper opacity already at 1) so the
            // visible product is monotonic. During a drill-in the
            // wrapper opacity 0→1 ramp masks the rebuild and the inner
            // dip is suppressed — see Main.qml SystemsModel.onModelReset.
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
            // so a model reset re-evaluates the lookup. The bounds
            // check is honest (count is always >= 0, but currentIndex
            // can stale-out across resets) and matches the Rust-side
            // out-of-range fallback in system_name_at.
            text: systemsGrid.currentIndex >= 0
                  && systemsGrid.currentIndex < Browse.SystemsModel.count
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
