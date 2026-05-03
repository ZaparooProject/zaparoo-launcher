// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0

import QtQuick
import Zaparoo.Theme

// Software-rendering safe contextual menu. It positions itself next to an
// anchor rectangle and clamps to the window bounds so edge tiles never push
// the menu off-screen. It intentionally has no dim scrim.
Item {
    id: menu

    property bool open: false
    property rect anchorRect: Qt.rect(0, 0, 0, 0)
    property var entries: []
    property int currentIndex: 0

    signal accepted(int index)
    signal closeRequested()

    readonly property int margin: Sizing.pctH(2)
    readonly property int gap: Sizing.pctW(1.2)
    readonly property int rowHeight: Sizing.pctH(6)
    readonly property int horizontalPadding: Sizing.pctW(2)
    readonly property int panelWidth:
        Math.min(Math.max(Sizing.pctW(26), Sizing.pctH(44)),
                 Math.max(0, width - 2 * margin))
    readonly property int panelHeight:
        Math.min(entries.length * rowHeight + 2, Math.max(0, height - 2 * margin))
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
        else if (action === "accept")
            menu.accepted(menu.currentIndex)
        else if (action === "cancel")
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

        Column {
            anchors.fill: parent
            anchors.margins: 1

            Repeater {
                model: menu.entries

                Rectangle {
                    id: row

                    required property int index
                    required property string modelData

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
                        text: row.modelData
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
                        onClicked: menu.accepted(row.index)
                    }
                }
            }
        }
    }
}
