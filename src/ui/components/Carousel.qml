// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
pragma ComponentBehavior: Bound

import QtQuick
import Zaparoo.Theme

// Horizontal carousel. Up to visibleCovers items centred on
// currentIndex on a flat finite line — the leftmost item sits at a
// negative offset, the rightmost at a positive one. Tiles past the
// visible band hard-cut to invisible — no fade ramp, since
// translucent overlays force per-frame repaint of the busy
// background underneath on Qt Software adaptation (see CLAUDE.md →
// "no fading or scaling of a parent that contains many delegates").
// The hard-cut at the band edge matches the instant-cut idiom used
// everywhere else.
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

            // Flat finite line: no modulo wrap. The leftmost item sits
            // at a negative offset, the rightmost at a positive one.
            property int offset: index - root.currentIndex
            property bool isSelected: offset === 0
            // One slot of slack past the visible band so a tile entering
            // the band already has `visible: true` at its pre-slide x.
            // Without the slack, an entering tile is painted at its
            // OLD (out-of-band) x for one frame as `visible` flips
            // true, then Behavior on x animates inward — the user
            // sees the card briefly clipped against the screen edge
            // and pop into place. With the slack, the slide starts
            // from the off-screen edge and reads as a smooth slot-in.
            // Tiles past band+1 are still hard-cut (no opacity ramp,
            // since translucent overlays force bg repaint per frame
            // — the original justification for this slack was the
            // edge-fade that's since been removed).
            property bool isVisible:
                Math.abs(offset) <= Math.floor(Sizing.visibleCovers / 2) + 1

            width: root.coverWidth
            height: root.coverHeight
            x: root.width / 2 - width / 2 + offset * root.coverSpacing
            y: 0
            z: 10 - Math.abs(offset)
            opacity: isVisible ? 1.0 : 0.0
            visible: isVisible
            // Carousel owns the de-emphasis of unselected neighbours;
            // the unified Tile applies its own selected-bump internally.
            // Compounding 1.0 × Tile's 1.06× lands the focused tile on
            // spec, 0.85× × 1.0 keeps the carousel's "everything but the
            // chosen one shrinks" feel.
            scale: isSelected ? 1.0 : 0.85

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
