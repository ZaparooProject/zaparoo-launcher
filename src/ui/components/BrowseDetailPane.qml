// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0

import QtQuick
import Zaparoo.Theme

Item {
    id: root

    property string title: ""
    property string coverKey: ""
    property string description: ""
    property bool canPreviousImage: false
    property bool canNextImage: false

    readonly property int _carouselGutter:
        (canPreviousImage || canNextImage) ? Sizing.pctW(4) : 0

    Item {
        id: imageSlot

        anchors.left: parent.left
        anchors.leftMargin: root._carouselGutter
        anchors.right: parent.right
        anchors.rightMargin: root._carouselGutter
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

    Image {
        source: Resources.iconUrl("NavLeft")
        width: Sizing.pctH(4)
        height: width
        anchors.left: parent.left
        anchors.verticalCenter: imageSlot.verticalCenter
        fillMode: Image.PreserveAspectFit
        smooth: true
        visible: root.canPreviousImage
    }

    Image {
        source: Resources.iconUrl("NavRight")
        width: Sizing.pctH(4)
        height: width
        anchors.right: parent.right
        anchors.verticalCenter: imageSlot.verticalCenter
        fillMode: Image.PreserveAspectFit
        smooth: true
        visible: root.canNextImage
    }

    Text {
        id: titleText

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

    Text {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: titleText.bottom
        anchors.topMargin: Sizing.pctH(2)
        anchors.bottom: parent.bottom
        text: root.description
        color: Theme.textLabel
        font.family: Theme.fontUi
        font.pixelSize: Sizing.fontSize(2.1)
        wrapMode: Text.Wrap
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignLeft
        verticalAlignment: Text.AlignTop
        renderType: Text.NativeRendering
        visible: root.description !== ""
    }
}
