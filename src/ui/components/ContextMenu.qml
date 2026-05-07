// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import Zaparoo.Theme

// `entries` is a `var` array of plain JS objects (`{ id, label }`). The
// AOT compiler can't infer the shape of `var`, so every binding that
// reads `entries.length` or `modelData.label` falls back to the JS
// interpreter and trips the compiler category. Suppress file-wide.
// qmllint disable compiler

// Software-rendering safe contextual menu. It positions itself next to an
// anchor rectangle and clamps to the window bounds so edge tiles never push
// the menu off-screen. The scrim is a single `Shape` with two subpaths and
// `OddEvenFill`: an outer full-window rect and an inner rounded rect that
// punches a hole over `anchorRect`, so the anchored tile stays bright with
// rounded corners that match the tile's own radius. A full-screen scrim
// would defeat the "this menu is about *that* tile" affordance, and four
// rectangular bands left a square cutout around the rounded tile corners.
//
// `Shape` is software-renderer safe — Qt's docs guarantee the software
// adaptation paints `Shape` via `QPainter::fillPath()` (no scenegraph
// shaders). Path triangulation is one-shot per `anchorRect` change, on
// the CPU during the polishing phase, so the steady-state cost is just
// the QPainter fill — same family of work as the four `Rectangle` bands
// it replaces.
Item {
    id: menu

    property bool open: false
    property rect anchorRect: Qt.rect(0, 0, 0, 0)
    // Each entry is `{ id: string, label: string }`. `id` is the dispatch
    // key the router switches on (e.g. "launch_game", "qr_code"); `label`
    // is the localized text. Position-keyed dispatch was a footgun —
    // dynamic per-owner menus silently re-shuffled the index/action map.
    property var entries: []
    property int currentIndex: 0

    signal accepted(string id)
    signal closeRequested()

    readonly property int margin: Sizing.pctH(2)
    readonly property int gap: Sizing.pctW(1.2)
    readonly property int rowHeight: Sizing.pctH(6)
    readonly property int rowSpacing: Sizing.pctH(1)
    readonly property int horizontalPadding: Sizing.pctW(2)
    readonly property int panelWidth:
        Math.min(Math.max(Sizing.pctW(26), Sizing.pctH(44)),
                 Math.max(0, width - 2 * margin))
    // Top/bottom margins inside the panel are sized to the panel
    // radius so a focused row's accent ring never intersects the
    // rounded corners — see the panel `Rectangle` below.
    readonly property int panelRadius: Sizing.cornerRadius / 2
    readonly property int panelHeight:
        Math.min(entries.length * rowHeight
                 + Math.max(0, entries.length - 1) * rowSpacing
                 + 2 * panelRadius,
                 Math.max(0, height - 2 * margin))
    readonly property bool preferRight:
        anchorRect.x + anchorRect.width + gap + panelWidth <= width - margin
    readonly property int preferredX:
        preferRight
        ? anchorRect.x + anchorRect.width + gap
        : anchorRect.x - gap - panelWidth
    readonly property int preferredY:
        anchorRect.y + Math.floor((anchorRect.height - panelHeight) / 2)

    visible: open
    enabled: visible
    anchors.fill: parent
    z: 250

    onOpenChanged: {
        if (open)
            currentIndex = 0
    }

    function move(delta: int): void {
        if (menu.entries.length <= 0)
            return
        menu.currentIndex =
            ((menu.currentIndex + delta) % menu.entries.length + menu.entries.length)
            % menu.entries.length
    }

    function handleAction(action: string): void {
        if (action === "up")
            menu.move(-1)
        else if (action === "down")
            menu.move(1)
        else if (action === "accept") {
            if (menu.currentIndex >= 0 && menu.currentIndex < menu.entries.length)
                menu.accepted(menu.entries[menu.currentIndex].id)
        }
        else if (action === "cancel" || action === "write_card")
            menu.closeRequested()
    }

    // Catches dismiss-clicks on the dimmed area around the anchor.
    // Sits beneath the scrim and the panel; per-row MouseAreas inside
    // the panel win for clicks on rows because the panel is declared
    // after this MouseArea, so the panel subtree sits on top in
    // z-order. Clicks on the punched-through anchor area also hit
    // this MouseArea (the scrim cutout has no fill there) and close
    // the menu. Clicks inside the panel chrome (top/bottom radius
    // padding, side margins, row spacing) are filtered out by the
    // bounding-rect check so a stray press on padding doesn't dismiss.
    //
    // Swallows hover and every mouse button so neither hover events
    // nor right-clicks bleed through to the underlying grid while the
    // menu is open. Without `hoverEnabled` and `Qt.AllButtons` the
    // grid below would highlight tiles under the scrim and a right
    // click on the dim area would land on the grid's context handler.
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.AllButtons
        onClicked: (mouse) => {
            if (mouse.x < panel.x || mouse.y < panel.y
                || mouse.x > panel.x + panel.width
                || mouse.y > panel.y + panel.height)
                menu.closeRequested()
        }
    }

    // Scrim with a rounded cutout over `anchorRect`. Two subpaths on
    // one `ShapePath` with `OddEvenFill`: the outer rect fills the whole
    // window, the inner rounded-rect subtracts so the anchor area stays
    // bright. The cutout radius matches `Sizing.cornerRadius` (the same
    // token tile cards use) so the cutout edge and the tile edge sit
    // concentric — no scrim peeking through at the corners.
    //
    // No stroke (the cutout edge meets the bright tile cleanly without
    // a bordering line). Path coords are in the Shape's local space,
    // which equals the menu's local space because the Shape fills it.
    Shape {
        id: scrim

        anchors.fill: parent
        // Default `Shape.UnknownRenderer` lets Qt pick the right backend
        // per Qt Quick scenegraph: `SoftwareRenderer` (QPainter) on
        // MiSTer's software adaptation, `CurveRenderer`/`GeometryRenderer`
        // on a hardware backend. Don't pin it — pinning to
        // `SoftwareRenderer` on a GL/RHI backend forces the slow path
        // for no reason.

        readonly property real _cutoutRadius: Math.min(
            Sizing.cornerRadius,
            Math.min(menu.anchorRect.width, menu.anchorRect.height) / 2)

        ShapePath {
            strokeWidth: -1     // -1 = no stroke
            fillColor: Theme.scrim
            fillRule: ShapePath.OddEvenFill

            // Outer rect (subpath 1) — the full menu area.
            startX: 0
            startY: 0
            PathLine { x: scrim.width; y: 0 }
            PathLine { x: scrim.width; y: scrim.height }
            PathLine { x: 0; y: scrim.height }
            PathLine { x: 0; y: 0 }

            // Inner rounded rect (subpath 2) — punches the hole. Walk
            // the rectangle clockwise from the top edge, with PathArc
            // segments rounding each corner at `_cutoutRadius`.
            PathMove {
                x: menu.anchorRect.x + scrim._cutoutRadius
                y: menu.anchorRect.y
            }
            PathLine {
                x: menu.anchorRect.x + menu.anchorRect.width - scrim._cutoutRadius
                y: menu.anchorRect.y
            }
            PathArc {
                x: menu.anchorRect.x + menu.anchorRect.width
                y: menu.anchorRect.y + scrim._cutoutRadius
                radiusX: scrim._cutoutRadius
                radiusY: scrim._cutoutRadius
            }
            PathLine {
                x: menu.anchorRect.x + menu.anchorRect.width
                y: menu.anchorRect.y + menu.anchorRect.height - scrim._cutoutRadius
            }
            PathArc {
                x: menu.anchorRect.x + menu.anchorRect.width - scrim._cutoutRadius
                y: menu.anchorRect.y + menu.anchorRect.height
                radiusX: scrim._cutoutRadius
                radiusY: scrim._cutoutRadius
            }
            PathLine {
                x: menu.anchorRect.x + scrim._cutoutRadius
                y: menu.anchorRect.y + menu.anchorRect.height
            }
            PathArc {
                x: menu.anchorRect.x
                y: menu.anchorRect.y + menu.anchorRect.height - scrim._cutoutRadius
                radiusX: scrim._cutoutRadius
                radiusY: scrim._cutoutRadius
            }
            PathLine {
                x: menu.anchorRect.x
                y: menu.anchorRect.y + scrim._cutoutRadius
            }
            PathArc {
                x: menu.anchorRect.x + scrim._cutoutRadius
                y: menu.anchorRect.y
                radiusX: scrim._cutoutRadius
                radiusY: scrim._cutoutRadius
            }
        }
    }

    Rectangle {
        id: panel

        x: Math.max(menu.margin,
                    Math.min(menu.preferredX, menu.width - menu.margin - menu.panelWidth))
        y: Math.max(menu.margin,
                    Math.min(menu.preferredY, menu.height - menu.margin - menu.panelHeight))
        width: menu.panelWidth
        height: menu.panelHeight
        color: Theme.bgPanel
        radius: menu.panelRadius

        Column {
            anchors.fill: parent
            anchors.topMargin: menu.panelRadius
            anchors.bottomMargin: menu.panelRadius
            anchors.leftMargin: Sizing.pctW(1)
            anchors.rightMargin: Sizing.pctW(1)
            spacing: menu.rowSpacing

            Repeater {
                model: menu.entries

                Rectangle {
                    id: row

                    required property int index
                    required property var modelData

                    width: parent.width
                    height: menu.rowHeight
                    color: Theme.surfaceCard
                    border.width: index === menu.currentIndex ? 2 : 1
                    border.color: index === menu.currentIndex
                                  ? Theme.accent
                                  : Theme.borderMid
                    radius: Sizing.cornerRadius

                    Text {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: menu.horizontalPadding
                        anchors.rightMargin: menu.horizontalPadding
                        text: row.modelData.label
                        color: Theme.textPrimary
                        font.family: Theme.fontUi
                        font.pixelSize: Sizing.fontSize(2.4)
                        elide: Text.ElideRight
                        renderType: Text.NativeRendering
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton
                        cursorShape: Qt.PointingHandCursor
                        onEntered: menu.currentIndex = row.index
                        onClicked: menu.accepted(row.modelData.id)
                    }
                }
            }
        }
    }
}
