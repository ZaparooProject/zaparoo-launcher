// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
pragma ComponentBehavior: Bound

import QtQuick
import Zaparoo.Theme

Item {
    id: root

    property string title: ""
    property string coverKey: ""
    property string description: ""
    property bool showDescription: true
    property bool showTitle: true
    property string detailTags: ""
    property bool canPreviousImage: false
    property bool canNextImage: false

    readonly property int _carouselGutter: (canPreviousImage || canNextImage) ? Sizing.pctW(4) : 0

    Item {
        id: imageSlot

        anchors.left: parent.left
        anchors.leftMargin: root._carouselGutter
        anchors.right: parent.right
        anchors.rightMargin: root._carouselGutter
        anchors.top: parent.top
        height: Sizing.px(parent.height * 0.5)

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
        visible: root.showTitle && root.title !== ""
    }

    Column {
        id: tagTable

        visible: root.detailTags !== ""
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: imageSlot.bottom
        anchors.topMargin: Sizing.pctH(3)
        anchors.bottom: parent.bottom
        spacing: Sizing.pctH(0.8)
        clip: true

        Repeater {
            model: root.detailTags === "" ? [] : root.detailTags.split("\n")

            delegate: Item {
                id: tagRow

                required property string modelData

                width: tagTable.width
                height: Math.max(Sizing.pctH(3), tagValue.paintedHeight)

                readonly property list<string> parts: modelData.split("\t")
                readonly property bool isFilename: parts.length > 0 && parts[0] === "Filename"

                Text {
                    id: tagType

                    anchors.left: parent.left
                    anchors.top: parent.top
                    width: Sizing.pctW(9)
                    text: tagRow.parts.length > 0 ? tagRow.parts[0] : ""
                    color: Theme.textLabel
                    font.family: Theme.fontUi
                    font.pixelSize: Sizing.fontSize(2.2)
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignRight
                    renderType: Text.NativeRendering
                }

                Text {
                    id: tagValue

                    anchors.left: tagType.right
                    anchors.leftMargin: Sizing.pctW(1.4)
                    anchors.right: parent.right
                    anchors.top: parent.top
                    text: tagRow.parts.length > 1 ? tagRow.parts[1] : ""
                    color: Theme.textPrimary
                    font.family: Theme.fontUi
                    font.pixelSize: Sizing.fontSize(2.2)
                    wrapMode: Text.Wrap
                    maximumLineCount: tagRow.isFilename ? 8 : 2
                    elide: tagRow.isFilename ? Text.ElideNone : Text.ElideRight
                    horizontalAlignment: Text.AlignLeft
                    renderType: Text.NativeRendering
                }
            }
        }
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
        font.pixelSize: Sizing.fontSize(2.2)
        wrapMode: Text.Wrap
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignLeft
        verticalAlignment: Text.AlignTop
        renderType: Text.NativeRendering
        visible: root.showDescription && root.description !== ""
    }
}
