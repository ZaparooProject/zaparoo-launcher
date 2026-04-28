// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
pragma ComponentBehavior: Bound

import QtQuick
import Zaparoo.Theme

// Horizontal carousel. Items lay out as a flat finite line centered on
// currentIndex — no wrap. Each tile fades its own opacity based on its
// horizontal center's distance from the carousel edges, so background
// content (logo, status, bg pattern) shows through cleanly instead of
// being painted over by a solid edge gradient.
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

    // 0..1, multiplies into delegates that opt into the hub-style
    // activation fade. Tiles that don't care just ignore it.
    property real imagesOpacity: 1.0

    // Width of the per-tile fade band on each edge. A tile whose center
    // is fadeWidth away from the carousel edge is fully visible; at the
    // edge itself it's fully transparent. Linear ramp in between.
    property int edgeFadeWidth: Sizing.pctW(8)

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

            // Flat finite line: no modulo wrap. The leftmost item sits at
            // a negative offset, the rightmost at a positive one, and
            // each tile self-fades as it approaches the carousel edge.
            property int offset: index - root.currentIndex
            property bool isSelected: offset === 0
            // +1 slot of padding past the visible band so a tile sliding
            // out has room to ramp its alpha to 0 before being culled.
            // Without the slack, exiting tiles would hard-cut.
            property bool isVisible:
                Math.abs(offset) <= Math.floor(Sizing.visibleCovers / 2) + 1

            width: root.coverWidth
            height: root.coverHeight
            x: root.width / 2 - width / 2 + offset * root.coverSpacing
            y: 0
            z: 10 - Math.abs(offset)
            // Per-tile alpha fade. Reads the live `x` so the binding
            // re-evaluates every frame as the Behavior animates the tile
            // across the band — exiting tiles dissolve smoothly instead
            // of relying on a solid overlay.
            opacity: {
                if (!isVisible)
                    return 0
                if (root.edgeFadeWidth <= 0)
                    return 1
                const cx = x + width / 2
                const dist = Math.min(cx, root.width - cx)
                return Math.max(0, Math.min(1, dist / root.edgeFadeWidth))
            }
            visible: isVisible
            // Lerp toward 1.0 as imagesOpacity drops so the activated strip
            // (imagesOpacity = 0) lands at scale 1.0 across every tile —
            // that's what lines the labels up at a uniform baseline. In
            // focused mode (imagesOpacity = 1) the selected tile shows its
            // full 1.1× zoom and unselected tiles their 0.85×.
            scale: 1.0 + ((isSelected ? 0.1 : -0.15) * root.imagesOpacity)

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
                imagesOpacity: root.imagesOpacity
            }
        }
    }
}
