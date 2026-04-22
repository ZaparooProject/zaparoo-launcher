// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
// SPDX-FileCopyrightText: 2026 Callan Barrett
pragma ComponentBehavior: Bound

import QtQuick
import Zaparoo.Theme

// Horizontal carousel. Displays up to visibleCovers items centred on currentIndex.
Item {
    id: root

    required property var model
    required property Component delegate
    required property url placeholderCover
    required property real rainbowHue

    property int currentIndex: 0
    readonly property int itemCount: itemRepeater.count

    readonly property int coverWidth: Sizing.pctH(30)
    readonly property int coverHeight: Sizing.pctH(45)
    readonly property int coverSpacing: Sizing.pctH(35)

    Repeater {
        id: itemRepeater

        model: root.model

        Item {
            id: coverItem

            required property int index
            required property string name

            property int offset: {
                if (root.itemCount === 0)
                    return 0
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

            Loader {
                anchors.fill: parent
                sourceComponent: root.delegate
                property bool isSelected: coverItem.isSelected
                property real rainbowHue: root.rainbowHue
                property url placeholderCover: root.placeholderCover
                property string name: coverItem.name
            }
        }
    }
}
