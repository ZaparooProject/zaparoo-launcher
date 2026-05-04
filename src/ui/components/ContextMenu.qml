// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
pragma ComponentBehavior: Bound

import QtQuick
import Zaparoo.Theme

// `entries` is a `var` array of plain JS objects (`{ id, label }`). The
// AOT compiler can't infer the shape of `var`, so every binding that
// reads `entries.length` or `modelData.label` falls back to the JS
// interpreter and trips the compiler category. Suppress file-wide.
// qmllint disable compiler

// Software-rendering safe contextual menu. It positions itself next to an
// anchor rectangle and clamps to the window bounds so edge tiles never push
// the menu off-screen. It intentionally has no dim scrim.
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
    readonly property int horizontalPadding: Sizing.pctW(2)
    readonly property int panelWidth:
        Math.min(Math.max(Sizing.pctW(26), Sizing.pctH(44)),
                 Math.max(0, width - 2 * margin))
    // Top/bottom margins inside the panel are sized to the panel
    // radius so a focused row's square background never intersects
    // the rounded corners — see the panel `Rectangle` below.
    readonly property int panelRadius: Sizing.cornerRadius / 2
    readonly property int panelHeight:
        Math.min(entries.length * rowHeight + 2 * panelRadius,
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

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        onClicked: menu.closeRequested()
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
        border.width: 2
        border.color: Theme.textPrimary
        radius: menu.panelRadius

        Column {
            anchors.fill: parent
            anchors.topMargin: menu.panelRadius
            anchors.bottomMargin: menu.panelRadius
            anchors.leftMargin: 1
            anchors.rightMargin: 1

            Repeater {
                model: menu.entries

                Rectangle {
                    id: row

                    required property int index
                    required property var modelData

                    width: parent.width
                    height: menu.rowHeight
                    color: index === menu.currentIndex ? Theme.surfaceCard : "transparent"
                    border.width: index === menu.currentIndex ? 1 : 0
                    border.color: Theme.accent

                    Text {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: menu.horizontalPadding
                        anchors.rightMargin: menu.horizontalPadding
                        text: row.modelData.label
                        color: row.index === menu.currentIndex ? Theme.textPrimary : Theme.textLabel
                        font.family: Theme.fontUi
                        font.pixelSize: Sizing.fontSize(2.4)
                        elide: Text.ElideRight
                        renderType: Text.NativeRendering
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton
                        onEntered: menu.currentIndex = row.index
                        onClicked: menu.accepted(row.modelData.id)
                    }
                }
            }
        }
    }
}
