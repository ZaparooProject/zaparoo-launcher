// Zaparoo Launcher
// Copyright (c) 2026 The Zaparoo Project Contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0

import QtQuick
import Zaparoo.Theme

Item {
    id: root

    anchors.fill: parent

    // qmllint disable missing-property compiler
    readonly property bool delegateIsSelected: parent.isSelected
    readonly property string delegateName: parent.name
    // qmllint enable missing-property compiler

    Rectangle {
        anchors.fill: parent
        anchors.margins: 0
        color: "transparent"
        border.width: Math.max(1, Sizing.pctH(0.5))
        border.color: root.delegateIsSelected ? Theme.accent : Theme.borderMid
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.bgMid

        Text {
            anchors.centerIn: parent
            width: parent.width - Sizing.pctH(2)
            text: root.delegateName
            font.family: Theme.fontRetro
            font.pixelSize: Sizing.fontSize(3)
            color: root.delegateIsSelected ? Theme.textPrimary : Theme.textDim
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            renderType: Text.NativeRendering
        }
    }
}
