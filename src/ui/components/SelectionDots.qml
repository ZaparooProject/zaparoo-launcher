// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
// SPDX-FileCopyrightText: 2026 Callan Barrett
pragma ComponentBehavior: Bound

import QtQuick
import Zaparoo.Theme

// Row of small indicator dots showing which carousel item is selected.
Row {
    id: root

    required property int count
    required property int currentIndex
    required property real rainbowHue

    spacing: Sizing.pctW(2)

    Repeater {
        model: root.count

        Rectangle {
            required property int index

            width: Sizing.pctH(2)
            height: Sizing.pctH(2)
            radius: width / 2
            color: index === root.currentIndex
                ? Qt.hsla(root.rainbowHue, 0.8, 0.6, 1)
                : "#222222"
            border.width: 1
            border.color: index === root.currentIndex ? "white" : "#444444"

            Behavior on color {
                ColorAnimation {
                    duration: 200
                }
            }
        }
    }
}
