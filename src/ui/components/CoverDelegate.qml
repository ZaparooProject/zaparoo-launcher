// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
// SPDX-FileCopyrightText: 2026 Callan Barrett

import QtQuick
import Zaparoo.Theme

Item {
    id: root

    anchors.fill: parent

    // qmllint disable missing-property compiler
    readonly property bool delegateIsSelected: parent.isSelected
    readonly property url delegatePlaceholderCover: parent.placeholderCover
    // qmllint enable missing-property compiler

    Rectangle {
        anchors.fill: parent
        anchors.margins: 0
        color: "transparent"
        border.width: Math.max(1, Sizing.pctH(0.5))
        border.color: root.delegateIsSelected ? Theme.accent : Theme.borderMid
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.bgMid

        Image {
            anchors.fill: parent
            anchors.margins: 1
            source: root.delegatePlaceholderCover
            sourceSize.width: width
            sourceSize.height: height
            fillMode: Image.PreserveAspectFit
            smooth: false
            asynchronous: true
        }
    }
}
