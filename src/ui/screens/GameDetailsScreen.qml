// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0

import QtQuick
import Zaparoo.Theme

// Minimal game details screen. For now it displays only the selected
// game title and lets Escape return to the games grid.
Item {
    id: details

    property bool active: false
    property string gameTitle: ""

    signal requestGamesScreen()

    function handleAction(action: string): void {
        if (action === "cancel")
            details.requestGamesScreen()
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        y: Sizing.pctH(11)
        width: parent.width * 0.86
        text: details.gameTitle
        font.family: Theme.fontUi
        font.pixelSize: Sizing.fontSize(5)
        font.weight: Font.Medium
        color: Theme.textPrimary
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHCenter
        renderType: Text.NativeRendering
    }
}
