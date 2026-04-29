// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0

import QtQuick
import QtQuick.Window
import QtQuick.Controls
import Zaparoo.Ui
import Zaparoo.Theme
import Zaparoo.Screens
import Zaparoo.Browse as Browse

// cxx-qt 0.8 patches `isFinal: true` on singleton properties but the
// qmltypes schema has no `isFinal` slot for Method, so every qinvokable
// call on a Zaparoo.Browse singleton still trips qmllint's "Member can
// be shadowed" check. Until the schema grows method-level finality,
// suppress the compiler category file-wide.
// qmllint disable compiler

// Visual tree. Edit this file in Qt Design Studio; the state machine
// and side-effects live in Main.qml which extends this layout. Keep
// this file declarative — property bindings and child objects only,
// no imperative JS or signal-handler bodies, so the designer sees
// everything in the 2D view.
ApplicationWindow {
    id: root

    // Screen constants re-exported from the manager so tests and
    // Main.qml can reference them without importing Zaparoo.Screens.
    readonly property string screenHub: ScreenManager.screenHub
    readonly property string screenSystems: ScreenManager.screenSystems
    readonly property string screenGames: ScreenManager.screenGames

    // Runtime state. `activeScreen` mirrors ScreenManager's property
    // (two-way synced below so direct assignment from tests still
    // works).
    property bool fullScreen: false
    property string activeScreen: ScreenManager.activeScreen

    // Defaults keep the design canvas at a sensible aspect for Design
    // Studio. Main.qml overrides these at runtime with Screen.width /
    // Screen.height, so the live launcher still fills the screen.
    width: 1280
    height: 720
    visible: true
    visibility: root.fullScreen ? Window.FullScreen : Window.Windowed
    title: qsTr("Zaparoo Launcher")

    // Screen plumbing exposed for Main.qml's orchestration. Anything
    // inside the screens (categories row, systems/games grids) is
    // reached via root.hubScreen.* / root.systemsScreen.* /
    // root.gamesScreen.* — no per-widget aliases here.
    property alias hubScreen: hubScreen
    property alias systemsScreen: systemsScreen
    property alias gamesScreen: gamesScreen

    property bool cardWriteModalVisible: false
    property bool cardWriteFailed: false

    // Forward-transition state owned by Main.qml. "" while idle;
    // "systems" or "games" while waiting on a model fill before
    // flipping `activeScreen`. Declared here so the source-screen
    // content-hiding bindings (row/grid `visible`) resolve statically
    // in qmllint.
    property string pendingTransition: ""

    // Per-screen state derivation. Shape mirrors ScreenStateOverlay's
    // `state` ternary so the help bar and the in-screen overlay agree
    // on what state each screen is in. Hub has no Loading row —
    // CategoriesModel binds eagerly via bind_to_endpoint! and exposes
    // no `loading` qproperty, so a count-of-zero collapses straight
    // into Empty (matching the overlay's existing behavior on Hub).
    readonly property string systemsScreenState:
        Browse.SystemsModel.loading ? "loading"
        : ((Browse.SystemsModel.error_message ?? "") !== "" ? "error"
        : (Browse.SystemsModel.count === 0 ? "empty" : "ready"))

    readonly property string gamesScreenState:
        Browse.GamesModel.loading ? "loading"
        : ((Browse.GamesModel.error_message ?? "") !== "" ? "error"
        : (Browse.GamesModel.count === 0 ? "empty" : "ready"))

    readonly property string hubScreenState:
        (Browse.CategoriesModel.error_message ?? "") !== "" ? "error"
        : (Browse.CategoriesModel.count === 0 ? "empty" : "ready")

    signal cancelCardWriteRequested()

    // Two-way sync between root.activeScreen and ScreenManager.activeScreen.
    // Binding-breaking assignments (tests setting root.activeScreen = "games")
    // still propagate to ScreenManager; ScreenManager changes (from the
    // screens) still update root.activeScreen. The `if (X !== Y)` guard
    // on each side prevents the obvious cycle. Adding any transformation
    // between the two sides would defeat the guard — see #24 for the
    // tracked single-source-of-truth refactor.
    onActiveScreenChanged: {
        if (ScreenManager.activeScreen !== root.activeScreen)
            ScreenManager.activeScreen = root.activeScreen
    }
    Connections {
        target: ScreenManager
        function onActiveScreenChanged(): void {
            if (root.activeScreen !== ScreenManager.activeScreen)
                root.activeScreen = ScreenManager.activeScreen
        }
    }

    // ── Background ────────────────────────────────────────────────────────────

    Rectangle {
        anchors.fill: parent
        color: Theme.bgDeep
    }

    // Faint circuit-trace texture, tiled across the whole window. The
    // PNG is pre-rendered from resources/images/bg-circuit.svg at the
    // source pattern's native 304×304 size, with white at ~8 % alpha
    // baked into the pixmap so QtSvg isn't needed at runtime. Sits
    // between bgDeep and the rest of the tree so logos, captions, and
    // selection cards stay fully legible. `Image.Tile` is software-
    // rendered, so this is MiSTer-safe; `cache: true` keeps the
    // pixmap in QPixmapCache after first decode.
    Image {
        anchors.fill: parent
        source: "qrc:/qt/qml/Zaparoo/App/resources/images/bg-circuit.png"
        fillMode: Image.Tile
        cache: true
        smooth: false        // 1:1 tile — filtering would just blur the lines
        // Synchronous so the first frame paints with the texture instead
        // of flashing the bare bgDeep underneath. One small PNG decode
        // at startup is cheap.
        asynchronous: false
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

    // ── Screen containers ─────────────────────────────────────────────────────

    // Stacked container — only the active screen paints. Hub →
    // Systems → Games drill-downs (and Esc back) are instant cuts:
    // bind `visible` directly on the live `activeScreen` and let
    // Qt's scene graph swap which screen paints in one frame.
    //
    // Earlier iterations tried a horizontal slide, then a direct
    // opacity fade on the screen container, then an overlay-rectangle
    // fade. All three were structurally too expensive for Qt Quick's
    // Software adaptation when the destination screen is a dense
    // grid. Translucent overlays don't subtract from the renderer's
    // dirty region, so every cell underneath re-rasterises per frame
    // throughout the fade — text labels, cover images, card bodies.
    // Instant cuts paint the new screen exactly once. See
    // docs/qml-gotchas.md → "Software-renderer animation costs"
    // for the full reasoning.
    //
    // No additional cue on screen change: the help-bar text changes
    // instantly, the screen body swaps, and the user just pressed
    // OK or Esc — the action is deliberate and the feedback is
    // immediate. The page-dot pulse inside `PagedGrid` is the only
    // animated transition cue in the launcher.
    //
    // The wrapper `Item` stays for grouping clarity; with no fade
    // machinery it carries no buffered state. Model bindings stay
    // live across deactivations so Esc back to systems doesn't
    // re-instantiate the whole delegate tree — Items with
    // `visible: false` skip painting but keep their scene graph
    // alive and their decoded covers warm.
    Item {
        id: stackedScreens

        anchors.fill: parent

        HubScreen {
            id: hubScreen
            anchors.fill: parent
            visible: root.activeScreen === root.screenHub
            transitioning: root.pendingTransition !== ""
        }

        SystemsScreen {
            id: systemsScreen
            anchors.fill: parent
            visible: root.activeScreen === root.screenSystems
            transitioning: root.pendingTransition !== ""
        }

        GamesScreen {
            id: gamesScreen
            anchors.fill: parent
            visible: root.activeScreen === root.screenGames
        }
    }

    // ── Card writer modal ────────────────────────────────────────────────────

    Modal {
        id: cardWriteModal

        open: root.cardWriteModalVisible
        kind: "transient"
        failed: root.cardWriteFailed
        title: root.cardWriteFailed
               ? qsTr("Writing failed")
               : qsTr("Put a writable card near the reader")
        onCancelRequested: root.cancelCardWriteRequested()
    }

    // ── Top-right HUD ─────────────────────────────────────────────────────────
    //
    // Clock now; status icons later. The Row is right-anchored so new icons
    // can be prepended on the left without resizing or repositioning.

    Row {
        id: topHud

        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: Sizing.pctH(2)
        anchors.rightMargin: Sizing.pctW(2)
        spacing: Sizing.pctW(1.5)
        z: 200

        // Status icons go here, before clockLabel.

        Text {
            id: clockLabel

            // 30s tick keeps the displayed minute fresh without per-second
            // wakeups; minutes-only display means we never need finer.
            property string currentTime: Qt.formatDateTime(new Date(), "HH:mm")

            text: clockLabel.currentTime
            font.family: Theme.fontUi
            font.pixelSize: Sizing.fontSize(2.5)
            color: Theme.textPrimary
            renderType: Text.NativeRendering

            Timer {
                interval: 30000
                running: true
                repeat: true
                triggeredOnStart: true
                onTriggered: clockLabel.currentTime =
                    Qt.formatDateTime(new Date(), "HH:mm")
            }
        }
    }

    // ── FPS counter ───────────────────────────────────────────────────────────
    //
    // Sits in the bottom-right corner above the (conditional) status strip
    // so it never overlaps the top HUD or the bottom bars.

    FpsCounter {
        anchors.bottom: statusStrip.top
        anchors.right: parent.right
        anchors.bottomMargin: Sizing.pctH(1)
        anchors.rightMargin: Sizing.pctW(1)
        z: 200
    }

    // ── Connection status strip ───────────────────────────────────────────────
    //
    // Shown only when Core is unreachable or the catalog failed to load;
    // otherwise the strip is hidden and takes no space. Connection state
    // constants mirror rust/launcher/src/models/app_status.rs:
    //   0 DISCONNECTED · 1 CONNECTING · 2 READY · 3 ERROR.

    Rectangle {
        id: statusStrip

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: instructionsBar.top
        height: visible ? Sizing.pctH(4) : 0
        visible: Browse.AppStatus.connection_state !== 2
        color: Theme.bgBar
        border.width: 1
        // White border on ERROR draws the eye to the strip; the muted
        // border on CONNECTING/DISCONNECTED keeps it informational.
        border.color: Browse.AppStatus.connection_state === 3
                      ? Theme.textPrimary
                      : Theme.borderSubtle
        z: 150

        Text {
            anchors.centerIn: parent
            // `%1` placeholder keeps translators in charge of word order —
            // some languages won't lead with "Core error". `last_error`
            // is untranslated (it's the Rust-side error string) on purpose.
            text: {
                const state = Browse.AppStatus.connection_state;
                if (state === 3) {
                    const msg = Browse.AppStatus.last_error ?? "";
                    return msg !== ""
                        ? qsTr("Core error: %1").arg(msg)
                        : qsTr("Core error");
                }
                if (state === 1) return qsTr("Connecting to Zaparoo Core…");
                return qsTr("Disconnected from Zaparoo Core");
            }
            font.family: Theme.fontUi
            font.pixelSize: Sizing.fontSize(2.5)
            color: Theme.textPrimary
            renderType: Text.NativeRendering
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
            // (activeScreen, screenState, modal?)-keyed lookup. The modal
            // row wins outright; otherwise per-screen text varies with
            // the screen's data-state (Loading / Error / Empty / Ready).
            // Error and Empty share the retry-or-back row on Systems and
            // Games (both wire `accept` to re-fire `set_category` /
            // `set_system` in non-Ready state). Hub has no retry handler
            // — CategoriesModel binds eagerly via bind_to_endpoint! and
            // recovers automatically — so its non-Ready row drops [OK]
            // RETRY rather than promising behavior the screen doesn't
            // implement.
            //
            // During a forward transition (`pendingTransition !== ""`)
            // the router's input gate swallows every press — including
            // cancel — so the bar blanks rather than advertising
            // buttons that won't respond. Modals still win outright;
            // they run on top of the input gate.
            text: {
                if (root.cardWriteModalVisible)
                    return qsTr("[ESC] CANCEL");
                if (root.pendingTransition !== "")
                    return "";
                if (root.activeScreen === root.screenHub) {
                    if (root.hubScreenState === "ready")
                        return qsTr("[<>] CATEGORY  [OK] SELECT  [ESC] QUIT");
                    return qsTr("[ESC] QUIT");
                }
                if (root.activeScreen === root.screenSystems) {
                    if (root.systemsScreenState === "loading")
                        return qsTr("[ESC] BACK");
                    if (root.systemsScreenState === "ready")
                        return qsTr("[<>] SYSTEM  [OK] GAMES  [TAB] FLASH CARD  [ESC] BACK");
                    return qsTr("[OK] RETRY  [ESC] BACK");
                }
                // games
                if (root.gamesScreenState === "loading")
                    return qsTr("[ESC] BACK");
                if (root.gamesScreenState === "ready")
                    return qsTr("[<>] GAME  [OK] PLAY  [TAB] FLASH CARD  [ESC] BACK");
                return qsTr("[OK] RETRY  [ESC] BACK");
            }
            font.family: Theme.fontUi
            font.pixelSize: Sizing.fontSize(2.5)
            color: Theme.textDim
            renderType: Text.NativeRendering
        }
    }
}
