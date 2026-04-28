// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
pragma Singleton

import QtQuick

// Centralizes the qrc layout for embedded resources so the rule
// (`qrc:/qt/qml/Zaparoo/App/resources/...`) lives in exactly one place.
// Tile.qml and MainLayout.qml's prefetch repeater both build cover URLs
// from a `coverKey`; without a shared helper, a future change to the
// resource path or image format silently misses one of the two sites
// and breaks the QPixmapCache match between prefetch and visible Image.
QtObject {
    // Base URL for everything under `resources/` in the embedded qrc.
    readonly property string baseUrl: "qrc:/qt/qml/Zaparoo/App/resources/"

    // Build a cover image URL from a `coverKey` (relative path under
    // `resources/images/` without extension, e.g. `systems/SNES`,
    // `categories/Consoles`). Empty key returns an empty URL so the
    // caller can use it as a "no cover" sentinel.
    function coverUrl(key: string): url {
        if (key === "")
            return ""
        return baseUrl + "images/" + key + ".png"
    }

    function statusIconUrl(name: string): url {
        if (name === "")
            return ""
        return baseUrl + "images/status/" + name + ".xpm"
    }
}
