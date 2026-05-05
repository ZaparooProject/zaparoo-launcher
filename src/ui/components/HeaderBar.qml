// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0

import QtQuick
import Zaparoo.Theme
import Zaparoo.Browse as Browse

// cxx-qt 0.8 patches `isFinal: true` on singleton properties but the
// qmltypes schema has no `isFinal` slot, so every read of a Browse
// singleton trips qmllint's "Member can be shadowed" check. Suppress
// the compiler category file-wide until the schema grows the slot.
// qmllint disable compiler

// Top header bar — Zaparoo logo on the left, host status row + Core
// status pill stacked on the right. Height is fixed at
// `Sizing.headerHeight` so the pill's slot is reserved even when the
// pill is idle and the logo can match the two stacked rows exactly.
//
// Software-renderer safe: only Image, Row, Item, Text, and the
// existing CoreStatusPill subtree. No transforms, no shaders.
Item {
    id: header

    height: Sizing.headerHeight

    Image {
        id: logo

        anchors.left: parent.left
        anchors.leftMargin: Sizing.headerSideMargin
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        // PreserveAspectFit caps width by the logo's intrinsic aspect,
        // so the brand mark never stretches even though the Image
        // element fills the full header height.
        fillMode: Image.PreserveAspectFit
        horizontalAlignment: Image.AlignLeft
        source: "qrc:/qt/qml/Zaparoo/App/resources/images/logo.png"
    }

    // Host status row — NFC / Wi-Fi / LAN / Bluetooth icons plus the
    // wall clock, right-anchored so badges can appear and disappear
    // without nudging the clock away from the edge.
    Row {
        id: topHud

        anchors.top: parent.top
        anchors.right: parent.right
        anchors.rightMargin: Sizing.headerSideMargin
        spacing: Sizing.pctW(1)
        // Explicit row height keeps every child on a single line. Without
        // this the Row would track the tallest child (clock Text — font
        // ascender + descender), which pushes icons up and out of
        // alignment with the clock baseline.
        height: Sizing.headerRowHeight

        StatusIcon {
            anchors.verticalCenter: parent.verticalCenter
            visible: Browse.SystemStatus.has_nfc
            source: Resources.statusIconUrl("NFC")
            name: "NFC"
        }

        StatusIcon {
            anchors.verticalCenter: parent.verticalCenter
            visible: Browse.SystemStatus.has_wifi_internet
            source: Resources.statusIconUrl("WiFi")
            name: "Wi-Fi"
        }

        StatusIcon {
            anchors.verticalCenter: parent.verticalCenter
            visible: Browse.SystemStatus.has_lan_internet
            source: Resources.statusIconUrl("WiredNetwork")
            name: "LAN"
        }

        StatusIcon {
            anchors.verticalCenter: parent.verticalCenter
            visible: Browse.SystemStatus.has_bluetooth
            source: Resources.statusIconUrl("Bluetooth")
            name: "Bluetooth"
        }

        Text {
            id: clockLabel

            // 30s tick keeps the displayed minute fresh without per-second
            // wakeups; minutes-only display means we never need finer.
            // Fixed width avoids reflow on the minute boundary because
            // proportional digits make "11:11" narrower than "10:00".
            property string currentTime: Qt.formatDateTime(new Date(), "HH:mm")

            anchors.verticalCenter: parent.verticalCenter
            height: parent.height
            width: Sizing.headerRowHeight * 3
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignRight
            text: clockLabel.currentTime
            font.family: Theme.fontUi
            font.pixelSize: Sizing.headerRowHeight
            color: Theme.textPrimary
            renderType: Text.NativeRendering

            Timer {
                interval: 30000
                running: true
                repeat: true
                triggeredOnStart: true
                onTriggered: clockLabel.currentTime =
                    Qt.formatDateTime(new Date(), "HH:mm")
            }
        }
    }

    // Mutually-exclusive Core / indexing / scraper status surface. Sits
    // on its own line directly under `topHud`, right-aligned to the
    // same edge as the clock. The pill collapses to zero size when
    // idle, but its slot stays reserved by the header's fixed height
    // so the logo and the surrounding layout don't shift.
    CoreStatusPill {
        anchors.top: topHud.bottom
        anchors.right: topHud.right
        anchors.topMargin: Sizing.headerStackGap
    }
}
