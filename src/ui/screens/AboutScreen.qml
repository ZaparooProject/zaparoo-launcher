// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
pragma ComponentBehavior: Bound

import QtQuick
import Zaparoo.Theme
import Zaparoo.Ui
import Zaparoo.Browse as Browse

// cxx-qt 0.8 patches `isFinal: true` on singleton properties but the
// qmltypes schema has no `isFinal` slot, so reads of `Browse.BuildInfo`
// fields trip qmllint's "Member can be shadowed" check. Suppress just
// the compiler category file-wide; matches the pattern used in
// CommercialNoticeModal.qml.
// qmllint disable compiler

// About / License screen — static, scrollable info page reachable from
// Settings → About / License. Pure input dispatcher: emits
// `requestSettingsScreen()` on cancel; Up/Down scroll the Flickable.
//
// Build provenance (git commit, build channel, official-build marker)
// will plug into the version line in a follow-up round; for now only
// the hardcoded `Qt.application.version` is shown.
Item {
    id: about

    // Bound by MainLayout to `root.pendingTransition !== ""`. About is
    // a destination, never a source — kept for parity with the other
    // screens.
    property bool transitioning: false

    signal requestSettingsScreen()

    // True when the body Column overflows the Flickable viewport, so
    // the help bar can show the Up/Down scroll cue only when it's
    // actually meaningful. Per the minimal-help-bar policy, hints
    // shouldn't promise a press that no-ops.
    readonly property bool contentOverflows:
        body.implicitHeight > flickable.height

    function _scrollBy(delta: int): void {
        const maxY = Math.max(0, flickable.contentHeight - flickable.height)
        flickable.contentY = Math.max(0, Math.min(maxY, flickable.contentY + delta))
    }

    function handleAction(action: string): void {
        if (action === "up")
            about._scrollBy(-Sizing.pctH(8))
        else if (action === "down")
            about._scrollBy(Sizing.pctH(8))
        else if (action === "cancel")
            about.requestSettingsScreen()
        // accept and left/right are no-ops on a static page.
    }

    // ── Visual tree ───────────────────────────────────────────────────────────

    TopStatusStrip {
        id: topStrip
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: Sizing.headerBottom
        height: Sizing.pctH(7)
        title: qsTr("About / License")
        currentPage: 0
        totalPages: 0
        totalText: ""
    }

    // Body lives in a Flickable so the static content can grow past a
    // single screen on MiSTer 240p without dropping off-frame. Width
    // is capped tighter than Settings's pctW(70) — prose reads better
    // at narrow line lengths, and the cap also keeps the logo from
    // having to scale up past its 600px native width on widescreen.
    // Bottom margin clears the help bar (pctH(6)) plus a small gap.
    Flickable {
        id: flickable

        anchors.top: topStrip.bottom
        anchors.topMargin: Sizing.pctH(2)
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Sizing.pctH(8)
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(parent.width - Sizing.pctW(10), Sizing.pctW(50))
        contentWidth: width
        contentHeight: body.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: body

            width: parent.width
            spacing: Sizing.pctH(2)

            // Logo width is capped at a screen-height-relative size so
            // the brand mark stays a header element across 240p →
            // 1080p without ballooning. sourceSize is pinned to the
            // native pixel dimensions to stop Qt upscaling then
            // downsampling and to keep the lines crisp; height is
            // derived from width via the image's intrinsic aspect.
            Image {
                anchors.horizontalCenter: parent.horizontalCenter
                source: "qrc:/qt/qml/Zaparoo/App/resources/images/logo.png"
                fillMode: Image.PreserveAspectFit
                sourceSize.width: 600
                sourceSize.height: 135
                width: Math.min(parent.width, Sizing.pctH(35))
                height: width * 135 / 600
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                horizontalAlignment: Text.AlignHCenter
                text: qsTr("Zaparoo Launcher")
                color: Theme.textPrimary
                font.family: Theme.fontUi
                font.pixelSize: Sizing.fontSize(4)
                font.weight: Font.Medium
                renderType: Text.NativeRendering
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                horizontalAlignment: Text.AlignHCenter
                text: qsTr("Version %1 · %2 · %3")
                    .arg(Qt.application.version)
                    .arg(Browse.BuildInfo.commit)
                    .arg(Browse.BuildInfo.channel)
                color: Theme.textLabel
                font.family: Theme.fontUi
                font.pixelSize: Sizing.fontSize(2.4)
                renderType: Text.NativeRendering
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                horizontalAlignment: Text.AlignHCenter
                text: qsTr("Built %1").arg(Browse.BuildInfo.build_date)
                color: Theme.textLabel
                font.family: Theme.fontUi
                font.pixelSize: Sizing.fontSize(2.2)
                renderType: Text.NativeRendering
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: qsTr("Copyright 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.")
                color: Theme.textPrimary
                font.family: Theme.fontUi
                font.pixelSize: Sizing.fontSize(2.6)
                renderType: Text.NativeRendering
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: qsTr("Source available under the PolyForm Noncommercial License 1.0.0. Free for personal, non-commercial use. Commercial use or redistribution requires a separate license.")
                color: Theme.textPrimary
                font.family: Theme.fontUi
                font.pixelSize: Sizing.fontSize(2.6)
                renderType: Text.NativeRendering
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: qsTr("Commercial licensing: legal@zaparoo.org")
                color: Theme.textPrimary
                font.family: Theme.fontUi
                font.pixelSize: Sizing.fontSize(2.6)
                renderType: Text.NativeRendering
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: qsTr("Project: https://zaparoo.org")
                color: Theme.textPrimary
                font.family: Theme.fontUi
                font.pixelSize: Sizing.fontSize(2.6)
                renderType: Text.NativeRendering
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                horizontalAlignment: Text.AlignHCenter
                text: qsTr("Created by")
                color: Theme.textLabel
                font.family: Theme.fontUi
                font.pixelSize: Sizing.fontSize(2.4)
                renderType: Text.NativeRendering
            }

            // Contributor names are not translated — they're proper
            // names. Joined with newlines (not separate Text items)
            // so the block reads as one credits paragraph and the
            // Column spacing doesn't push them apart.
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                horizontalAlignment: Text.AlignHCenter
                text: "Andrea Bogazzi\nBossRighteous\nTim Wilsie\nWizzo"
                color: Theme.textPrimary
                font.family: Theme.fontUi
                font.pixelSize: Sizing.fontSize(2.6)
                renderType: Text.NativeRendering
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: qsTr("Full license text in COPYING.")
                color: Theme.textLabel
                font.family: Theme.fontUi
                font.pixelSize: Sizing.fontSize(2.4)
                renderType: Text.NativeRendering
            }
        }
    }
}
