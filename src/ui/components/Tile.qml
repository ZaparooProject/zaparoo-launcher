// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0

import QtQuick
import Zaparoo.Theme

// Unified grid tile. Solid card with a centered icon area filling the
// card body, plus a white outline ring around the card when this tile
// is the focused selection. The focused tile's display name renders
// below the grid via ActiveLabel.qml — no label inside the tile —
// because per-tile labels duplicate identity already carried by the
// curated logo and force long names to wrap/elide inside cramped
// cells. Used by every tile surface in the launcher — hub categories
// row, systems grid, games grid — so the vocabulary is identical
// across screens.
//
// Parent contract — Tile must be loaded inside a host that exposes:
//   - isSelected: bool   — true when this tile is the focused selection
//   - isFocused:  bool   — true when the section owning this tile has user focus
//   - name:       string — model display name (used by the procedural
//                          fallback while the cover PNG decodes)
//   - coverKey:   string — relative path under resources/images/ (no extension)
//
// PagedGrid.qml and HubScreen's static category row both wrap their
// Tile delegate in a TileLoader that defines exactly these four
// properties; QML's late-binding model means a caller that forgets
// one fails silently at runtime rather than at build time, so the
// Component.onCompleted check below converts that footgun into a
// loud warning.
Item {
    id: root

    anchors.fill: parent

    // qmllint disable missing-property compiler
    readonly property bool delegateIsSelected: parent.isSelected
    readonly property bool delegateIsFocused: parent.isFocused
    readonly property string delegateName: parent.name
    readonly property string delegateCoverKey: parent.coverKey
    // qmllint enable missing-property compiler

    Component.onCompleted: {
        // Self-check the parent contract. Logs once at construction so
        // a future caller that drops Tile into a non-conforming wrapper
        // sees the failure mode immediately instead of debugging
        // mysteriously empty tiles.
        // qmllint disable missing-property compiler
        if (typeof parent.isSelected !== "boolean"
            || typeof parent.isFocused !== "boolean"
            || typeof parent.name !== "string"
            || typeof parent.coverKey !== "string") {
            console.warn(
                "Tile: parent does not satisfy the delegate contract "
                + "(expected isSelected:bool, isFocused:bool, "
                + "name:string, coverKey:string)")
        }
        // qmllint enable missing-property compiler
    }

    readonly property int _padding: Sizing.pctH(3)
    readonly property int _outlineGap: Sizing.pctH(0.4)
    readonly property int _outlineWidth: Sizing.pctH(0.6)

    readonly property bool _focusedSelection:
        root.delegateIsSelected && root.delegateIsFocused

    // `coverKey` is the relative path under `resources/images/` without
    // extension — `systems/snes`, `categories/Consoles`, etc. The model
    // chooses the subdirectory; Tile is agnostic. Resources.coverUrl is
    // the single source of truth for the qrc layout — see Resources.qml.
    readonly property url _coverSource:
        Resources.coverUrl(root.delegateCoverKey)
    readonly property bool _hasCover: cover.status === Image.Ready

    // Selected tile bumps up a hair so the user can see at a glance
    // which one is current. PagedGrid bumps cellItem.z for the
    // selected slot, so the scaled tile draws on top of its
    // right/bottom neighbours. Gated on `_focusedSelection` so a tile
    // in an unfocused section doesn't compete for the eye with the
    // focused section's selection cue.
    //
    // No `Behavior on scale`: under software rendering, animating
    // two tiles' scale across 120 ms forces a bilinear resample of
    // each decoded cover PNG every frame, on both the outgoing and
    // incoming tile. The focus outline ring is the primary focus
    // cue; the scale bump is supplementary and looks fine snapping
    // instantly. See `docs/qml-gotchas.md` → "Software-renderer
    // animation costs".
    transformOrigin: Item.Center
    scale: root._focusedSelection ? 1.06 : 1.0

    // Tile body. Solid card so the white icon has a high-contrast
    // surface. Always visible — no opacity gating — which is the
    // unified-Tile contract: every grid renders the same shape.
    Rectangle {
        anchors.fill: parent
        radius: Sizing.cornerRadius
        color: Theme.surfaceCard
    }

    // Focus outline ring. Drawn *inside* the card edge so the ring
    // never bleeds past the cell bounds — that's the project standard:
    // borders/outlines stay within their parent rather than overflowing
    // it. Keeps the ring out of PagedGrid's clip rect at the row edges
    // and means callers don't have to reserve bleed room for it. Gated
    // on `_focusedSelection` so only the focused tile in the focused
    // section lights up — keeps multiple tile sections on screen from
    // competing for the eye. Drawn after the card so the border sits on
    // top; the icon padding (`_padding = pctH(3)`) is far larger than
    // the inset (`_outlineGap = pctH(0.4)`), so the ring never overlaps
    // content.
    Rectangle {
        anchors.fill: parent
        anchors.margins: root._outlineGap
        color: "transparent"
        border.color: Theme.textPrimary
        border.width: root._outlineWidth
        // Card radius minus the inset margin keeps the ring concentric
        // with the card corners.
        radius: Sizing.cornerRadius - root._outlineGap
        visible: root._focusedSelection
    }

    // Icon area. Fills the card minus padding on every side, centered
    // horizontally. PreserveAspectFit lets curated logos render at
    // their native aspect inside whichever dimension is the tighter
    // constraint.
    Image {
        id: cover

        anchors {
            top: parent.top
            topMargin: root._padding
            bottom: parent.bottom
            bottomMargin: root._padding
            horizontalCenter: parent.horizontalCenter
        }
        width: parent.width - 2 * root._padding
        source: root._coverSource
        // Pin to the system PNGs' native width (256). A size-dependent
        // binding here would force a re-decode every frame the cell
        // animates — a constant value means QPixmapCache hits once per
        // logo and reuses the decoded pixmap across each layout
        // change. Combined with `smooth: true`, downscaling to the
        // actual cell width is bilinear-filtered on draw.
        sourceSize.width: 256
        fillMode: Image.PreserveAspectFit
        smooth: true
        asynchronous: true
        opacity: root._hasCover ? 1.0 : 0.0
    }

    // Procedural fallback. Sits at the same geometry as the cover and
    // snaps to the cover the moment Image.status hits Ready; the brief
    // Loading window shows the fallback text rather than crossfading.
    // Cache hits skip Loading entirely and snap directly.
    Text {
        anchors.fill: cover
        text: root.delegateName
        font.family: Theme.fontUi
        font.pixelSize: Sizing.fontSize(2.4)
        color: root._focusedSelection ? Theme.textPrimary : Theme.textLabel
        // Wrap (not WordWrap): an unbreakable identifier like
        // `_LongCollectionName_Definitive_Cut.smc` would otherwise
        // render past `width` and bleed out of the tile.
        wrapMode: Text.Wrap
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        renderType: Text.NativeRendering
        opacity: root._hasCover ? 0.0 : 1.0
        clip: true
    }
}
