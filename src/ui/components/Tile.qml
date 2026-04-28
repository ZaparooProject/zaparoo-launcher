// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0

import QtQuick
import Zaparoo.Theme

// Unified grid tile. Solid card with a centered icon area on top, an
// always-visible label below, and a white outline ring around the card
// when this tile is the focused selection. Used by every grid in the
// launcher — categories carousel, systems grid, games grid — so the
// vocabulary is identical across screens.
//
// Parent contract — Tile must be loaded inside a host that exposes:
//   - isSelected: bool   — true when this tile is the focused selection
//   - isFocused:  bool   — true when the section owning this tile has user focus
//   - name:       string — model display name (drives the label and the
//                          procedural fallback)
//   - coverKey:   string — relative path under resources/images/ (no extension)
//
// Carousel.qml and PagedGrid.qml both wrap their Tile delegate in a
// TileLoader that defines exactly these four properties; QML's late-
// binding model means a caller that forgets one fails silently at
// runtime rather than at build time, so the Component.onCompleted
// check below converts that footgun into a loud warning.
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

    readonly property int _gap: Sizing.pctH(1)
    readonly property int _padding: Sizing.pctH(3)
    readonly property int _labelHeight:
        Sizing.fontSize(2.4) + Sizing.pctH(0.8)
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
    // which one is current. Software-rendering safe: Qt rasterises the
    // scaled item once per frame, no shaders involved. PagedGrid bumps
    // cellItem.z for the selected slot, so the scaled tile draws on top
    // of its right/bottom neighbours.
    transformOrigin: Item.Center
    scale: root.delegateIsSelected ? 1.06 : 1.0

    Behavior on scale {
        NumberAnimation {
            duration: 120
            easing.type: Easing.OutQuad
        }
    }

    // Focus outline ring. Sits *outside* the card with a thin gap so
    // the outline reads as a separate ring rather than a thick border
    // on the card. Gated on `_focusedSelection` so only the focused
    // tile in the focused section lights up — keeps two grids on
    // screen (carousel + grid) from competing for the eye.
    Rectangle {
        anchors.centerIn: parent
        width: parent.width + 2 * (root._outlineGap + root._outlineWidth)
        height: parent.height + 2 * (root._outlineGap + root._outlineWidth)
        color: "transparent"
        border.color: Theme.textPrimary
        border.width: root._outlineWidth
        radius: Sizing.pctH(1.6)
        visible: root._focusedSelection
    }

    // Tile body. Solid card so the white icon + label have a high-
    // contrast surface. Always visible — no opacity gating — which is
    // the unified-Tile contract: every grid renders the same shape.
    Rectangle {
        anchors.fill: parent
        radius: Sizing.pctH(1.2)
        color: Theme.surfaceCard
    }

    // Icon area. Spans from the top padding down to just above the
    // label, centered horizontally. PreserveAspectFit lets curated
    // logos render at their native aspect inside whichever dimension
    // is the tighter constraint.
    Image {
        id: cover

        anchors {
            top: parent.top
            topMargin: root._padding
            bottom: label.top
            bottomMargin: root._gap
            horizontalCenter: parent.horizontalCenter
        }
        width: parent.width - 2 * root._padding
        source: root._coverSource
        // Pin to the system PNGs' native width (256). A size-dependent
        // binding here would force a re-decode every frame the cell
        // animates — a constant value means QPixmapCache hits once per
        // logo and reuses the decoded pixmap across the whole
        // transition. Combined with `smooth: true`, downscaling to the
        // actual cell width is bilinear-filtered on draw.
        sourceSize.width: 256
        fillMode: Image.PreserveAspectFit
        smooth: true
        asynchronous: true
        opacity: root._hasCover ? 1.0 : 0.0

        Behavior on opacity {
            NumberAnimation {
                duration: 150
            }
        }
    }

    // Procedural fallback. Sits at the same geometry as the cover and
    // fades out as the curated logo becomes ready, so the cell never
    // flashes between states.
    Text {
        anchors.fill: cover
        text: root.delegateName
        font.family: Theme.fontUi
        font.pixelSize: Sizing.fontSize(2.4)
        color: root.delegateIsSelected ? Theme.textPrimary : Theme.textDim
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        renderType: Text.NativeRendering
        opacity: root._hasCover ? 0.0 : 1.0

        Behavior on opacity {
            NumberAnimation {
                duration: 150
            }
        }
    }

    // Label. Always visible. Selection cue is colour + weight only —
    // no scale, no underline — so labels line up at a uniform baseline
    // across the row.
    Text {
        id: label

        anchors {
            bottom: parent.bottom
            bottomMargin: root._padding
            horizontalCenter: parent.horizontalCenter
        }
        width: parent.width - 2 * root._padding
        height: root._labelHeight
        text: root.delegateName
        font.family: Theme.fontUi
        font.pixelSize: Sizing.fontSize(2.4)
        font.weight: root._focusedSelection ? Font.Medium : Font.Normal
        color: root._focusedSelection ? Theme.textPrimary : Theme.textDim
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        renderType: Text.NativeRendering
    }
}
