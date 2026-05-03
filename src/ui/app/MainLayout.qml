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
    readonly property string screenRecents: ScreenManager.screenRecents
    readonly property string screenSettings: ScreenManager.screenSettings

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

    Binding {
        target: Resources
        property: "buttonLayout"
        value: Browse.Settings.current_button_layout
    }

    // Screen plumbing exposed for Main.qml's orchestration. Anything
    // inside the screens (categories row, systems/games grids) is
    // reached via root.hubScreen.* / root.systemsScreen.* /
    // root.gamesScreen.* — no per-widget aliases here.
    property alias hubScreen: hubScreen
    property alias systemsScreen: systemsScreen
    property alias gamesScreen: gamesScreen
    property alias recentsScreen: recentsScreen
    property alias settingsScreen: settingsScreen
    property alias contextMenu: contextMenu
    property alias firstRunIndexModal: firstRunIndexModal
    property alias logUploadModal: logUploadModal

    property bool cardWriteModalVisible: false
    property bool cardWriteFailed: false
    property bool qrCodeModalVisible: false
    property bool firstRunIndexModalVisible: false
    property bool logUploadModalVisible: false
    property bool contextMenuVisible: false
    property rect contextMenuAnchor: Qt.rect(0, 0, 0, 0)
    // Owner-aware. Written by Main.qml at openContextMenu time; each entry
    // is `{ id: string, label: string }`. The router switches on `id`, not
    // position, so adding/removing entries can't silently re-map actions.
    // TODO: `Browse.SystemStatus.has_nfc` (used by Main.qml when building
    // the games-tile entries) is only updated when Core runs locally
    // (rust/launcher/src/models/system_status.rs:88). Remote-Core readers
    // aren't tracked yet — wire a Core-driven reader-status feed before
    // showing "Write to NFC token" in remote-Core configs.
    property var contextMenuEntries: []

    signal contextMenuAccepted(string id)
    signal contextMenuCloseRequested()

    // Forward-transition state owned by Main.qml. "" while idle;
    // "systems" or "games" while waiting on a model fill before
    // flipping `activeScreen`. Declared here so the source-screen
    // content-hiding bindings (row/grid `visible`) resolve statically
    // in qmllint.
    property string pendingTransition: ""

    // Cold-launch curtain. False until the catalog has loaded for the
    // first time this session; while false the host screens are
    // hidden and `BootOverlay` paints alone over the global
    // background. Flipped exactly once by Main.qml's connection-state
    // watcher when `connection_state` first reaches READY. After that,
    // the Loader unmounts the overlay and a subsequent disconnect
    // surfaces only via the top-right status pill — the user keeps
    // their cached catalog and just sees the link state change.
    property bool bootComplete: false

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

    readonly property string recentsScreenState:
        Browse.RecentsModel.loading ? "loading"
        : ((Browse.RecentsModel.error_message ?? "") !== "" ? "error"
        : (Browse.RecentsModel.count === 0 ? "empty" : "ready"))

    signal cancelCardWriteRequested()
    signal closeQrCodeRequested()
    signal closeFirstRunIndexRequested()
    signal closeLogUploadRequested()

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
        // Screens stay hidden until the catalog has loaded for the
        // first time. BootOverlay holds the window in the meantime;
        // see the `bootComplete` property declaration above.
        visible: root.bootComplete

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
            transitioning: root.pendingTransition !== ""
        }

        RecentsScreen {
            id: recentsScreen
            anchors.fill: parent
            visible: root.activeScreen === root.screenRecents
            transitioning: root.pendingTransition !== ""
        }

        SettingsScreen {
            id: settingsScreen
            anchors.fill: parent
            visible: root.activeScreen === root.screenSettings
            transitioning: root.pendingTransition !== ""
        }
    }

    // ── Boot overlay ─────────────────────────────────────────────────────────
    //
    // Painted between the screens and the modal layer; unmounts itself
    // the first time `bootComplete` flips true. Loader (rather than
    // `visible: false`) so the overlay leaves the scene graph after
    // dismissal — a subsequent disconnect must not bring it back over
    // the user's cached catalog.

    Loader {
        anchors.fill: parent
        active: !root.bootComplete
        z: 50
        sourceComponent: BootOverlay { }
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

    ContextMenu {
        id: contextMenu

        open: root.contextMenuVisible
        anchorRect: root.contextMenuAnchor
        entries: root.contextMenuEntries
        onAccepted: id => root.contextMenuAccepted(id)
        onCloseRequested: root.contextMenuCloseRequested()
    }

    QrCodeModal {
        id: qrCodeModal

        anchors.fill: parent
        open: root.qrCodeModalVisible
    }

    // First-run mediadb index modal. Pushed by Main.qml the first time
    // we connect to a Core whose mediadb is empty. Blocks the screens
    // beneath until the initial scan completes (or the user cancels and
    // tries again).
    FirstRunIndexModal {
        id: firstRunIndexModal

        anchors.fill: parent
        open: root.firstRunIndexModalVisible
        onCloseRequested: root.closeFirstRunIndexRequested()
    }

    // Log-upload modal. Pushed by Main.qml when the user triggers the
    // "Upload log" action in Settings. Owns its own three-phase view
    // (uploading / success / error) — the router only sees open / close.
    LogUploadModal {
        id: logUploadModal

        anchors.fill: parent
        open: root.logUploadModalVisible
        onCloseRequested: root.closeLogUploadRequested()
    }

    // ── Top-right HUD ─────────────────────────────────────────────────────────
    //
    // Host status icons plus clock. The Row is right-anchored so icons
    // can appear/disappear without moving the clock away from the edge.

    Row {
        id: topHud

        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: Sizing.pctH(2)
        anchors.rightMargin: Sizing.pctW(2)
        spacing: Sizing.pctW(1)
        z: 200
        // Explicit row height matches StatusIcon's square size so every
        // child can verticalCenter against the row and the icons + clock
        // sit on a single line. Without this Row height tracks the
        // tallest child, which is the Text element (font ascender +
        // descender) — that pushes icons up and out of alignment.
        // Clock pixelSize runs larger than the icon box because a font's
        // cap-height is ~0.7× pixelSize, so matching pixelSize to icon
        // height makes glyphs look small next to the square SVGs; bumping
        // the clock font to ~1.4× the icon size lands their visual weight
        // on par. Row height takes the max so neither child clips.
        readonly property real _iconSize: Sizing.fontSize(2.4)
        readonly property real _clockFontSize: Sizing.fontSize(3.4)
        height: Math.max(topHud._iconSize, topHud._clockFontSize)

        StatusIcon {
            anchors.verticalCenter: parent.verticalCenter
            visible: Browse.SystemStatus.has_nfc
            source: Resources.statusIconUrl("NFC")
            name: "NFC"
        }

        StatusIcon {
            anchors.verticalCenter: parent.verticalCenter
            visible: Browse.SystemStatus.has_wifi_internet
            source: Resources.statusIconUrl("WiFi")
            name: "Wi-Fi"
        }

        StatusIcon {
            anchors.verticalCenter: parent.verticalCenter
            visible: Browse.SystemStatus.has_lan_internet
            source: Resources.statusIconUrl("WiredNetwork")
            name: "LAN"
        }

        StatusIcon {
            anchors.verticalCenter: parent.verticalCenter
            visible: Browse.SystemStatus.has_bluetooth
            source: Resources.statusIconUrl("Bluetooth")
            name: "Bluetooth"
        }

        Text {
            id: clockLabel

            // 30s tick keeps the displayed minute fresh without per-second
            // wakeups; minutes-only display means we never need finer.
            // Fixed width avoids reflow on the minute boundary because
            // proportional digits make "11:11" narrower than "10:00".
            property string currentTime: Qt.formatDateTime(new Date(), "HH:mm")

            anchors.verticalCenter: parent.verticalCenter
            height: parent.height
            width: topHud._clockFontSize * 3
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignRight
            text: clockLabel.currentTime
            font.family: Theme.fontUi
            font.pixelSize: topHud._clockFontSize
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

    // Mutually-exclusive Core/indexing/scraper status surface. Sits on
    // its own line directly under `topHud`, right-aligned to the same
    // edge as the clock. When the pill is idle (no connection issue,
    // no indexing, no scraping) it collapses to zero size and the
    // second line takes no visual space.
    CoreStatusPill {
        anchors.top: topHud.bottom
        anchors.right: topHud.right
        anchors.topMargin: Sizing.pctH(0.8)
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

        // (activeScreen, screenState, modal?)-keyed lookup. The modal
        // row wins outright; otherwise per-screen entries vary with
        // the screen's data-state (Loading / Error / Empty / Ready).
        // Error and Empty share the retry-or-back row on Systems and
        // Games (both wire `accept` to re-fire `set_category` /
        // `set_system` in non-Ready state). Hub has no retry handler
        // — CategoriesModel binds eagerly via bind_to_endpoint! and
        // recovers automatically — so its non-Ready row drops the
        // Retry entry rather than promising behavior the screen
        // doesn't implement.
        //
        // During a forward transition (`pendingTransition !== ""`)
        // the router's input gate swallows every press — including
        // cancel — so the bar blanks rather than advertising
        // buttons that won't respond. Modals still win outright;
        // they run on top of the input gate.
        //
        // Each entry resolves to a button glyph (Dpad / ButtonA /
        // ButtonB / ButtonX) plus a label. The button names are routed
        // through Resources.iconUrl(), which owns the qrc path rules.
        //
        // Label vocabulary is deliberately minimal: D-pad is always
        // "Move"; A is "Open" for both drill-downs and launches (the
        // tile and screen title carry the specific identity, so the
        // verb doesn't need to repeat that); B is "Back" except on
        // the Hub root, where it's "Quit". Sentence case throughout.
        readonly property var helpEntries: {
            if (root.contextMenuVisible)
                return [
                    { button: "ButtonA", label: qsTr("Select") },
                    { button: "ButtonB", label: qsTr("Close") }
                ];
            if (root.cardWriteModalVisible)
                return [{ button: "ButtonB", label: qsTr("Cancel") }];
            if (root.qrCodeModalVisible)
                return [{ button: "ButtonB", label: qsTr("Close") }];
            if (root.logUploadModalVisible) {
                const phase = root.logUploadModal.phase;
                if (phase === root.logUploadModal._stateSuccess)
                    return [
                        { button: "ButtonA", label: qsTr("Done") },
                        { button: "ButtonB", label: qsTr("Close") }
                    ];
                if (phase === root.logUploadModal._stateError)
                    return [
                        { button: "ButtonA", label: qsTr("Retry") },
                        { button: "ButtonB", label: qsTr("Close") }
                    ];
                // Idle / uploading: only Cancel.
                return [{ button: "ButtonB", label: qsTr("Cancel") }];
            }
            if (!root.bootComplete)
                return [];
            if (root.firstRunIndexModalVisible) {
                const phase = root.firstRunIndexModal.phase;
                if (phase === "running")
                    return [{ button: "ButtonB", label: qsTr("Cancel") }];
                if (phase === "completed")
                    return [];
                return [{ button: "ButtonA", label: qsTr("Start") }];
            }
            if (root.pendingTransition !== "")
                return [];
            if (root.activeScreen === root.screenHub) {
                // Hub always has the actions row (Recently Played /
                // Settings), so Move/Open/Quit applies even when the
                // categories row is empty (0 systems indexed) — the
                // help bar must reflect that the actions row is
                // navigable, otherwise the user reads "Quit only"
                // and misses the Settings tile entirely.
                return [
                    { button: "Dpad",    label: qsTr("Move") },
                    { button: "ButtonA", label: qsTr("Open") },
                    { button: "ButtonB", label: qsTr("Quit") }
                ];
            }
            if (root.activeScreen === root.screenSystems) {
                if (root.systemsScreenState === "loading")
                    return [{ button: "ButtonB", label: qsTr("Back") }];
                if (root.systemsScreenState === "ready") {
                    // L/R shoulders page jump; only advertise the cue
                    // when there's a second page to jump to, so we
                    // don't promise a press that no-ops on a single
                    // page of systems.
                    const pages = root.systemsScreen.systemsGrid.pageCount;
                    let row = [
                        { button: "Dpad",    label: qsTr("Move") }
                    ];
                    if (pages > 1)
                        row.push({ buttons: ["ButtonL", "ButtonR"], label: qsTr("Page") });
                    row.push({ button: "ButtonA", label: qsTr("Open") },
                             { button: "ButtonX", label: qsTr("Options") },
                             { button: "ButtonB", label: qsTr("Back") });
                    return row;
                }
                return [
                    { button: "ButtonA", label: qsTr("Retry") },
                    { button: "ButtonB", label: qsTr("Back") }
                ];
            }
            if (root.activeScreen === root.screenRecents) {
                if (root.recentsScreenState === "loading")
                    return [{ button: "ButtonB", label: qsTr("Back") }];
                if (root.recentsScreenState === "ready") {
                    const pages = root.recentsScreen.recentsGrid.pageCount;
                    let row = [
                        { button: "Dpad", label: qsTr("Move") }
                    ];
                    if (pages > 1)
                        row.push({ buttons: ["ButtonL", "ButtonR"], label: qsTr("Page") });
                    row.push({ button: "ButtonA", label: qsTr("Open") },
                             { button: "ButtonB", label: qsTr("Back") });
                    return row;
                }
                return [
                    { button: "ButtonA", label: qsTr("Retry") },
                    { button: "ButtonB", label: qsTr("Back") }
                ];
            }
            if (root.activeScreen === root.screenSettings) {
                let row = [];
                // Up/Down moves between fields; only useful when there
                // are 2+ fields.
                if (root.settingsScreen.fieldCount > 1) {
                    row.push({
                        buttons: ["DpadUp", "DpadDown"],
                        label: qsTr("Move")
                    });
                }
                // Left/Right cycles the focused field's value. Skip
                // the cue when the focused field is an action row
                // (no left/right binding) or there are no fields.
                if (root.settingsScreen.fieldCount > 0
                    && !root.settingsScreen.focusedFieldIsAction) {
                    row.push({
                        buttons: ["DpadLeft", "DpadRight"],
                        label: qsTr("Change")
                    });
                }
                if (root.settingsScreen.focusedFieldIsToggle)
                    row.push({ button: "ButtonA", label: qsTr("Toggle") });
                else if (root.settingsScreen.focusedFieldIsAction
                         && !root.settingsScreen.focusedActionDisabled)
                    row.push({
                        button: "ButtonA",
                        label: root.settingsScreen.focusedActionBusy
                               ? qsTr("Cancel") : qsTr("Start")
                    });
                row.push({ button: "ButtonB", label: qsTr("Back") });
                return row;
            }
            // games
            if (root.gamesScreenState === "loading")
                return [{ button: "ButtonB", label: qsTr("Back") }];
            if (root.gamesScreenState === "ready") {
                const pages = root.gamesScreen.gamesGrid.pageCount;
                // Options menu is only meaningful on media leaves —
                // folder/root entries open via Accept and have no
                // per-entry actions. Drop the X cue so the bar
                // doesn't promise a press that no-ops.
                const idx = root.gamesScreen.gamesGrid.currentIndex;
                const entryType = Browse.GamesModel.entry_type_at(idx);
                const isFolder = entryType === "directory" || entryType === "root";
                let row = [
                    { button: "Dpad",    label: qsTr("Move") }
                ];
                if (pages > 1)
                    row.push({ buttons: ["ButtonL", "ButtonR"], label: qsTr("Page") });
                row.push({ button: "ButtonA", label: qsTr("Open") });
                if (!isFolder)
                    row.push({ button: "ButtonX", label: qsTr("Options") });
                row.push({ button: "ButtonB", label: qsTr("Back") });
                return row;
            }
            return [
                { button: "ButtonA", label: qsTr("Retry") },
                { button: "ButtonB", label: qsTr("Back") }
            ];
        }

        Row {
            anchors.centerIn: parent
            spacing: Sizing.pctW(2)

            Repeater {
                model: instructionsBar.helpEntries

                // Each entry is either a single-glyph cue
                // (`{ button: "ButtonA", label: "Open" }`) or a
                // multi-glyph cue rendered as N icons in a row before
                // the label (`{ buttons: ["DpadLeft", "DpadRight"],
                // label: "Change" }`). The Settings screen uses the
                // multi-glyph form to disambiguate "left/right cycles
                // the value" from "up/down moves between fields".
                delegate: Row {
                    id: helpEntry
                    required property var modelData
                    spacing: Sizing.pctW(0.6)

                    readonly property var buttonList:
                        helpEntry.modelData.buttons !== undefined
                            ? helpEntry.modelData.buttons
                            : [helpEntry.modelData.button]

                    Repeater {
                        model: helpEntry.buttonList
                        delegate: Image {
                            required property string modelData
                            anchors.verticalCenter: parent.verticalCenter
                            height: Sizing.pctH(4)
                            width: height
                            fillMode: Image.PreserveAspectFit
                            sourceSize.height: height
                            sourceSize.width: width
                            source: Resources.iconUrl(modelData)
                            smooth: true
                        }
                    }

                    Text {
                        anchors.verticalCenter: helpEntry.verticalCenter
                        text: helpEntry.modelData.label
                        font.family: Theme.fontUi
                        font.pixelSize: Sizing.fontSize(2.5)
                        color: Theme.textPrimary
                        renderType: Text.NativeRendering
                    }
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        z: 10000
        visible: !Browse.Settings.current_mouse_enabled
        enabled: visible
        hoverEnabled: true
        acceptedButtons: Qt.AllButtons
        cursorShape: Qt.BlankCursor
    }
}
