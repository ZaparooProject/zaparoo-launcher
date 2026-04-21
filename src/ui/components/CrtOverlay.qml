// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
// SPDX-FileCopyrightText: 2026 Callan Barrett
pragma ComponentBehavior: Bound

import QtQuick

// Software-rendered CRT scanline overlay.
// Darkens every other horizontal line at 20% opacity.
// Uses a Repeater — avoid enabling this at high resolutions when FPS is low.
Item {
    id: root

    Repeater {
        model: Math.ceil(root.height / 2)

        Rectangle {
            required property int index

            x: 0
            y: index * 2
            width: root.width
            height: 1
            color: "#000000"
            opacity: 0.2
        }
    }
}
