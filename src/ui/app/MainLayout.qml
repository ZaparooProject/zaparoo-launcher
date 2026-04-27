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
// call on a Zaparoo.Browse singleton (all_cover_keys, etc.) still trips
// qmllint's "Member can be shadowed" check. Until the schema grows
// method-level finality, suppress the compiler category file-wide.
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

    // Screen plumbing exposed for Main.qml's orchestration. Anything
    // inside the screens (categories carousel, systems/games grids) is
    // reached via root.hubScreen.* / root.gamesScreen.* — no per-widget
    // aliases here.
    property alias hubScreen: hubScreen
    property alias gamesScreen: gamesScreen

    property bool cardWriteModalVisible: false
    property bool cardWriteFailed: false

    signal cancelCardWriteRequested()

    Behavior on screenOffset {
        NumberAnimation {
            duration: 220
            easing.type: Easing.OutCubic
        }
    }

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

    // ── System logo prefetch ─────────────────────────────────────────────────
    //
    // Hidden Repeater that loads every system PNG once the catalog
    // arrives, priming Qt's pixmap cache. Without this, the *first*
    // category switch pays the PNG decode for that category's logos —
    // a visible stutter the user noticed. Subsequent visits are free.
    //
    // Bound directly to SystemsModel.cover_keys: the property is set
    // *after* the model's internal `last_ready` snapshot inside
    // `apply_state`, so the changed-signal can only fire once the keys
    // are real. No cross-model coupling, no Component.onCompleted seed.

    Item {
        id: coverPrefetch
        visible: false

        Repeater {
            model: Browse.SystemsModel.cover_keys

            Image {
                required property string modelData

                // `coverKey` carries the subdirectory (e.g. `systems/SNES`).
                // Resources.coverUrl is the same builder Tile.qml uses, so
                // this prefetch and the visible Image hit the same
                // QPixmapCache slot — see Resources.qml.
                source: Resources.coverUrl(modelData)
                // Match Tile.qml's sourceSize so the prefetch and the
                // visible Image share a QPixmapCache entry. A different
                // sourceSize would key a separate cache slot and the
                // prefetch wouldn't help.
                sourceSize.width: 256
                asynchronous: true
                cache: true
            }
        }
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

    // ── Card writer modal ────────────────────────────────────────────────────

    Rectangle {
        id: cardWriteScrim

        anchors.fill: parent
        visible: root.cardWriteModalVisible
        color: "#99000000"
        z: 300

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width * 0.78, Sizing.pctH(82))
            height: Sizing.pctH(34)
            color: Theme.bgPanel
            border.width: 2
            border.color: root.cardWriteFailed ? Theme.textPrimary : Theme.accent

            Text {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.topMargin: Sizing.pctH(7)
                anchors.leftMargin: Sizing.pctW(5)
                anchors.rightMargin: Sizing.pctW(5)
                text: root.cardWriteFailed
                      ? qsTr("Writing failed")
                      : qsTr("Put a writable card near the reader")
                font.family: Theme.fontRetro
                font.pixelSize: Sizing.fontSize(3)
                color: Theme.textPrimary
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                renderType: Text.NativeRendering
            }

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Sizing.pctH(5)
                width: Sizing.pctW(22)
                height: Sizing.pctH(7)
                color: Theme.bgBar
                border.width: 1
                border.color: Theme.borderMid
                visible: !root.cardWriteFailed

                Text {
                    anchors.centerIn: parent
                    text: qsTr("Cancel")
                    font.family: Theme.fontRetro
                    font.pixelSize: Sizing.fontSize(2.4)
                    color: Theme.textPrimary
                    renderType: Text.NativeRendering
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.cancelCardWriteRequested()
                }
            }
        }
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
            text: root.activeScreen === root.screenGames
                  ? qsTr("[<>] GAME [OK] PLAY [TAB] FLASH CARD [ESC]")
                  : (root.hubFocus === root.focusSystems
                     ? qsTr("[<>] SYS [OK] GAMES [TAB] FLASH CARD [ESC]")
                     : qsTr("[<>] CATEGORY  [OK] SELECT  [ESC] QUIT"))
            font.family: Theme.fontUi
            font.pixelSize: Sizing.fontSize(2.5)
            color: Theme.textDim
            renderType: Text.NativeRendering
        }
    }
}
