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

// Hub screen — categories carousel only. Owns the categories action
// dispatch; emits `requestSystemsScreen` on Accept/Down so Main.qml can
// drive the cross-screen transition. The systems grid lives in
// `SystemsScreen.qml` as a peer screen.
Item {
    id: hub

    property alias categoriesCarousel: categoriesCarousel

    signal requestSystemsScreen()
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

    function handleAction(action: string): void {
        if (action === "left") {
            if (hub._navigateCarousel(hub.categoriesCarousel, -1))
                Browse.HubState.category =
                    Browse.CategoriesModel.category_at(hub.categoriesCarousel.currentIndex)
        } else if (action === "right") {
            if (hub._navigateCarousel(hub.categoriesCarousel, 1))
                Browse.HubState.category =
                    Browse.CategoriesModel.category_at(hub.categoriesCarousel.currentIndex)
        } else if (action === "accept" || action === "down") {
            // Both Accept and Down drill into the systems screen. Down
            // matches d-pad / gamepad expectations (the systems grid
            // sits visually below); Accept stays for keyboard users.
            // set_category is async (Step 4a), so this returns
            // immediately; the systems load proceeds in parallel with
            // the cross-screen flip Main.qml fires off the signal.
            if (hub.categoriesCarousel.itemCount > 0) {
                const chosen =
                    Browse.CategoriesModel.category_at(hub.categoriesCarousel.currentIndex)
                Browse.HubState.category = chosen
                Browse.SystemsModel.set_category(chosen)
            }
            hub.requestSystemsScreen()
        } else if (action === "cancel") {
            hub.requestQuit()
        }
    }

    // ── Visual tree ───────────────────────────────────────────────────────────

    Carousel {
        id: categoriesCarousel

        // Cell layout. The image area is a square equal to coverWidth;
        // the label sits inside the cell below it. _labelHeight and
        // _gap mirror HubCategoryTile's internal constants so the cell
        // box fits its contents exactly.
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

        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width
        height: _bandHeight
        y: Sizing.pctH(30)
        coverWidth: _coverWidth
        coverHeight: _coverHeight
        coverSpacing: _coverSpacing

        model: Browse.CategoriesModel
        delegate: HubCategoryTile {}
    }

    // CategoriesModel has no `loading` qproperty — the catalog is
    // fetched eagerly via bind_to_endpoint!. The brief cold-launch
    // window where count===0 surfaces as "No categories" is acceptable
    // per the "Loading is brief" locked decision in MVP_PLAN.md.
    ScreenStateOverlay {
        anchors.centerIn: categoriesCarousel
        width: categoriesCarousel.width
        height: categoriesCarousel.height
        errorMessage: Browse.CategoriesModel.error_message ?? ""
        count: Browse.CategoriesModel.count
        emptyText: qsTr("No categories")
    }
}
