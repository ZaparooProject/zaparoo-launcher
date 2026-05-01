// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0

import QtQuick
import Zaparoo.Theme

// Single row in a `SettingsScreen.qml` form. Label on the left, current
// value on the right with `<` `>` cycling arrows when focused. The
// arrows are hint glyphs — actual cycling is owned by the parent
// screen's `handleAction`, which calls a model setter on left/right.
//
// Visual states:
//   * Unfocused — flat surface, muted label, primary value text.
//   * Focused — surface bumps to `surfaceCard`, borders to `textPrimary`,
//     and the cycling-arrow glyphs become visible.
//
// The component is purely presentational. The screen owns layout (Column
// stacking + selection index) and value mutation.
Item {
    id: root

    required property string label
    required property string value
    property bool isFocused: false
    // True on either edge when the value can advance further. Drives
    // arrow visibility so the user sees a hint that left/right does
    // nothing at the ends of a list.
    property bool canCyclePrev: true
    property bool canCycleNext: true

    implicitHeight: Sizing.pctH(8)

    Rectangle {
        id: surface

        anchors.fill: parent
        radius: Sizing.pctH(1.2)
        color: root.isFocused ? Theme.surfaceCard : "transparent"
        border.color: root.isFocused ? Theme.textPrimary : Theme.borderSubtle
        border.width: root.isFocused ? Sizing.pctH(0.4) : 1
    }

    Text {
        id: labelText

        anchors.left: parent.left
        anchors.leftMargin: Sizing.pctW(3)
        anchors.verticalCenter: parent.verticalCenter
        text: root.label
        color: root.isFocused ? Theme.textPrimary : Theme.textLabel
        font.family: Theme.fontUi
        font.pixelSize: Sizing.fontSize(2.6)
        renderType: Text.NativeRendering
    }

    // Right-side value cluster: `<`  value  `>`. The arrow glyphs are
    // plain Text — keeping it dependency-free; the gamepad button glyphs
    // are reserved for the help bar.
    Row {
        anchors.right: parent.right
        anchors.rightMargin: Sizing.pctW(3)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Sizing.pctW(1.5)

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "<"
            visible: root.isFocused && root.canCyclePrev
            color: Theme.textPrimary
            font.family: Theme.fontUi
            font.pixelSize: Sizing.fontSize(3.0)
            renderType: Text.NativeRendering
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.value
            color: Theme.textPrimary
            font.family: Theme.fontUi
            font.pixelSize: Sizing.fontSize(2.6)
            renderType: Text.NativeRendering
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: ">"
            visible: root.isFocused && root.canCycleNext
            color: Theme.textPrimary
            font.family: Theme.fontUi
            font.pixelSize: Sizing.fontSize(3.0)
            renderType: Text.NativeRendering
        }
    }
}
