// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0

import QtQuick
import Zaparoo.Theme

// Three-slot bottom band shared by the Systems and Games screens. Owns
// layout only — callers compute and pass `currentPage`, `totalPages`,
// `loadingMore`, and `totalText` from their own model. Each slot is
// capped at one third of the parent width with `elide: ElideRight` so
// long strings (3-digit page counts, 5-digit file totals, translated
// "Loading more…") can't collide on a 240p MiSTer screen.
//
// Slots:
//   left   — "Loading more…" cue (visible while `loadingMore`)
//   center — "Page N / M" counter (visible when `totalPages > 1`)
//   right  — total-count badge (visible when `totalText !== ""`)
//
// Software-rendering safe: only Item + Text, no transforms, no shaders.
Item {
    id: status

    property int currentPage: 0      // 0-indexed; displayed as N+1
    property int totalPages: 1
    property bool loadingMore: false
    property string totalText: ""    // formatted; empty hides the slot

    readonly property real _slotWidth: status.width / 3
    readonly property real _slotMargin: Sizing.pctW(5)

    Text {
        id: loadingMoreCue
        visible: status.loadingMore
        anchors.left: parent.left
        anchors.leftMargin: status._slotMargin
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Sizing.pctH(0.8)
        width: status._slotWidth - status._slotMargin
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignLeft
        text: qsTr("Loading more…")
        font.family: Theme.fontUi
        font.pixelSize: Sizing.fontSize(1.6)
        color: Theme.textDim
        renderType: Text.NativeRendering
    }

    Text {
        id: pageCounter
        visible: status.totalPages > 1
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Sizing.pctH(0.5)
        width: status._slotWidth
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignHCenter
        text: qsTr("Page %1 / %2")
                .arg(status.currentPage + 1)
                .arg(status.totalPages)
        font.family: Theme.fontUi
        font.pixelSize: Sizing.fontSize(2.4)
        color: Theme.textDim
        renderType: Text.NativeRendering
    }

    Text {
        id: totalBadge
        visible: status.totalText !== ""
        anchors.right: parent.right
        anchors.rightMargin: status._slotMargin
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Sizing.pctH(0.8)
        width: status._slotWidth - status._slotMargin
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignRight
        text: status.totalText
        font.family: Theme.fontUi
        font.pixelSize: Sizing.fontSize(1.6)
        color: Theme.textDim
        renderType: Text.NativeRendering
    }
}
