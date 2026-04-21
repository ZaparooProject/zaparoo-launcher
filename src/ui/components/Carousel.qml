// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
// SPDX-FileCopyrightText: 2026 Callan Barrett
pragma ComponentBehavior: Bound

import QtQuick
import Zaparoo.Theme

// Horizontal cover-art carousel.
// Displays up to visibleCovers items centred on currentIndex.
Item {
    id: root

    required property list<url> coverImages
    required property real rainbowHue

    property int currentIndex: 0
    readonly property int itemCount: coverImages.length

    readonly property int coverWidth: Sizing.pctH(30)
    readonly property int coverHeight: Sizing.pctH(45)
    readonly property int coverSpacing: Sizing.pctH(35)

    Repeater {
        model: root.itemCount

        Item {
            id: coverItem

            required property int index

            property int offset: {
                var diff = index - root.currentIndex
                if (diff > root.itemCount / 2)
                    diff -= root.itemCount
                if (diff < -root.itemCount / 2)
                    diff += root.itemCount
                return diff
            }
            property bool isSelected: offset === 0
            property bool isVisible: Math.abs(offset) <= Math.floor(Sizing.visibleCovers / 2)

            width: root.coverWidth
            height: root.coverHeight
            x: root.width / 2 - width / 2 + offset * root.coverSpacing
            y: 0
            z: 10 - Math.abs(offset)
            opacity: isVisible ? (1.0 - Math.abs(offset) * 0.3) : 0
            scale: isSelected ? 1.1 : 0.85
            visible: isVisible

            Behavior on x {
                NumberAnimation {
                    duration: 150
                }
            }
            Behavior on scale {
                NumberAnimation {
                    duration: 150
                }
            }

            Rectangle {
                anchors.fill: parent
                anchors.margins: -Sizing.pctH(0.8)
                color: "transparent"
                border.width: Math.max(1, Sizing.pctH(0.5))
                border.color: coverItem.isSelected
                    ? Qt.hsla(root.rainbowHue, 0.9, 0.6, 1)
                    : Theme.borderMid
            }

            Rectangle {
                anchors.fill: parent
                color: Theme.bgMid

                Image {
                    anchors.fill: parent
                    anchors.margins: 1
                    source: root.coverImages[coverItem.index]
                    fillMode: Image.PreserveAspectFit
                    smooth: false
                    cache: true
                }
            }
        }
    }
}
