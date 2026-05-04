// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0

import QtQuick
import Zaparoo.Theme
import Zaparoo.Browse as Browse

// qmllint disable compiler

Item {
    id: modal

    property bool open: false

    signal closeRequested()

    readonly property int _stateIdle: 0
    readonly property int _stateRunning: 1
    readonly property int _stateSuccess: 2
    readonly property int _stateError: 3
    readonly property int phase: Browse.UpdateAllRunner.state

    visible: modal.open
    anchors.fill: parent
    z: 320

    onOpenChanged: {
        if (!modal.open)
            return
        if (modal.phase === modal._stateIdle)
            Browse.UpdateAllRunner.run()
    }

    function _send(action: string): void {
        if (action === "up")
            Browse.UpdateAllRunner.send_input("\u001b[A")
        else if (action === "down")
            Browse.UpdateAllRunner.send_input("\u001b[B")
        else if (action === "right")
            Browse.UpdateAllRunner.send_input("\u001b[C")
        else if (action === "left")
            Browse.UpdateAllRunner.send_input("\u001b[D")
        else if (action === "accept")
            Browse.UpdateAllRunner.send_input("\r")
        else if (action === "cancel")
            Browse.UpdateAllRunner.send_input("\u001b")
    }

    function handleAction(action: string): void {
        if (modal.phase === modal._stateRunning) {
            modal._send(action)
            return
        }
        if (action === "accept" || action === "cancel")
            modal.closeRequested()
    }

    function handleText(text: string): void {
        if (modal.phase === modal._stateRunning && text !== "")
            Browse.UpdateAllRunner.send_input(text)
    }

    Rectangle {
        anchors.fill: parent
        color: "#cc000000"

        MouseArea {
            anchors.fill: parent
        }
    }

    Rectangle {
        id: panel

        anchors.centerIn: parent
        width: Math.min(parent.width * 0.88, Sizing.pctH(150))
        height: Math.min(parent.height * 0.78, Sizing.pctH(88))
        color: Theme.bgPanel
        border.width: 2
        border.color: Theme.textPrimary
        radius: Sizing.cornerRadius

        Text {
            id: title

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: Sizing.pctH(3)
            anchors.leftMargin: Sizing.pctW(4)
            anchors.rightMargin: Sizing.pctW(4)
            text: qsTr("MiSTer update_all")
            font.family: Theme.fontUi
            font.pixelSize: Sizing.fontSize(3.0)
            color: Theme.textPrimary
            horizontalAlignment: Text.AlignHCenter
            renderType: Text.NativeRendering
        }

        Rectangle {
            id: terminalFrame

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: title.bottom
            anchors.bottom: footer.top
            anchors.margins: Sizing.pctH(3)
            color: Theme.bgBar
            border.width: 1
            border.color: Theme.borderMid
            radius: Math.max(1, Math.round(Sizing.cornerRadius * 0.45))
            clip: true

            Flickable {
                id: terminalView

                anchors.fill: parent
                anchors.margins: Sizing.pctH(2)
                contentWidth: width
                contentHeight: terminalText.height
                boundsBehavior: Flickable.StopAtBounds
                clip: true

                Text {
                    id: terminalText

                    width: terminalView.width
                    text: Browse.UpdateAllRunner.output_text
                    font.family: Theme.fontMono
                    font.pixelSize: Sizing.fontSize(2.0)
                    color: Theme.textPrimary
                    wrapMode: Text.WrapAnywhere
                    renderType: Text.NativeRendering

                    onTextChanged: Qt.callLater(function() {
                        terminalView.contentY = Math.max(0,
                            terminalView.contentHeight - terminalView.height)
                    })
                }
            }
        }

        Text {
            id: footer

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Sizing.pctH(3)
            anchors.leftMargin: Sizing.pctW(4)
            anchors.rightMargin: Sizing.pctW(4)
            height: Sizing.pctH(6)
            text: {
                if (modal.phase === modal._stateRunning)
                    return qsTr("D-pad controls update_all. This window stays open while it runs.")
                if (modal.phase === modal._stateSuccess)
                    return qsTr("Done.")
                if (Browse.UpdateAllRunner.error_message !== "")
                    return qsTr("Failed: %1").arg(Browse.UpdateAllRunner.error_message)
                return qsTr("Failed.")
            }
            font.family: Theme.fontUi
            font.pixelSize: Sizing.fontSize(2.2)
            color: modal.phase === modal._stateError ? Theme.accent : Theme.textPrimary
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            wrapMode: Text.WordWrap
            renderType: Text.NativeRendering
        }
    }
}
