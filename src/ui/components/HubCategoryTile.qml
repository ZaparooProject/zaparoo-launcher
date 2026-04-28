// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0

import QtQuick
import Zaparoo.Theme

// Hub categories tile: rounded card with a white icon on top and a
// label below. A thick white outline appears around the entire card
// when this tile is the focused selection. In activated mode (compact
// strip while the systems grid is showing) the card, icon, and outline
// all fade to 0 — only the labels remain, baseline-aligned across all
// tiles, with the focused category surfacing via bold + textPrimary
// and the rest in textDim.
//
// Parent contract — must be loaded inside a host that exposes:
//   - isSelected:    bool   — true when this tile is the focused selection
//   - isFocused:     bool   — true when the section owning this tile has user focus
//   - name:          string — model display name (the visible label)
//   - coverKey:      string — relative path under resources/images/ (no extension)
//   - imagesOpacity: real   — 0..1, drives the activation fade of bg/icon/outline
Item {
    id: root

    anchors.fill: parent

    // qmllint disable missing-property compiler
    readonly property bool delegateIsSelected: parent.isSelected
    readonly property bool delegateIsFocused: parent.isFocused
    readonly property string delegateName: parent.name
    readonly property string delegateCoverKey: parent.coverKey
    readonly property real delegateImagesOpacity: parent.imagesOpacity
    // qmllint enable missing-property compiler

    Component.onCompleted: {
        // qmllint disable missing-property compiler
        if (typeof parent.isSelected !== "boolean"
            || typeof parent.isFocused !== "boolean"
            || typeof parent.name !== "string"
            || typeof parent.coverKey !== "string"
            || typeof parent.imagesOpacity !== "number") {
            console.warn(
                "HubCategoryTile: parent does not satisfy the delegate contract "
                + "(expected isSelected:bool, isFocused:bool, name:string, "
                + "coverKey:string, imagesOpacity:real)")
        }
        // qmllint enable missing-property compiler
    }

    readonly property int _gap: Sizing.pctH(1)
    readonly property int _labelHeight: Sizing.fontSize(2.4) + Sizing.pctH(0.8)
    readonly property int _padding: Sizing.pctH(3)
    readonly property int _outlineGap: Sizing.pctH(0.4)
    readonly property int _outlineWidth: Sizing.pctH(0.6)

    // Focus outline. Sits *outside* the card with a thin gap so the
    // outline reads as a separate ring rather than a thick border on
    // the card. Opacity tracks imagesOpacity so it fades in lockstep
    // with the card during the 250 ms section flip; the
    // delegateIsSelected gate keeps it on the focused tile only.
    Rectangle {
        id: focusOutline
        anchors.centerIn: parent
        width: parent.width + 2 * (root._outlineGap + root._outlineWidth)
        height: parent.height + 2 * (root._outlineGap + root._outlineWidth)
        color: "transparent"
        border.color: Theme.textPrimary
        border.width: root._outlineWidth
        radius: Sizing.pctH(1.6)
        opacity: root.delegateIsSelected
                 ? root.delegateImagesOpacity : 0.0
        visible: opacity > 0
    }

    // Tile body. Solid card so the white icon + label have a high-
    // contrast surface. Fades with imagesOpacity so the activated
    // strip leaves only the labels.
    Rectangle {
        id: tileBg
        anchors.fill: parent
        radius: Sizing.pctH(1.2)
        color: Theme.surfaceCard
        opacity: root.delegateImagesOpacity
        visible: opacity > 0
    }

    // Icon. Fills the area between the top padding and the label,
    // centered horizontally. PreserveAspectFit means the 512×512
    // silhouette PNG renders as a centered square inside whichever
    // dimension is the tighter constraint.
    Image {
        id: icon
        anchors {
            top: parent.top
            topMargin: root._padding
            bottom: label.top
            bottomMargin: root._gap
            horizontalCenter: parent.horizontalCenter
        }
        width: parent.width - 2 * root._padding
        source: Resources.coverUrl(root.delegateCoverKey)
        sourceSize.width: 256
        fillMode: Image.PreserveAspectFit
        smooth: true
        asynchronous: true
        opacity: root.delegateImagesOpacity
        visible: opacity > 0
    }

    // Label. Always visible. Selection cue is colour + weight only —
    // no scale, no underline — so the labels line up at a uniform
    // baseline in the activated strip.
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
        font.weight: root.delegateIsSelected ? Font.Medium : Font.Normal
        color: root.delegateIsSelected ? Theme.textPrimary : Theme.textDim
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        renderType: Text.NativeRendering
    }
}
