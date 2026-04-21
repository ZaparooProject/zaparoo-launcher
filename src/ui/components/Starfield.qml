// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
// SPDX-FileCopyrightText: 2026 Callan Barrett
pragma ComponentBehavior: Bound

import QtQuick
import Zaparoo.Theme

// Falling-star background animation.
// Star count scales with resolution to keep performance acceptable.
Item {
    id: root

    Repeater {
        model: root.height > 720 ? 12 : (root.height < 300 ? 8 : 20)

        Rectangle {
            id: star

            property real speed: 5000 + Math.random() * 5000
            property real startY: Math.random() * root.height

            width: Math.max(1, Sizing.pctH(0.6))
            height: width
            color: Qt.hsla(0, 0, 0.5 + Math.random() * 0.3, 1)
            x: Math.random() * root.width
            y: startY

            NumberAnimation on y {
                loops: Animation.Infinite
                from: -5
                to: root.height + 5
                duration: star.speed
            }
        }
    }
}
