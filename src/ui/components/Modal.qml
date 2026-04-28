// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0

import QtQuick
import Zaparoo.Theme

// Reusable modal panel. Two flavors selected by `kind`:
//   "action_error" — title + one button. Caller wires `accepted` to
//                    its dismiss handler. Border uses Theme.textPrimary.
//   "transient"    — title + optional Cancel pill, no accept button.
//                    Auto-dismisses via the caller's failure timer or
//                    external signal. Border uses Theme.accent while
//                    `failed === false`, Theme.textPrimary on failure.
//
// Pure presentation: input routing lives in Main.qml, persistence in
// Browse.AppState. The component only renders, swallows clicks on its
// scrim, and emits `cancelRequested` (transient Cancel pill) or
// `accepted` (action_error button).
//
// Software-rendering safe — only Item, Rectangle, Text, MouseArea.
// No transforms, no shaders, no animations.
Item {
    id: modal

    property bool open: false
    property string kind: "action_error"     // or "transient"
    property string title: ""
    property string body: ""                 // optional secondary line
    property string buttonLabel: qsTr("OK")  // action_error only
    property bool failed: false              // transient only

    signal accepted()         // action_error: button click
    signal cancelRequested()  // transient: Cancel pill click

    visible: modal.open
    anchors.fill: parent
    z: 300

    Rectangle {
        anchors.fill: parent
        color: "#99000000"

        // Eat clicks on the scrim so they don't reach the screens
        // underneath.
        MouseArea {
            anchors.fill: parent
        }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width * 0.78, Sizing.pctH(82))
            height: Sizing.pctH(34)
            color: Theme.bgPanel
            border.width: 2
            border.color: modal.failed
                          ? Theme.textPrimary
                          : (modal.kind === "action_error"
                             ? Theme.textPrimary
                             : Theme.accent)

            Text {
                id: titleText

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.topMargin: Sizing.pctH(7)
                anchors.leftMargin: Sizing.pctW(5)
                anchors.rightMargin: Sizing.pctW(5)
                text: modal.title
                font.family: Theme.fontUi
                font.pixelSize: Sizing.fontSize(3)
                color: Theme.textPrimary
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                renderType: Text.NativeRendering
            }

            Text {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: titleText.bottom
                anchors.topMargin: Sizing.pctH(1.5)
                anchors.leftMargin: Sizing.pctW(5)
                anchors.rightMargin: Sizing.pctW(5)
                visible: modal.body !== ""
                text: modal.body
                font.family: Theme.fontUi
                font.pixelSize: Sizing.fontSize(2.4)
                color: Theme.textPrimary
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                renderType: Text.NativeRendering
            }

            // Cancel pill — transient flavor, hidden once `failed`
            // flips. Failure is a terminal display that auto-dismisses,
            // not interactive.
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Sizing.pctH(5)
                width: Sizing.pctW(22)
                height: Sizing.pctH(7)
                color: Theme.bgBar
                border.width: 1
                border.color: Theme.borderMid
                visible: modal.kind === "transient" && !modal.failed

                Text {
                    anchors.centerIn: parent
                    text: qsTr("Cancel")
                    font.family: Theme.fontUi
                    font.pixelSize: Sizing.fontSize(2.4)
                    color: Theme.textPrimary
                    renderType: Text.NativeRendering
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: modal.cancelRequested()
                }
            }

            // Accept button — action_error flavor.
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Sizing.pctH(5)
                width: Sizing.pctW(22)
                height: Sizing.pctH(7)
                color: Theme.bgBar
                border.width: 1
                border.color: Theme.borderMid
                visible: modal.kind === "action_error"

                Text {
                    anchors.centerIn: parent
                    text: modal.buttonLabel
                    font.family: Theme.fontUi
                    font.pixelSize: Sizing.fontSize(2.4)
                    color: Theme.textPrimary
                    renderType: Text.NativeRendering
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: modal.accepted()
                }
            }
        }
    }
}
