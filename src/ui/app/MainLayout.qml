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

// cxx-qt 0.7 doesn't emit FINAL markers in plugin.qmltypes, so qmllint
// flags every call on a Zaparoo.Browse singleton as "can be shadowed".
// Remove after the cxx-qt 0.8 upgrade.
// qmllint disable compiler

// Visual tree. Edit this file in Qt Design Studio; the state machine
// and side-effects live in Main.qml which extends this layout. Keep
// this file declarative — property bindings and child objects only,
// no imperative JS or signal-handler bodies, so the designer sees
// everything in the 2D view.
ApplicationWindow {
    id: root

    // Screen/focus constants re-exported from the manager + HubScreen so
    // tests and Main.qml can reference them without importing both.
    readonly property string screenHub: ScreenManager.screenHub
    readonly property string screenGames: ScreenManager.screenGames
    readonly property string focusCategories: hubScreen.focusCategories
    readonly property string focusSystems: hubScreen.focusSystems

    // Runtime state. `activeScreen` mirrors ScreenManager's property
    // (two-way synced below so direct assignment from tests still
    // works). `hubFocus` aliases HubScreen's internal focus.
    property bool fullScreen: false
    property string activeScreen: ScreenManager.activeScreen
    property alias hubFocus: hubScreen.section

    // Drives the hub↔games slide transition. 0 = hub centred; width = games centred.
    property real screenOffset: root.activeScreen === root.screenGames ? root.width : 0

    // Defaults keep the design canvas at a sensible aspect for Design
    // Studio. Main.qml overrides these at runtime with Screen.width /
    // Screen.height, so the live launcher still fills the screen.
    width: 1280
    height: 720
    visible: true
    visibility: root.fullScreen ? Window.FullScreen : Window.Windowed
    title: qsTr("Zaparoo Launcher")

    // Aliases so Main.qml (and existing tests) can drive the carousels
    // without reaching through nested component ids.
    property alias categoriesCarousel: hubScreen.categoriesCarousel
    property alias systemsCarousel: hubScreen.systemsCarousel
    property alias gamesCarousel: gamesScreen.gamesCarousel

    // Screen/manager plumbing exposed for Main.qml's orchestration.
    property alias hubScreen: hubScreen
    property alias gamesScreen: gamesScreen

    Behavior on screenOffset {
        NumberAnimation {
            duration: 220
            easing.type: Easing.OutCubic
        }
    }

    // Two-way sync between root.activeScreen and ScreenManager.activeScreen.
    // Binding-breaking assignments (tests setting root.activeScreen = "games")
    // still propagate to ScreenManager; ScreenManager changes (from the
    // screens) still update root.activeScreen.
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

    HubScreen {
        id: hubScreen
        x: -root.screenOffset
        width: parent.width
        height: parent.height
    }

    GamesScreen {
        id: gamesScreen
        x: parent.width - root.screenOffset
        width: parent.width
        height: parent.height
        active: root.activeScreen === root.screenGames
    }

    // ── FPS counter ───────────────────────────────────────────────────────────

    FpsCounter {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: Sizing.pctH(1)
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
            font.family: Theme.fontRetro
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
            text: root.activeScreen === root.screenGames
                  ? qsTr("[<>] GAME  [OK] PLAY  [ESC] BACK")
                  : (root.hubFocus === root.focusSystems
                     ? qsTr("[<>] SYSTEM  [OK] GAMES  [ESC] BACK")
                     : qsTr("[<>] CATEGORY  [OK] SELECT  [ESC] QUIT"))
            font.family: Theme.fontRetro
            font.pixelSize: Sizing.fontSize(2.5)
            color: Theme.textDim
            renderType: Text.NativeRendering
        }
    }
}
