// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0

import QtQuick
import Zaparoo.Theme

// Displays a live FPS readout in the top-right corner.
// Green ≥55 FPS, yellow ≥30 FPS, red <30 FPS.
// Always check this counter stays green at 720p+ when changing visuals.
Item {
    id: root

    property int fps: 0
    property int _frameCount: 0

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            root.fps = root._frameCount
            root._frameCount = 0
        }
    }

    FrameAnimation {
        running: true
        onTriggered: root._frameCount++
    }

    Text {
        anchors.top: parent.top
        anchors.right: parent.right
        // `%1 FPS` stays one string so translators can reorder ("FPS %1")
        // without splitting the label from the number.
        text: qsTr("%1 FPS").arg(root.fps)
        font.family: Theme.fontMono
        font.pixelSize: Sizing.fontSize(2)
        color: root.fps >= 55 ? "#00ff00" : (root.fps >= 30 ? "#ffff00" : "#ff0000")
        renderType: Text.NativeRendering
    }
}
