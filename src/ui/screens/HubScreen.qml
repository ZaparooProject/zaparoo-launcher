// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
pragma ComponentBehavior: Bound

import QtQuick
import Zaparoo.Theme
import Zaparoo.Ui
import Zaparoo.Browse as Browse

// cxx-qt 0.8 patches `isFinal: true` on singleton properties but the
// qmltypes schema has no `isFinal` slot for Method, so every qinvokable
// call on a Zaparoo.Browse singleton (set_category, index_for_category,
// etc.) still trips qmllint's "Member can be shadowed" check. Until
// the schema grows method-level finality, suppress the compiler
// category file-wide.
// qmllint disable compiler

// Hub screen — categories row only. Pure input dispatcher: emits
// `requestAccept(category)` on Accept and `requestQuit` on Escape.
// All cross-screen orchestration (model fills, deferred set_category,
// cover prefetch, transition overlay, screen flip) lives in Main.qml.
// `transitioning` is written by the router so the row hides during
// the loading wait.
//
// The Hub renders as a static, centered row of category tiles — no
// sliding carousel, no per-press band-slide animation. Categories are
// 3-6 short top-level labels (`Favorites`, `Consoles`, `Computer`,
// `Handheld`, `Arcade` on MiSTer); fixed-position cells read more
// clearly as top-level navigation and stay cheap on Qt's Software
// adaptation. The earlier Carousel component sat under the same band
// scaling-up the focused tile mid-slide, which on MiSTer paid the
// per-frame cost of repainting the bg-circuit texture under a
// translucent focus-ring rectangle across the full band.
Item {
    id: hub

    property bool transitioning: false
    property int currentIndex: 0

    signal requestAccept(category: string)
    signal requestQuit()

    // Restore the hub from the persisted `Browse.HubState.category`
    // (or index 0 if the saved value is missing from the model). Always
    // cascades into `SystemsModel.set_category` so the systems-model
    // reset handler fires and drives the next step of the restore chain.
    //
    // Called from two sites in Main.qml — the Component.onCompleted
    // early-arrival path (catalog already seeded synchronously) and the
    // CategoriesModel.onModelReset listener (later refreshes). On a
    // refresh the category list can reorder, so the row index MUST be
    // re-seeded even when SystemsModel is already on the chosen
    // category — otherwise the visible focus drifts off whichever
    // screen the user is on. Only the expensive set_category call is
    // gated; the QML-side index assignment is cheap and idempotent.
    // The `is_empty` clause mirrors Rust's same-named recovery in
    // SystemsModel::set_category so a stale-but-empty model still gets
    // a retry shot.
    function restoreFromCategoriesReset(): void {
        const savedCategory = Browse.HubState.category
        const idx = savedCategory === ""
                    ? -1
                    : Browse.CategoriesModel.index_for_category(savedCategory)
        const chosenIndex = idx >= 0 ? idx : 0
        const chosenCategory = idx >= 0
                               ? savedCategory
                               : Browse.CategoriesModel.category_at(chosenIndex)
        hub.currentIndex = chosenIndex
        if (Browse.SystemsModel.current_category === chosenCategory
            && Browse.SystemsModel.count > 0)
            return
        Browse.SystemsModel.set_category(chosenCategory)
    }

    // Returns true if the focus actually moved. Empty rows leave disk
    // state alone — see tst_persistence.qml for the regression guarded
    // against. Past either end the index wraps modulo count so
    // right-at-end whips to 0 and left-at-start whips to count-1; with
    // no slide animation, the focus simply jumps.
    function _navigate(delta: int): bool {
        const count = Browse.CategoriesModel.count
        if (count <= 0)
            return false
        const next = ((hub.currentIndex + delta) % count + count) % count
        if (next === hub.currentIndex)
            return false
        hub.currentIndex = next
        return true
    }

    // Side-effect of every focus move: persist HubState. We do NOT call
    // SystemsModel.set_category here — that one's reserved for Accept
    // (and the router orchestrates it). Calling it on every left/right
    // press fires two model resets (synchronous clear + async tokio
    // fill) per press, each destroying-and-recreating SystemsScreen's
    // bound delegates on the UI thread — choppy on MiSTer even though
    // SystemsScreen is `visible: false`. See `bfa0629 perf: drop the
    // eager system-cover prefetcher` for the prior round of this lesson.
    function _commitCategory(category: string): void {
        Browse.HubState.category = category
    }

    function handleAction(action: string): void {
        if (action === "left") {
            if (hub._navigate(-1))
                hub._commitCategory(
                    Browse.CategoriesModel.category_at(hub.currentIndex))
        } else if (action === "right") {
            if (hub._navigate(1))
                hub._commitCategory(
                    Browse.CategoriesModel.category_at(hub.currentIndex))
        } else if (action === "accept") {
            // Empty row sends "" — router treats that as the committed
            // "Enter on empty hub goes to Systems" passthrough.
            const chosen = Browse.CategoriesModel.count <= 0
                ? ""
                : Browse.CategoriesModel.category_at(hub.currentIndex)
            hub.requestAccept(chosen)
        } else if (action === "cancel") {
            hub.requestQuit()
        }
    }

    // ── Visual tree ───────────────────────────────────────────────────────────

    Item {
        id: categoriesRow

        // Cell layout. The image area is a square equal to coverWidth;
        // the label sits inside the cell below it. `cellHeight` mirrors
        // Tile's internal `_labelHeight = 2 lines × FontMetrics.height
        // + pctH(0.4)` formula so long category names like "Handheld
        // Consoles" can wrap onto a second line inside the Tile. If
        // you change either side, change the other.
        readonly property int spacing: Sizing.pctW(3)
        readonly property int sideInset: Sizing.pctW(5)
        readonly property int maxCellWidth: Sizing.pctH(22)
        readonly property int n: Browse.CategoriesModel.count
        readonly property int rawCellWidth:
            n > 0
                ? Math.floor((width - 2 * sideInset - (n - 1) * spacing) / n)
                : 0
        readonly property int cellWidth: Math.min(maxCellWidth, rawCellWidth)
        readonly property int cellHeight:
            Sizing.pctH(22) + Sizing.pctH(1)
            + Math.ceil(2 * rowLabelFm.height) + Sizing.pctH(0.4)
        readonly property int totalRowWidth:
            n > 0 ? n * cellWidth + (n - 1) * spacing : 0
        readonly property int rowOriginX: (width - totalRowWidth) / 2

        // Symmetric padding contains the focused tile's 1.06× scale
        // bleed inside the row's own bounds. The earlier Carousel
        // anchored cells at y=0 within a band that only carried slack
        // at the bottom, so the scale bleed leaked upward into the
        // bg-circuit area above the band.
        readonly property int verticalPadding: Sizing.pctH(2)

        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width
        height: cellHeight + 2 * verticalPadding
        y: Sizing.pctH(33)

        // Hide the tiles while the router holds us here on a forward
        // transition so the centred "Loading…" cue (painted from
        // Main.qml) reads alone.
        visible: !hub.transitioning

        FontMetrics {
            id: rowLabelFm
            font.family: Theme.fontUi
            font.pixelSize: Sizing.fontSize(2.6)
        }

        Component {
            id: tileDelegate
            Tile {}
        }

        Repeater {
            id: itemRepeater

            model: Browse.CategoriesModel

            Item {
                id: cellItem

                required property int index
                required property string name
                required property string coverKey

                x: categoriesRow.rowOriginX
                   + index * (categoriesRow.cellWidth + categoriesRow.spacing)
                y: categoriesRow.verticalPadding
                width: categoriesRow.cellWidth
                height: categoriesRow.cellHeight

                readonly property bool isSelected: index === hub.currentIndex
                // Focused tile draws on top so its 1.06× scale-up isn't
                // clipped by neighbours to the right.
                z: isSelected ? 1 : 0

                TileLoader {
                    anchors.fill: parent
                    sourceComponent: tileDelegate
                    isSelected: cellItem.isSelected
                    isFocused: true
                    name: cellItem.name
                    coverKey: cellItem.coverKey
                }
            }
        }
    }

    // CategoriesModel has no `loading` qproperty — the catalog is
    // fetched eagerly via bind_to_endpoint!. The brief cold-launch
    // window where count===0 surfaces as "No categories" is acceptable
    // per the "Loading is brief" locked decision in MVP_PLAN.md.
    ScreenStateOverlay {
        anchors.centerIn: categoriesRow
        width: categoriesRow.width
        height: categoriesRow.height
        loading: false
        errorMessage: Browse.CategoriesModel.error_message ?? ""
        count: Browse.CategoriesModel.count
        emptyText: qsTr("No categories")
    }
}
