// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0

import QtQuick
import Zaparoo.Theme
import Zaparoo.Ui
import Zaparoo.Browse as Browse

// cxx-qt 0.8 patches `isFinal: true` on singleton properties but the
// qmltypes schema has no `isFinal` slot for Method, so every qinvokable
// call on a Zaparoo.Browse singleton (path_at, set_system, etc.) still
// trips qmllint's "Member can be shadowed" check. Until the schema grows
// method-level finality, suppress the compiler category file-wide.
// qmllint disable compiler

// Games screen — paged grid driven by `Browse.GamesModel`. Owns the
// action dispatch for the games subset; emits `requestSystemsScreen`
// on Escape so Main.qml can drive the cross-screen back-jump.
Item {
    id: games

    property alias gamesGrid: gamesGrid

    // Emitted when the user presses Escape — Main.qml flips the
    // active screen back to SystemsScreen (one peer up the back-stack;
    // a second Escape from there pops to Hub).
    signal requestSystemsScreen()
    signal requestGameCardWrite(int index)

    // Emitted when the user accepts a directory or root entry — Main.qml
    // pushes the level onto GamesState and drives the model into the new
    // path. Stays inside the games screen (no peer flip).
    signal requestNavigateIntoFolder(string path)

    // Emitted when the user cancels from a deeper folder level — Main.qml
    // pops one level off the stack and rebrowses the parent.
    signal requestNavigateOutOfFolder()

    // Move selection by (dx, dy) and commit the new selection on
    // success. Unlike HubScreen's _handleSystems, none of the games-grid
    // directions have a row-edge escape branch, so all four cardinal
    // actions share this exact body.
    function _performMove(dx: int, dy: int): void {
        if (games.gamesGrid.moveSelection(dx, dy))
            Browse.GamesState.set_selected_at_top(
                Browse.GamesModel.path_at(games.gamesGrid.currentIndex))
    }

    // Mirrors ScreenStateOverlay's `state` ternary so accept routing and
    // the in-screen overlay agree on which state we're in.
    function _state(): string {
        if (Browse.GamesModel.loading)
            return "loading"
        if ((Browse.GamesModel.error_message ?? "") !== "")
            return "error"
        if (Browse.GamesModel.count === 0)
            return "empty"
        return "ready"
    }

    // True when we're inside a navigated folder (path_stack length > 1).
    // Drives folder-aware cancel routing.
    function _atFolderLevel(): bool {
        return Browse.GamesState.path_stack.length > 1
    }

    // True when the highlighted row is launchable (not a directory or
    // root). Read by MainLayout to suppress the [TAB] FLASH CARD cue
    // while a folder is highlighted, since `write_card` no-ops there.
    readonly property bool currentEntryWritable: {
        if (gamesGrid.itemCount === 0)
            return false
        const t = Browse.GamesModel.entry_type_at(gamesGrid.currentIndex)
        return t !== "directory" && t !== "root"
    }

    function handleAction(action: string): void {
        if (action === "left") {
            games._performMove(-1, 0)
        } else if (action === "right") {
            games._performMove(1, 0)
        } else if (action === "up") {
            games._performMove(0, -1)
        } else if (action === "down") {
            games._performMove(0, 1)
        } else if (action === "accept") {
            // Accept routing depends on the screen's data state, matching
            // the help bar vocabulary in MainLayout.qml. Loading swallows
            // the press (load is in flight); Error/Empty re-fires the
            // current load (the [OK] RETRY behavior the help bar
            // promises); Ready launches the highlighted game OR drills
            // into a directory/root entry. The retry path picks
            // set_path vs set_system based on whether we're at a deeper
            // level, so retrying inside a folder doesn't kick the user
            // back to the system root.
            const state = games._state()
            if (state === "loading")
                return
            if (state === "error" || state === "empty") {
                if (games._atFolderLevel()) {
                    const stack = Browse.GamesState.path_stack
                    const top = stack[stack.length - 1]
                    Browse.GamesModel.set_path(top)
                } else {
                    const sid = Browse.GamesModel.current_system_id
                    if (sid !== "")
                        Browse.GamesModel.set_system(sid)
                }
                return
            }
            const idx = games.gamesGrid.currentIndex
            const entryType = Browse.GamesModel.entry_type_at(idx)
            if (entryType === "directory" || entryType === "root") {
                games.requestNavigateIntoFolder(Browse.GamesModel.path_at(idx))
                return
            }
            // Persist before handing control away. Directional moves
            // already update the saved selection on every step, but the
            // user may press Accept on the first highlighted entry
            // without navigating, leaving the saved selection stale
            // from a prior system. Writing here makes the commit
            // explicit so a kill during launch resumes on the correct
            // entry.
            Browse.GamesState.set_selected_at_top(
                Browse.GamesModel.path_at(idx))
            Browse.GamesModel.launch_at(idx)
        } else if (action === "write_card") {
            if (games.gamesGrid.itemCount > 0) {
                const idx = games.gamesGrid.currentIndex
                const entryType = Browse.GamesModel.entry_type_at(idx)
                if (entryType !== "directory" && entryType !== "root") {
                    Browse.GamesState.set_selected_at_top(
                        Browse.GamesModel.path_at(idx))
                    games.requestGameCardWrite(idx)
                }
            }
        } else if (action === "cancel") {
            if (games._atFolderLevel())
                games.requestNavigateOutOfFolder()
            else
                games.requestSystemsScreen()
        }
    }

    // ── Visual tree ───────────────────────────────────────────────────────────

    // Top label — active system name. Composed via SystemsModel because
    // GamesModel only carries `current_system_id`, not the human name.
    // The id-fallback covers the brief navigate window before
    // SystemsModel sees the new id and the test harness case where
    // SystemsModel is empty; the user sees the id rather than nothing.
    //
    // The screen Item fills the whole window, so the label has to clear
    // the MainLayout logo (topMargin pctH(2) + height pctH(7) — bottom
    // edge at pctH(9)) with a pctH(2) gap.
    Text {
        id: topLabel
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Sizing.pctH(11)
        text: {
            const sid = Browse.GamesModel.current_system_id
            if (sid === "")
                return ""
            const idx = Browse.SystemsModel.index_for_system_id(sid)
            return idx >= 0 ? Browse.SystemsModel.system_name_at(idx) : sid
        }
        font.family: Theme.fontUi
        font.pixelSize: Sizing.fontSize(4)
        font.weight: Font.Medium
        color: Theme.textPrimary
        renderType: Text.NativeRendering
    }

    // Grid fills the safe zone between the top label and the help bar.
    // bottomMargin = MainLayout's instructionsBar height (pctH(6)) +
    // pctH(2) gap. If you change the help-bar height, update this too.
    PagedGrid {
        id: gamesGrid

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: topLabel.bottom
        anchors.topMargin: Sizing.pctH(2)
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Sizing.pctH(8)
        model: Browse.GamesModel
        delegate: Tile {}
        // Cover-art tiles run taller than systems logos, so a 5x3
        // layout starves vertical space. Games gets its own
        // gamesGridColumns/Rows in Sizing — 5x2 on desktop, narrower
        // branches at low resolutions match the systems grid logic.
        columnsOverride: Sizing.gamesGridColumns
        rowsOverride: Sizing.gamesGridRows
        onLoadMoreRequested: Browse.GamesModel.fetch_more()
    }

    // Bottom-of-grid status band — total is exact: Core's media.browse
    // returns directories only on page 1 and always before files, so
    // dir_count + total_files is the precise entry count for the path.
    // No "+" suffix, no estimate.
    PaginationStatus {
        anchors.left: gamesGrid.left
        anchors.right: gamesGrid.right
        anchors.bottom: gamesGrid.bottom
        height: gamesGrid.bottomBandHeight
        currentPage: gamesGrid.currentPage
        totalPages: Math.max(1,
            Math.ceil((Browse.GamesModel.dir_count
                       + Browse.GamesModel.total_files) / gamesGrid.pageSize))
        loadingMore: Browse.GamesModel.loading_more
        totalText: Browse.GamesModel.total_files > 0
                   ? qsTr("%1 files").arg(Browse.GamesModel.total_files)
                   : ""
    }

    ScreenStateOverlay {
        anchors.centerIn: gamesGrid
        width: gamesGrid.width
        height: gamesGrid.height
        loading: Browse.GamesModel.loading
        errorMessage: Browse.GamesModel.error_message ?? ""
        count: Browse.GamesModel.count
        emptyText: qsTr("No games in this system")
    }
}
