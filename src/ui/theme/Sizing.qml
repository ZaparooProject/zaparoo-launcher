// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
pragma Singleton

import QtQuick

// Resolution-agnostic sizing helpers.
// All UI elements must use these functions rather than hardcoded pixel values.
// The UI must run correctly from 240p (CRT) through 1080p.
QtObject {
    id: root

    // Reference window dimensions — updated by Main.qml on start and resize.
    property real screenWidth: 640
    property real screenHeight: 480

    // Visible tile-row covers: fewer at very low resolution to avoid crowding.
    readonly property int visibleCovers: screenHeight < 300 ? 3 : 5

    // Paged grid shape: chosen by screen height so the same grid reads
    // sensibly from MiSTer 240p through 1080p. Width × height of one
    // page in tiles; product is the page size used by `PagedGrid`.
    readonly property int gridColumns: screenHeight < 300 ? 3
                                       : screenHeight < 600 ? 4
                                       : 5
    readonly property int gridRows: screenHeight < 300 ? 2 : 3

    function pctH(percent: real): int {
        return Math.round(screenHeight * percent / 100)
    }

    function pctW(percent: real): int {
        return Math.round(screenWidth * percent / 100)
    }

    // Minimum 8px to remain legible on CRT 240p displays.
    function fontSize(percent: real): int {
        return Math.max(8, pctH(percent))
    }
}
