// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0

import QtQuick

// Wraps a Tile-shaped delegate Component and exposes the four properties
// the Tile parent contract reads (see Tile.qml). Carousel and PagedGrid
// both need this exact shape; centralizing it here means the contract
// lives in one place and is enforced at compile time via
// `required property` rather than only at runtime via Tile's self-check.
//
// Hosts pass `sourceComponent` plus the four delegate properties; the
// loaded delegate (typically Tile) reads them through `parent.X` because
// QML doesn't surface Loader's user-defined properties on the loaded
// item directly.
Loader {
    required property bool isSelected
    required property bool isFocused
    required property string name
    required property string coverKey
    // Default 1.0 so the existing cover-fitting Tile delegate (which
    // ignores this property) keeps painting at full opacity. The hub
    // categories carousel binds this to drive its activation fade.
    property real imagesOpacity: 1.0
}
