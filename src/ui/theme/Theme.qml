// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
// SPDX-FileCopyrightText: 2026 Callan Barrett
pragma Singleton

import QtQuick

// Project-wide color and font constants.
// Never hardcode colors or font families inline — use these instead.
QtObject {
    // Backgrounds
    readonly property color bgDeep: "#0f0f23"
    readonly property color bgMid: "#252550"
    readonly property color bgPanel: "#1a1a35"
    readonly property color bgBar: "#0a0a15"

    // Borders
    readonly property color borderSubtle: "#1a1a2e"
    readonly property color borderFaint: "#222"
    readonly property color borderDim: "#333"
    readonly property color borderMid: "#404060"
    readonly property color borderActive: "#2a2a3a"

    // Text
    readonly property color textPrimary: "#ffffff"
    readonly property color textMuted: "#666666"
    readonly property color textDim: "#555555"
    readonly property color textLabel: "#888888"

    // Accent — static warm amber used for selection highlights.
    readonly property color accent: "#FFB347"

    // Fonts
    readonly property string fontRetro: "Press Start 2P"
    readonly property string fontMono: "monospace"
}
