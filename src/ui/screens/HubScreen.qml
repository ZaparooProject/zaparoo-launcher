// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0

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

// Hub screen — categories carousel only. Pure input dispatcher: emits
// `requestAccept(category)` on Accept and `requestQuit` on Escape.
// All cross-screen orchestration (model fills, deferred set_category,
// cover prefetch, transition overlay, screen flip) lives in Main.qml.
// `transitioning` is written by the router so the carousel hides
// during the loading wait.
Item {
    id: hub

    property alias categoriesCarousel: categoriesCarousel
    property bool transitioning: false

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
    // refresh the category list can reorder, so the carousel index
    // MUST be re-seeded even when SystemsModel is already on the
    // chosen category — otherwise the visible carousel slot drifts
    // off whichever screen the user is on. Only the expensive
    // set_category call is gated; the QML-side index assignment is
    // cheap and idempotent. The `is_empty` clause mirrors Rust's
    // same-named recovery in SystemsModel::set_category so a
    // stale-but-empty model still gets a retry shot.
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

    // Side-effect of every carousel commit: persist HubState. We do
    // NOT call SystemsModel.set_category here — that one's reserved
    // for Accept (and the router orchestrates it). Calling it on every
    // left/right press fires two model resets (synchronous clear +
    // async tokio fill) per press, and each reset destroys-and-recreates
    // 99 Tile delegates in SystemsScreen's bound Repeater on the UI
    // thread — choppy on MiSTer, even though SystemsScreen is
    // `visible: false`. See `bfa0629 perf: drop the eager system-cover
    // prefetcher` for the prior round of this lesson.
    function _commitCategory(category: string): void {
        Browse.HubState.category = category
    }

    function handleAction(action: string): void {
        if (action === "left") {
            if (hub._navigateCarousel(hub.categoriesCarousel, -1))
                hub._commitCategory(
                    Browse.CategoriesModel.category_at(hub.categoriesCarousel.currentIndex))
        } else if (action === "right") {
            if (hub._navigateCarousel(hub.categoriesCarousel, 1))
                hub._commitCategory(
                    Browse.CategoriesModel.category_at(hub.categoriesCarousel.currentIndex))
        } else if (action === "accept") {
            // Empty carousel sends "" — router treats that as the
            // committed "Enter on empty hub goes to Systems" passthrough.
            const chosen = hub.categoriesCarousel.itemCount <= 0
                ? ""
                : Browse.CategoriesModel.category_at(hub.categoriesCarousel.currentIndex)
            hub.requestAccept(chosen)
        } else if (action === "cancel") {
            hub.requestQuit()
        }
    }

    // ── Visual tree ───────────────────────────────────────────────────────────

    Carousel {
        id: categoriesCarousel

        // Cell layout. The image area is a square equal to coverWidth;
        // the label sits inside the cell below it. _labelHeight and
        // _gap mirror Tile's internal constants so the cell box fits
        // its contents exactly.
        readonly property int _gap: Sizing.pctH(1)
        readonly property int _labelHeight:
            Sizing.fontSize(2.4) + Sizing.pctH(0.8)
        readonly property int _imageSide: Sizing.pctH(22)
        readonly property int _coverWidth: _imageSide
        readonly property int _coverHeight: _imageSide + _gap + _labelHeight
        readonly property int _coverSpacing: Sizing.pctH(28)
        // Band has a small extra strip beyond the cell so the selected
        // tile's 1.06× scale doesn't get clipped by the band edges. The
        // focus outline ring is drawn inset against the card edge, so
        // it never bleeds past the cell — only the scale needs slack.
        readonly property int _bandHeight: _coverHeight + Sizing.pctH(2)

        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width
        height: _bandHeight
        y: Sizing.pctH(30)
        coverWidth: _coverWidth
        coverHeight: _coverHeight
        coverSpacing: _coverSpacing

        // Hide the tiles while the router holds us here on a forward
        // transition so the centred "Loading…" cue (painted from
        // Main.qml) reads alone in the cleared band.
        visible: !hub.transitioning

        model: Browse.CategoriesModel
        delegate: Tile {}
    }

    // CategoriesModel has no `loading` qproperty — the catalog is
    // fetched eagerly via bind_to_endpoint!. The brief cold-launch
    // window where count===0 surfaces as "No categories" is acceptable
    // per the "Loading is brief" locked decision in MVP_PLAN.md.
    ScreenStateOverlay {
        anchors.centerIn: categoriesCarousel
        width: categoriesCarousel.width
        height: categoriesCarousel.height
        loading: false
        errorMessage: Browse.CategoriesModel.error_message ?? ""
        count: Browse.CategoriesModel.count
        emptyText: qsTr("No categories")
    }
}
