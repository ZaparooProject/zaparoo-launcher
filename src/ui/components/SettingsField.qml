// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
// Single row in a `SettingsScreen.qml` form. Label on the left, current
// value on the right with `<` `>` cycling arrows when focused. The
// arrows are hint glyphs — actual cycling is owned by the parent
// screen's `handleAction`, which calls a model setter on left/right.
// Visual states:
//   * Unfocused — flat surface, muted label, primary value text.
//   * Focused — surface bumps to `surfaceCard`, borders to `textPrimary`,
//     and the cycling-arrow glyphs become visible.

import QtQuick
import Zaparoo.Theme

// The component is purely presentational. The screen owns layout (Column
// stacking + selection index) and value mutation.
Item {
    id: root

    required property string label
    required property string value
    property string control: "value"
    property bool checked: false
    property bool isFocused: false
    // True on either edge when the value can advance further. Drives
    // arrow visibility so the user sees a hint that left/right does
    // nothing at the ends of a list.
    property bool canCyclePrev: true
    property bool canCycleNext: true
    // For `control: "action"` — short live-state string painted on the
    // right ("In progress", "Paused", or "" when idle). The screen
    // owns the binding; the field treats it as a plain caption.
    property string actionStatus: ""

    signal hovered
    signal clicked
    signal rightClicked
    // Emitted when the action-control row receives an accept press.
    // The screen wires this to the matching invokable (start/cancel
    // index, start/cancel scrape) and gates by `actionStatus`.
    signal accepted

    // Item.enabled (built-in) gates the MouseArea below; the dimmed
    // opacity here gives a matching visual cue. Setting `enabled: false`
    // on the row makes Accept a no-op (the index/scrape pair use this
    // when one of the two is in flight — Core serialises them).
    opacity: enabled ? 1 : 0.4
    implicitHeight: Sizing.pctH(8)

    Rectangle {
        id: surface

        anchors.fill: parent
        radius: Sizing.cornerRadius
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
        visible: root.control === "value"
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
            font.pixelSize: Sizing.fontSize(3)
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
            font.pixelSize: Sizing.fontSize(3)
            renderType: Text.NativeRendering
        }
    }

    Item {
        id: toggle

        visible: root.control === "toggle"
        anchors.right: parent.right
        anchors.rightMargin: Sizing.pctW(3)
        anchors.verticalCenter: parent.verticalCenter
        // Standard pill-toggle proportion: width ≈ 1.85 × height keeps
        // the handle's travel close to one diameter on either side
        // without leaving the long rail of empty pill the previous
        // pctW(8) (~3.7× height on a 16:9 panel) painted.
        height: Sizing.pctH(3.8)
        width: height * 1.85

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: root.checked ? Theme.accent : Theme.borderMid
            border.color: root.isFocused ? Theme.textPrimary : Theme.borderSubtle
            border.width: root.isFocused ? Sizing.pctH(0.25) : 1
        }

        Rectangle {
            width: toggle.height - Sizing.pctH(0.9)
            height: width
            radius: width / 2
            x: root.checked ? toggle.width - width - Sizing.pctH(0.45) : Sizing.pctH(0.45)
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.textPrimary
        }
    }

    // Right-side cluster for `control: "action"`. The chevron is the
    // affordance — it always paints so an idle action row reads as
    // pressable. The status caption to its left only paints while the
    // operation is in flight ("In progress" / "Paused" / "Optimizing");
    // it's a status, not the label of the action.
    Row {
        visible: root.control === "action"
        anchors.right: parent.right
        anchors.rightMargin: Sizing.pctW(3)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Sizing.pctW(1.5)

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.actionStatus !== ""
            text: root.actionStatus
            color: Theme.textLabel
            font.family: Theme.fontUi
            font.pixelSize: Sizing.fontSize(2.4)
            renderType: Text.NativeRendering
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "›"
            color: Theme.textPrimary
            font.family: Theme.fontUi
            font.pixelSize: Sizing.fontSize(3)
            renderType: Text.NativeRendering
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onEntered: root.hovered()
        // Action rows fire `accepted()` (the screen runs start/cancel
        // there); every other control fires `clicked()` (the screen
        // moves focus and toggles a value). Emitting both for action
        // rows used to make `onClicked` and `onAccepted` race over
        // the same press.
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton)
                root.rightClicked();
            else if (root.control === "action")
                root.accepted();
            else
                root.clicked();
        }
    }
}
