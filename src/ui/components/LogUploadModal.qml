// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0

import QtQuick
import Zaparoo.Theme
import Zaparoo.Browse as Browse

// cxx-qt 0.8 patches `isFinal: true` on singleton properties but the
// qmltypes schema has no `isFinal` slot, so every read trips qmllint's
// "Member can be shadowed" check. Until the schema grows the slot,
// suppress the compiler category file-wide.
// qmllint disable compiler

// Modal shown when the user triggers "Upload log" from Settings. Three
// visual phases driven by `Browse.LogUpload.state`:
//
//   uploading (1) — single line of body copy, no buttons. Cancel via
//                   Escape (router pops the modal; the upload finishes
//                   in the background but the user can no longer see
//                   the result).
//   success   (2) — QR of the URL on top, the URL as plain text below,
//                   and a "Done" button that closes the modal.
//   error     (3) — error message + a "Retry" button that re-fires
//                   `Browse.LogUpload.upload()`.
//
// Routing and the modal stack are owned by `Main.qml`. We emit
// `closeRequested` and trust the router to pop. `handleAction` is the
// input hook called from `Main.qml`'s modal-dispatch branch.
Item {
    id: modal

    property bool open: false

    signal closeRequested()

    readonly property int _stateIdle: 0
    readonly property int _stateUploading: 1
    readonly property int _stateSuccess: 2
    readonly property int _stateError: 3

    readonly property int phase: Browse.LogUpload.state

    visible: modal.open
    anchors.fill: parent
    z: 300

    onOpenChanged: {
        if (!modal.open)
            return
        if (modal.phase === modal._stateIdle)
            Browse.LogUpload.upload()
    }

    // Generate the QR matrix as soon as we have a URL. `Browse.QrCode`
    // is shared across the launcher; the next consumer (a future flow)
    // will overwrite it with their own content, so generate eagerly
    // rather than relying on a previously cached matrix.
    Connections {
        target: Browse.LogUpload
        function onStateChanged(): void {
            if (Browse.LogUpload.state === modal._stateSuccess)
                Browse.QrCode.generate(Browse.LogUpload.url)
        }
    }

    function handleAction(action: string): void {
        if (action === "accept") {
            if (modal.phase === modal._stateSuccess) {
                modal.closeRequested()
            } else if (modal.phase === modal._stateError) {
                Browse.LogUpload.upload()
            }
        } else if (action === "cancel") {
            modal.closeRequested()
        }
    }

    // Scrim. Eats clicks so they don't reach the screen tree underneath.
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
        width: Math.min(parent.width * 0.78, Sizing.pctH(110))
        height: contentColumn.height + Sizing.pctH(12)
        color: Theme.bgPanel
        border.width: 2
        border.color: Theme.textPrimary
        radius: Sizing.cornerRadius

        Column {
            id: contentColumn

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: Sizing.pctH(6)
            anchors.leftMargin: Sizing.pctW(6)
            anchors.rightMargin: Sizing.pctW(6)
            spacing: Sizing.pctH(3)

            Text {
                width: parent.width
                text: qsTr("Upload log file")
                font.family: Theme.fontUi
                font.pixelSize: Sizing.fontSize(3.2)
                color: Theme.textPrimary
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                renderType: Text.NativeRendering
            }

            Text {
                width: parent.width
                visible: modal.phase === modal._stateUploading
                         || modal.phase === modal._stateIdle
                text: qsTr("Uploading log file - this may take a moment.")
                font.family: Theme.fontUi
                font.pixelSize: Sizing.fontSize(2.6)
                color: Theme.textPrimary
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                renderType: Text.NativeRendering
            }

            // Success block — QR matrix above, URL plain-text below.
            // The QR is a fixed pixel size derived from the matrix size
            // so the modal's panel height stays stable across phases.
            Item {
                id: successBlock

                width: parent.width
                visible: modal.phase === modal._stateSuccess
                height: visible ? qrHolder.height + urlText.height + Sizing.pctH(2) : 0

                readonly property int matrixSize: Browse.QrCode.size
                readonly property int quietZone: 4
                readonly property real maxQrPixels:
                    Math.min(Sizing.pctW(38), Sizing.pctH(54))
                readonly property real moduleSize: matrixSize > 0
                    ? Math.max(1,
                        Math.floor(maxQrPixels / (matrixSize + quietZone * 2)))
                    : 1
                readonly property real qrPixels:
                    moduleSize * (matrixSize + quietZone * 2)

                Rectangle {
                    id: qrHolder

                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    width: successBlock.qrPixels
                    height: successBlock.qrPixels
                    color: "white"
                    border.width: Math.max(1,
                                           Math.round(successBlock.moduleSize * 0.18))
                    border.color: Theme.borderSubtle

                    Item {
                        id: matrix

                        anchors.centerIn: parent
                        width: successBlock.moduleSize * successBlock.matrixSize
                        height: successBlock.moduleSize * successBlock.matrixSize
                        visible: successBlock.matrixSize > 0

                        Repeater {
                            model: successBlock.matrixSize

                            delegate: Item {
                                id: rowDelegate

                                required property int index

                                readonly property int row: index
                                readonly property string bits:
                                    Browse.QrCode.row_at(row)

                                x: 0
                                y: row * successBlock.moduleSize
                                width: matrix.width
                                height: successBlock.moduleSize

                                Repeater {
                                    model: successBlock.matrixSize

                                    delegate: Rectangle {
                                        required property int index

                                        x: index * successBlock.moduleSize
                                        y: 0
                                        width: successBlock.moduleSize
                                        height: successBlock.moduleSize
                                        color: "black"
                                        visible: rowDelegate.bits.charAt(index) === "1"
                                    }
                                }
                            }
                        }
                    }
                }

                Text {
                    id: urlText

                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: qrHolder.bottom
                    anchors.topMargin: Sizing.pctH(2)
                    width: parent.width
                    text: Browse.LogUpload.url
                    font.family: Theme.fontUi
                    font.pixelSize: Sizing.fontSize(2.2)
                    color: Theme.textPrimary
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WrapAnywhere
                    renderType: Text.NativeRendering
                }
            }

            Text {
                width: parent.width
                visible: modal.phase === modal._stateError
                text: Browse.LogUpload.error_message !== ""
                      ? qsTr("Upload failed: %1").arg(Browse.LogUpload.error_message)
                      : qsTr("Upload failed.")
                font.family: Theme.fontUi
                font.pixelSize: Sizing.fontSize(2.4)
                color: Theme.textPrimary
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                renderType: Text.NativeRendering
            }

            Item {
                width: parent.width
                height: Sizing.pctH(7)
                visible: modal.phase === modal._stateSuccess
                         || modal.phase === modal._stateError

                Rectangle {
                    id: actionButton

                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    width: Sizing.pctW(28)
                    height: parent.height
                    color: Theme.bgBar
                    border.width: 1
                    border.color: Theme.borderMid
                    radius: Sizing.cornerRadius

                    Text {
                        anchors.centerIn: parent
                        text: modal.phase === modal._stateError
                              ? qsTr("Retry")
                              : qsTr("Done")
                        font.family: Theme.fontUi
                        font.pixelSize: Sizing.fontSize(2.5)
                        color: Theme.textPrimary
                        renderType: Text.NativeRendering
                    }

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton
                        onClicked: modal.handleAction("accept")
                    }
                }
            }
        }
    }
}
