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
        compare(mainWindow.activeScreen, "hub")
        compare(mainWindow.hubFocus, "categories")
    }
}
