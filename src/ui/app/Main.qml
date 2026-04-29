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

    // Seed row/grid indices from persisted state when models deliver new
    // data. A miss (category renamed, ROM deleted) falls back to index 0
    // and leaves the saved identifier untouched on disk — so the user's
    // intent survives a transient catalog gap. State writes only happen
    // in each screen's handleAction (user navigation); these programmatic
    // seeds are inert.
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
        // user pressed Enter on an empty systems grid and we flipped the
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
            if (idx >= 0) {
                Browse.GamesModel.set_system(savedSystem)
            } else if (root.activeScreen === root.screenGames
                       && Browse.SystemsModel.count > 0) {
                // Games-screen restore where the saved id is missing
                // (renamed system, ROM deleted): drive GamesModel from
                // the visible row 0 fallback so the user sees real
                // games for whichever system the grid landed on, not a
                // stale list from a prior session. Persisted
                // GamesState.system_id is left untouched so the user's
                // intent survives a transient catalog gap.
                Browse.GamesModel.set_system(Browse.SystemsModel.system_id_at(0))
            }
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
    //
    // The runtime + persistence writes always go together — naming the
    // pair as a single helper makes the invariant explicit and keeps
    // the four request handlers below a single line each.
    function _goto(screen: string): void {
        ScreenManager.activeScreen = screen
        Browse.AppState.active_screen = screen
    }

    // True when Hub drilled straight into Games via the MiSTer
    // Arcade-bypass shortcut, so cancel-from-Games returns directly
    // to Hub rather than the Systems screen the user never saw. Set
    // by `_navigateFromHub` on the Arcade branch, cleared by
    // `_navigateFromSystems` (normal drill-down) and by the games'
    // onRequestSystemsScreen handler after routing.
    property bool _gamesEnteredFromHub: false

    // Single-shot callback slots fired by the loadingChanged
    // listeners below. Only one transition is in flight at a time
    // (input gate guarantees this), so two scalars are enough.
    // `pendingTransition` itself lives in MainLayout — the source
    // screen's content-hiding bindings (row/grid `visible`) resolve
    // there, so the property has to be declared at that level for
    // qmllint to be happy.
    property var _categoryReadyCallback: null
    property var _systemReadyCallback: null

    // Listen for SystemsModel fills owned by an in-flight transition.
    // `loading` flips true at the start of set_category and false when
    // the async tokio worker posts the filled rows back. Listening to
    // the false edge gives us a single, unambiguous "fill complete"
    // signal — onModelReset would also fire on the synchronous clear
    // (count=0) at the start of set_category, indistinguishable from a
    // category that legitimately fills with 0 rows. The callback slot
    // is consumed at most once per transition; a stray fire when no
    // transition is pending is a no-op.
    Connections {
        target: Browse.SystemsModel
        function onLoadingChanged(): void {
            if (Browse.SystemsModel.loading)
                return
            const cb = root._categoryReadyCallback
            if (cb === null)
                return
            root._categoryReadyCallback = null
            cb()
        }
    }
    Connections {
        target: Browse.GamesModel
        function onLoadingChanged(): void {
            if (Browse.GamesModel.loading)
                return
            const cb = root._systemReadyCallback
            if (cb === null)
                return
            root._systemReadyCallback = null
            cb()
        }
    }

    // Ensure SystemsModel is filled with `category`, then call cb().
    // Synchronous on the no-op return path (same category already
    // populated — a re-Accept after Esc-back); the set_category call
    // is still made for parity with the prior behaviour even though
    // Rust early-returns when the category already matches. Async
    // path waits for loadingChanged; the 50 ms defer hides
    // set_category's synchronous teardown of SystemsScreen's bound
    // tile delegates behind the transition overlay, so the user sees
    // overlay → frozen-under-overlay → grid instead of freeze →
    // flash → grid. Qt.callLater is not enough; it fires inside the
    // same event loop iteration before the next render polish/sync
    // pass.
    function _ensureCategory(category: string, cb): void {
        if (Browse.SystemsModel.current_category === category
            && Browse.SystemsModel.count > 0) {
            Browse.SystemsModel.set_category(category)
            cb()
            return
        }
        root._categoryReadyCallback = cb
        deferredCategorySetTimer.targetCategory = category
        deferredCategorySetTimer.restart()
    }

    // Ensure GamesModel is filled with `systemId`, then call cb().
    // Set_system early-returns when the system is already current
    // and populated (re-Accept after Esc-back); no signal fires, so
    // we flip synchronously on the no-op path.
    function _ensureSystem(systemId: string, cb): void {
        if (Browse.GamesModel.current_system_id === systemId
            && Browse.GamesModel.count > 0) {
            Browse.GamesModel.set_system(systemId)
            cb()
            return
        }
        root._systemReadyCallback = cb
        Browse.GamesModel.set_system(systemId)
    }

    // Hub Accept routing. Empty-row passthrough preserves the committed
    // "Enter on empty hub goes to Systems" behaviour and
    // keeps the navigation test synchronous. Otherwise: tentatively
    // pin the destination to Systems, fill the chosen category, then
    // either bypass to Games (MiSTer Arcade singleton) or fall
    // through to Systems with a cover-prefetch warmup so the
    // destination paints with logos already in QPixmapCache.
    function _navigateFromHub(category: string): void {
        if (category === "") {
            root._goto(root.screenSystems)
            return
        }
        Browse.HubState.category = category
        root.pendingTransition = "systems"
        root._ensureCategory(category, function() {
            const arcadeBypass =
                Browse.Runtime.is_mister
                && category === "Arcade"
                && Browse.SystemsModel.count === 1
            if (arcadeBypass) {
                const systemId = Browse.SystemsModel.system_id_at(0)
                Browse.SystemsState.system_id = systemId
                Browse.GamesState.system_id = systemId
                root.pendingTransition = "games"
                root._ensureSystem(systemId, function() {
                    root._gamesEnteredFromHub = true
                    root._completeTransition(root.screenGames)
                })
            } else {
                root._prefetchSystemCovers(function() {
                    root._completeTransition(root.screenSystems)
                })
            }
        })
    }

    // Systems Accept routing. Pin destination to Games, fill the
    // chosen system, then flip. Sets _gamesEnteredFromHub=false so
    // the back path lands on Systems (the normal drill).
    function _navigateFromSystems(systemId: string): void {
        Browse.SystemsState.system_id = systemId
        Browse.GamesState.system_id = systemId
        root.pendingTransition = "games"
        root._ensureSystem(systemId, function() {
            root._gamesEnteredFromHub = false
            root._completeTransition(root.screenGames)
        })
    }

    // Clear the pending flag, then flip. Order matters: clearing
    // first lets the destination screen paint without the overlay
    // still drawing over it, and lets bindings dependent on
    // pendingTransition (source screen visibility) settle to the
    // post-transition state in the same frame as the screen swap.
    function _completeTransition(screen: string): void {
        root.pendingTransition = ""
        root._goto(screen)
    }

    Connections {
        target: root.hubScreen
        function onRequestAccept(category: string): void {
            root._navigateFromHub(category)
        }
        function onRequestQuit(): void { Qt.quit() }
    }
    Connections {
        target: root.systemsScreen
        function onRequestAccept(systemId: string): void {
            // Empty payload is the [OK] RETRY contract from the help
            // bar — Empty/Error states re-fire the current load
            // rather than drilling. Loading swallows the press at the
            // screen layer (no signal emitted), so this branch only
            // sees user intent on a non-Ready state.
            if (systemId === "") {
                const cat = Browse.SystemsModel.current_category
                if (cat !== "")
                    Browse.SystemsModel.set_category(cat)
                return
            }
            root._navigateFromSystems(systemId)
        }
        function onRequestHubScreen(): void { root._goto(root.screenHub) }
        function onRequestSystemCardWrite(index: int): void {
            root.beginCardWrite("systems")
            Browse.SystemsModel.write_card_at(index)
        }
    }
    Connections {
        target: root.gamesScreen
        function onRequestSystemsScreen(): void {
            if (root._gamesEnteredFromHub) {
                root._gamesEnteredFromHub = false
                root._goto(root.screenHub)
            } else {
                root._goto(root.screenSystems)
            }
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
        // Input gate. While a forward transition is in flight, swallow
        // every press so a user mashing buttons during the loading
        // wait can't queue a second transition or kick a half-cancel
        // through cancel handlers — the in-flight model call has to
        // settle on its own. Modal handling below still has to run
        // first so an Accept/Esc on a card-write modal isn't
        // accidentally swallowed if a transition is pending behind
        // it (the modal owns input regardless).
        if (root.pendingTransition !== "" && !ScreenManager.hasModal)
            return
        if (ScreenManager.hasModal) {
            // Single-consumer dispatch. When a second modal lands
            // (action_error variant for game launch / settings reset
            // / etc.), generalise into a per-modal handler table
            // rather than chaining ifs.
            // Only "cancel" aborts an in-flight card write. Treating
            // "accept" the same way would let a fat-fingered OK during
            // pending kill the write the user actually wanted; on
            // success/error the modal auto-dismisses via
            // handleCardWriteStatus, so accept has nothing to do here.
            if (ScreenManager.topModal === root.modalCardWrite
                    && action === "cancel") {
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

    // Forward-transition cue. Item, not Rectangle — the source
    // screen's existing background and circuit-trace texture stay
    // visible underneath; never paint a full-screen fill. The
    // source screen's primary content is hidden by `transitioning`
    // bindings so the centred "Loading…" reads alone in the cleared
    // band. Sized to the full window so anchors.centerIn parks
    // the text in the geometric centre regardless of which screen
    // is the source.
    Item {
        anchors.fill: parent
        visible: root.pendingTransition !== ""
        z: 100

        Text {
            anchors.centerIn: parent
            text: qsTr("Loading…")
            font.family: Theme.fontUi
            font.pixelSize: Sizing.fontSize(3)
            color: Theme.textDim
            renderType: Text.NativeRendering
        }
    }

    // Hidden cover-decode loop driven by `_prefetchSystemCovers`.
    // While `active`, mounts an Image per SystemsModel row using
    // the same `source` / `sourceSize.width` / `cache` /
    // `asynchronous` settings as Tile.qml's cover Image so the
    // prefetch and the visible Tile share a QPixmapCache slot.
    // As each Image hits Ready or Error, the delegate calls back
    // into `_onCoverDecoded`, which fires the doneCallback and
    // unwinds once every cover is counted. Without this warmup
    // the destination SystemsScreen paints with each Tile showing
    // its procedural text fallback for tens of ms while the PNG
    // decodes — the visible "text → logo pop-in" the deferred
    // flip alone can't fix.
    //
    // Bounded by `systemsCoverPrefetchTimeout` so a missing PNG
    // (silent decode failure that doesn't emit Image.Error) or a
    // genuinely stuck async load never strands the user on the
    // loading overlay.
    Item {
        id: systemsCoverPrefetcher
        visible: false
        property bool active: false
        property var doneCallback: null
        property int total: 0
        property int done: 0

        function _markDone(): void {
            systemsCoverPrefetcher.done++
            if (systemsCoverPrefetcher.done >= systemsCoverPrefetcher.total) {
                systemsCoverPrefetcher.active = false
                systemsCoverPrefetchTimeout.stop()
                const cb = systemsCoverPrefetcher.doneCallback
                systemsCoverPrefetcher.doneCallback = null
                if (cb !== null)
                    cb()
            }
        }

        Repeater {
            model: systemsCoverPrefetcher.active ? Browse.SystemsModel : null
            delegate: Image {
                required property string coverKey
                source: coverKey === "" ? "" : Resources.coverUrl(coverKey)
                sourceSize.width: 256
                asynchronous: true
                cache: true

                // Each delegate contributes exactly once.
                // Component.onCompleted catches a synchronous Ready
                // (cache hit during construction); onStatusChanged
                // catches the normal async path. `_counted` dedupes
                // so a delegate whose status flips Null → Ready
                // inside construction (and again as the binding
                // settles) tallies once.
                property bool _counted: false
                function _markDone(): void {
                    if (_counted)
                        return
                    _counted = true
                    systemsCoverPrefetcher._markDone()
                }

                Component.onCompleted: {
                    if (status === Image.Ready
                        || status === Image.Error
                        || coverKey === "")
                        _markDone()
                }
                onStatusChanged: {
                    if (status === Image.Ready || status === Image.Error)
                        _markDone()
                }
            }
        }
    }

    function _prefetchSystemCovers(cb): void {
        systemsCoverPrefetcher.total = Browse.SystemsModel.count
        systemsCoverPrefetcher.done = 0
        if (systemsCoverPrefetcher.total === 0) {
            cb()
            return
        }
        systemsCoverPrefetcher.doneCallback = cb
        systemsCoverPrefetcher.active = true
        systemsCoverPrefetchTimeout.restart()
    }

    Timer {
        id: systemsCoverPrefetchTimeout
        interval: 1500
        repeat: false
        onTriggered: {
            systemsCoverPrefetcher.active = false
            const cb = systemsCoverPrefetcher.doneCallback
            systemsCoverPrefetcher.doneCallback = null
            if (cb !== null)
                cb()
        }
    }

    // Deferred set_category trigger. Lets the transition overlay
    // paint a frame before set_category's synchronous teardown of
    // SystemsScreen's tile delegates freezes the GUI thread. The
    // 50 ms interval covers a single frame even at MiSTer's ~20 fps
    // software renderer; Qt.callLater / interval 0 fire inside the
    // same event loop iteration before the next render.
    Timer {
        id: deferredCategorySetTimer
        interval: 50
        repeat: false
        property string targetCategory: ""
        onTriggered: Browse.SystemsModel.set_category(deferredCategorySetTimer.targetCategory)
    }
}
