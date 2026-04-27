// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
pragma ComponentBehavior: Bound

import QtQuick
import Zaparoo.Theme

// Horizontal carousel. Displays up to visibleCovers items centred on currentIndex.
Item {
    id: root

    required property var model
    required property Component delegate

    property int currentIndex: 0
    readonly property int itemCount: itemRepeater.count

    // Whether this section currently owns user focus. Tile uses this to
    // gate the selection card so only one section shows the focus cue
    // at a time when the hub has both a carousel and a grid on screen.
    // Defaults to true so call sites that don't care (games screen)
    // keep working untouched.
    property bool focused: true

    property int coverWidth: Sizing.pctH(30)
    property int coverHeight: Sizing.pctH(45)
    property int coverSpacing: Sizing.pctH(35)

    Repeater {
        id: itemRepeater

        model: root.model

        Item {
            id: coverItem

            required property int index
            required property string name
            // Every Browse model exposes a `coverKey` role — the relative
            // path under `resources/images/` without extension (e.g.
            // `systems/snes`, `categories/Consoles`). Tile resolves an
            // embedded cover from the key, or falls through to the
            // procedural fallback when no PNG matches.
            required property string coverKey

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
            opacity: isVisible ? 1.0 : 0
            scale: isSelected ? 1.1 : 0.85
            visible: isVisible

            Behavior on x {
                enabled: coverItem.isVisible
                NumberAnimation {
                    duration: 150
                }
            }
            Behavior on scale {
                enabled: coverItem.isVisible
                NumberAnimation {
                    duration: 150
                }
            }

            TileLoader {
                anchors.fill: parent
                sourceComponent: root.delegate
                isSelected: coverItem.isSelected
                isFocused: root.focused
                name: coverItem.name
                coverKey: coverItem.coverKey
            }
        }
    }
}
