// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
// SPDX-FileCopyrightText: 2026 Callan Barrett
pragma ComponentBehavior: Bound

import QtQuick
import Zaparoo.Theme

// Horizontal menu bar at the bottom of the screen.
// Items are highlighted by index when inMenu is true.
Row {
    id: root

    required property bool inMenu
    required property int menuIndex
    required property real rainbowHue
    required property list<string> menuItems

    spacing: Sizing.pctW(3)

    Repeater {
        model: root.menuItems

        Rectangle {
            id: menuItem

            required property int index
            required property string modelData

            width: Sizing.pctW(22)
            height: Sizing.pctH(7)
            color: root.inMenu && menuItem.index === root.menuIndex
                ? Theme.bgPanel
                : "transparent"
            border.width: 1
            border.color: root.inMenu && menuItem.index === root.menuIndex
                ? Qt.hsla(root.rainbowHue, 0.9, 0.6, 1)
                : Theme.borderDim

            Behavior on border.color {
                ColorAnimation {
                    duration: 200
                }
            }
            Behavior on color {
                ColorAnimation {
                    duration: 200
                }
            }

            Text {
                anchors.centerIn: parent
                text: menuItem.modelData
                font.family: Theme.fontRetro
                font.pixelSize: Sizing.fontSize(3)
                color: root.inMenu && menuItem.index === root.menuIndex
                    ? Theme.textPrimary
                    : Theme.textMuted

                Behavior on color {
                    ColorAnimation {
                        duration: 200
                    }
                }
            }
        }
    }
}
