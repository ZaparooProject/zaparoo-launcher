// Zaparoo Launcher
// Copyright (c) 2026 The Zaparoo Project Contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0

import QtQuick
import QtTest
import Zaparoo.App

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
        compare(mainWindow.hubFocus, "categories")
    }
}
