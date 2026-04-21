// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
// SPDX-FileCopyrightText: 2026 Callan Barrett

import QtQuick
import QtTest
import Zaparoo.App

TestCase {
    name: "UiSmoke"
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
        verify(!mainWindow.inMenu, "Should start in carousel mode, not menu mode")
        compare(mainWindow.menuIndex, 0)
        verify(!mainWindow.crtEnabled, "CRT should start off")
    }

    function test_game_names_present() {
        verify(mainWindow.gameNames.length > 0, "Should have at least one game name")
    }
}
