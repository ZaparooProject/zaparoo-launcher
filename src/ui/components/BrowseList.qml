// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
pragma ComponentBehavior: Bound

import QtQuick
import Zaparoo.Theme

Item {
    id: root

    required property var model
    property int currentIndex: 0
    property string currentName: ""
    property string currentCoverKey: ""
    readonly property int itemCount: listView.count
    readonly property int rowHeight: Sizing.pctH(6)

    signal itemHovered(int index)
    signal itemClicked(int index)
    signal itemRightClicked(int index)
    signal emptyRightClicked()

    function currentCellRectIn(target: Item): rect {
        if (root.itemCount <= 0)
            return Qt.rect(0, 0, 0, 0)
        const y = (root.currentIndex - listView.contentY / root.rowHeight)
                  * root.rowHeight
        const p = root.mapToItem(target, 0, y)
        return Qt.rect(p.x, p.y, root.width, root.rowHeight)
    }

    clip: true

    onItemCountChanged: {
        if (root.itemCount === 0) {
            root.currentName = ""
            root.currentCoverKey = ""
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        onClicked: root.emptyRightClicked()
    }

    ListView {
        id: listView

        anchors.fill: parent
        model: root.model
        currentIndex: root.currentIndex
        boundsBehavior: Flickable.StopAtBounds
        interactive: false
        spacing: Sizing.pctH(0.7)
        highlightFollowsCurrentItem: false

        onCurrentIndexChanged: {
            if (currentIndex >= 0)
                positionViewAtIndex(currentIndex, ListView.Contain)
        }

        delegate: Item {
            id: row

            required property int index
            required property string name
            required property string coverKey
            required property int favorite

            width: listView.width
            height: root.rowHeight

            readonly property bool selected: row.index === root.currentIndex

            Binding {
                target: root
                property: "currentName"
                when: row.selected
                value: row.name
                restoreMode: Binding.RestoreNone
            }

            Binding {
                target: root
                property: "currentCoverKey"
                when: row.selected
                value: row.coverKey
                restoreMode: Binding.RestoreNone
            }

            Rectangle {
                anchors.fill: parent
                color: row.selected ? Theme.surfaceCard : "transparent"
                radius: Math.max(0, Sizing.cornerRadius / 3)
            }

            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: Sizing.pctW(0.45)
                color: Theme.textPrimary
                visible: row.selected
                radius: Math.max(0, width / 3)
            }

            Text {
                anchors.left: parent.left
                anchors.leftMargin: Sizing.pctW(1.6)
                anchors.right: parent.right
                anchors.rightMargin: row.favorite !== 0
                                     ? Sizing.pctW(5.2)
                                     : Sizing.pctW(1.6)
                anchors.verticalCenter: parent.verticalCenter
                text: row.name
                color: row.selected ? Theme.textPrimary : Theme.textLabel
                font.family: Theme.fontUi
                font.pixelSize: Sizing.fontSize(2.9)
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
                renderType: Text.NativeRendering
            }

            Image {
                anchors.right: parent.right
                anchors.rightMargin: Sizing.pctW(1.6)
                anchors.verticalCenter: parent.verticalCenter
                width: Sizing.pctH(3.2)
                height: width
                source: Resources.iconUrl("Heart")
                sourceSize.width: width
                sourceSize.height: height
                fillMode: Image.PreserveAspectFit
                smooth: true
                asynchronous: false
                visible: row.favorite !== 0
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor

                onEntered: root.itemHovered(row.index)
                onClicked: (mouse) => {
                    if (mouse.button === Qt.RightButton)
                        root.itemRightClicked(row.index)
                    else
                        root.itemClicked(row.index)
                }
            }
        }
    }
}
