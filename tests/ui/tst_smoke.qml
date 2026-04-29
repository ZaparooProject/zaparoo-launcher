// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0

import QtQuick
import QtTest
import Zaparoo.App
import Zaparoo.Browse as Browse

TestCase {
    name: "UiWindow"
    when: windowShown

    Main {
        id: mainWindow
        width: 1280
        height: 720
    }

    function test_window_loads() {
        verify(mainWindow.visible, "Main window should be visible")
        compare(mainWindow.title, "Zaparoo Launcher")
    }

    function test_initial_state() {
        compare(mainWindow.activeScreen, "hub")
    }

    function test_system_status_properties_exist() {
        compare(typeof Browse.SystemStatus.has_nfc, "boolean")
        compare(typeof Browse.SystemStatus.has_wifi_internet, "boolean")
        compare(typeof Browse.SystemStatus.has_lan_internet, "boolean")
        compare(typeof Browse.SystemStatus.has_bluetooth, "boolean")
    }
}
