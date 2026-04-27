// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0

import QtQuick
import Zaparoo.Theme

// Carousel/grid tile: cover image fills the cell with the procedural
// fallback behind it. While the curated logo is decoding the fallback
// carries the cell; once the logo is ready the fallback fades out and
// the logo fades in, so the tile never flashes between states. The
// selected tile scales up slightly for at-a-glance focus.
//
// Parent contract — Tile must be loaded inside a host that exposes:
//   - isSelected: bool   — true when this tile is the focused selection
//   - isFocused:  bool   — true when the section owning this tile has user focus
//   - name:       string — model display name (drives the procedural fallback)
//   - coverKey:   string — relative path under resources/images/ (no extension)
//
// Carousel.qml and PagedGrid.qml both wrap their Tile delegate in a
// Loader that defines exactly these four properties; QML's late-binding
// model means a caller that forgets one fails silently at runtime
// rather than at build time, so the Component.onCompleted check below
// converts that footgun into a loud warning.
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
        // mysteriously empty tiles. The parent.X reads are the same
        // statically-unknowable shape as the property declarations
        // above, so the same suppression applies.
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

    // `coverKey` is the relative path under `resources/images/` without
    // extension — `systems/snes`, `categories/Consoles`, etc. The model
    // chooses the subdirectory; Tile is agnostic. Resources.coverUrl is
    // the single source of truth for the qrc layout — see Resources.qml.
    readonly property url _coverSource:
        Resources.coverUrl(root.delegateCoverKey)
    readonly property bool _hasCover: cover.status === Image.Ready

    // Selected tiles bump up a hair so the user can see at a glance
    // which one is current. Scale is software-rendering safe: Qt
    // rasterises the scaled item once per frame, no shaders involved.
    // PagedGrid bumps cellItem.z for the selected slot, so the scaled
    // tile draws on top of its right/bottom neighbours.
    transformOrigin: Item.Center
    scale: root.delegateIsSelected ? 1.08 : 1.0

    Behavior on scale {
        NumberAnimation {
            duration: 120
            easing.type: Easing.OutQuad
        }
    }

    // Subtle selection card. Sits behind the fallback text and the
    // cover image so neither the procedural placeholder nor the logo
    // is visually disturbed when it appears. Software-rendering safe:
    // Rectangle.radius is rasterised, no shaders.
    //
    // Sized to the cover's painted bounds (plus padding) so the card
    // hugs whatever aspect the logo has — square cards on system
    // logos, wide rectangles on horizontal category logos. Falls back
    // to the cell when the cover isn't loaded so the procedural text
    // still gets a backdrop. Gated on `delegateIsFocused` so only the
    // focused section shows the card; otherwise both the categories
    // carousel and systems grid would light their selection up at once.
    Rectangle {
        // Card extends `_padding` beyond the cover's painted bounds.
        // The Tile scales to 1.08× when selected, so this padding is
        // also scaled — pctH(3) gives a visible breathing strip even
        // after the scale-up; smaller values made the card visually
        // "kiss" the logo edges.
        readonly property real _padding: Sizing.pctH(3)

        anchors.centerIn: parent
        width: cover.status === Image.Ready
               ? Math.min(parent.width, cover.paintedWidth + 2 * _padding)
               : parent.width
        height: cover.status === Image.Ready
                ? Math.min(parent.height, cover.paintedHeight + 2 * _padding)
                : parent.height
        radius: Sizing.pctH(1.2)
        color: Qt.rgba(1, 1, 1, 0.08)
        opacity: root.delegateIsSelected && root.delegateIsFocused ? 1.0 : 0.0

        Behavior on opacity {
            NumberAnimation {
                duration: 120
                easing.type: Easing.OutQuad
            }
        }
    }

    // Procedural fallback. Sits underneath the cover and fades out as
    // the logo becomes ready, so the wide-aspect logo never lets the
    // fallback bleed through the empty top/bottom letterbox bands.
    Text {
        id: fallback

        anchors.fill: parent
        anchors.leftMargin: Sizing.pctW(0.5)
        anchors.rightMargin: Sizing.pctW(0.5)
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

    Image {
        id: cover

        anchors.fill: parent
        source: root._coverSource
        // Pin to the system PNGs' native width (256). A size-dependent
        // binding here (e.g. `Math.round(root.width * 2)`) forces a
        // re-decode every frame the cell animates, which the Hub's
        // category carousel does whenever focus moves between
        // categories and the systems grid (the cover size
        // shrinks/grows). A constant value means QPixmapCache hits
        // once per logo and reuses the decoded pixmap across the
        // whole transition. Category PNGs ship at 2014 px wide; this
        // also acts as their decode cap so they don't dominate the
        // cache. Combined with `smooth: true`, downscaling to the
        // actual cell width is bilinear-filtered on draw — no
        // jaggies, no decode churn.
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
}
