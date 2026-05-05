// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0

import QtQuick
import Zaparoo.Theme

Item {
    id: root

    property string title: ""
    property string coverKey: ""

    Item {
        id: imageSlot

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: parent.height * 0.5

        Image {
            id: cover
            anchors.fill: parent
            source: Resources.coverUrl(root.coverKey)
            fillMode: Image.PreserveAspectFit
            sourceSize.width: 512
            smooth: true
            asynchronous: true
            visible: root.coverKey !== "" && status === Image.Ready
        }
    }

    Text {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: imageSlot.bottom
        anchors.topMargin: Sizing.pctH(3)
        text: root.title
        color: Theme.textPrimary
        font.family: Theme.fontUi
        font.pixelSize: Sizing.fontSize(3.2)
        wrapMode: Text.Wrap
        maximumLineCount: 3
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignHCenter
        renderType: Text.NativeRendering
    }
}
