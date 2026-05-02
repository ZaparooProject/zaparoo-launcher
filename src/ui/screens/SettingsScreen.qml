// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
pragma ComponentBehavior: Bound

import QtQuick
import Zaparoo.Theme
import Zaparoo.Ui
import Zaparoo.Browse as Browse

// cxx-qt 0.8 patches `isFinal: true` on singleton properties but the
// qmltypes schema has no `isFinal` slot for Method, so every qinvokable
// call on a Zaparoo.Browse singleton (set_resolution) still trips
// qmllint's "Member can be shadowed" check. Until the schema grows
// method-level finality, suppress the compiler category file-wide.
// qmllint disable compiler

// Settings screen — gamepad-driven vertical form. Resolution is MiSTer-only
// because the underlying `vmode` command lives on MiSTer's Linux framebuffer.
// Button layout is cross-platform and selects the resource directory for
// help-bar button glyphs. Mouse support is cross-platform and controls
// cursor visibility plus mouse hit targets.
//
// Pure input dispatcher: emits `requestHubScreen()` on Escape; left/
// right cycle the focused field's value via the model singleton.
Item {
    id: settings

    signal requestHubScreen()

    // Field registry. Each entry's `id` is read by handleAction to
    // route the cycle to the right model setter. Keeping this as data
    // (rather than a Repeater of typed children) makes adding fields
    // a one-line edit and keeps the navigation logic uniform.
    //
    // Field-specific helpers below provide option lists, display labels,
    // and model setters. This keeps the Repeater delegate presentational
    // while handleAction remains a simple input dispatcher.
    readonly property var fields: {
        const out = []
        if (Browse.Settings.is_mister) {
            out.push({
                id: "resolution",
                label: qsTr("Resolution")
            })
        }
        out.push({
            id: "language",
            label: qsTr("Language")
        })
        out.push({
            id: "buttonLayout",
            label: qsTr("Button layout")
        })
        out.push({
            id: "mouseEnabled",
            label: qsTr("Mouse support")
        })
        return out
    }

    readonly property int fieldCount: settings.fields.length
    readonly property bool focusedFieldIsMouse:
        settings.fieldCount > 0 && settings.fields[settings.currentIndex].id === "mouseEnabled"

    property int currentIndex: 0

    function _resolutionList(): list<string> {
        const raw = Browse.Settings.available_resolutions
        return raw === undefined || raw === null ? [] : raw
    }

    function _resolutionDisplay(value: string): string {
        // Empty resolution means "fall back to launcher.toml defaults",
        // which the Settings model treats as the platform default. Render
        // it as a translated label rather than an empty cell so the user
        // sees something selectable.
        return value === "" ? qsTr("Default") : value
    }

    function _currentResolutionIndex(): int {
        const list = settings._resolutionList()
        const cur = Browse.Settings.current_resolution
        for (let i = 0; i < list.length; i++)
            if (list[i] === cur)
                return i
        return -1
    }

    function _cycleResolution(direction: int): void {
        const list = settings._resolutionList()
        if (list.length === 0)
            return
        let idx = settings._currentResolutionIndex()
        if (idx < 0) {
            // Current value is off the curated list (custom value
            // persisted from a previous build, or the empty "Default"
            // sentinel). Snap to the first or last list entry depending
            // on direction so the user sees an immediate change.
            idx = direction > 0 ? -1 : 0
        }
        const next = ((idx + direction) % list.length + list.length) % list.length
        Browse.Settings.set_resolution(list[next])
    }

    function _buttonLayoutList(): list<string> {
        const raw = Browse.Settings.available_button_layouts
        return raw === undefined || raw === null ? [] : raw
    }

    function _languageList(): list<string> {
        const raw = Browse.Settings.available_languages
        return raw === undefined || raw === null ? [] : raw
    }

    function _languageDisplay(value: string): string {
        if (value === "en")
            return qsTr("English")
        if (value === "it_IT")
            return qsTr("Italian")
        return qsTr("Auto")
    }

    function _currentLanguageIndex(): int {
        const list = settings._languageList()
        const cur = Browse.Settings.current_language
        for (let i = 0; i < list.length; i++)
            if (list[i] === cur)
                return i
        return -1
    }

    function _cycleLanguage(direction: int): void {
        const list = settings._languageList()
        if (list.length === 0)
            return
        let idx = settings._currentLanguageIndex()
        if (idx < 0)
            idx = direction > 0 ? -1 : 0
        const next = ((idx + direction) % list.length + list.length) % list.length
        Browse.Settings.set_language(list[next])
    }

    function _buttonLayoutDisplay(value: string): string {
        if (value === "xbox")
            return qsTr("Xbox")
        if (value === "sony")
            return qsTr("Sony")
        return qsTr("Nintendo")
    }

    function _currentButtonLayoutIndex(): int {
        const list = settings._buttonLayoutList()
        const cur = Browse.Settings.current_button_layout
        for (let i = 0; i < list.length; i++)
            if (list[i] === cur)
                return i
        return -1
    }

    function _cycleButtonLayout(direction: int): void {
        const list = settings._buttonLayoutList()
        if (list.length === 0)
            return
        let idx = settings._currentButtonLayoutIndex()
        if (idx < 0)
            idx = direction > 0 ? -1 : 0
        const next = ((idx + direction) % list.length + list.length) % list.length
        Browse.Settings.set_button_layout(list[next])
    }

    function _setMouseEnabled(direction: int): void {
        Browse.Settings.set_mouse_enabled(direction > 0)
    }

    function _toggleMouseEnabled(): void {
        Browse.Settings.set_mouse_enabled(!Browse.Settings.current_mouse_enabled)
    }

    function _cycleFocused(direction: int): void {
        if (settings.fieldCount === 0)
            return
        const id = settings.fields[settings.currentIndex].id
        if (id === "resolution")
            settings._cycleResolution(direction)
        else if (id === "language")
            settings._cycleLanguage(direction)
        else if (id === "buttonLayout")
            settings._cycleButtonLayout(direction)
        else if (id === "mouseEnabled")
            settings._setMouseEnabled(direction)
    }

    function handleAction(action: string): void {
        if (action === "up") {
            if (settings.currentIndex > 0)
                settings.currentIndex--
        } else if (action === "down") {
            if (settings.currentIndex < settings.fieldCount - 1)
                settings.currentIndex++
        } else if (action === "left") {
            settings._cycleFocused(-1)
        } else if (action === "right") {
            settings._cycleFocused(1)
        } else if (action === "accept") {
            if (settings.fieldCount > 0
                && settings.fields[settings.currentIndex].id === "mouseEnabled")
                settings._toggleMouseEnabled()
        } else if (action === "cancel") {
            settings.requestHubScreen()
        }
    }

    // ── Visual tree ───────────────────────────────────────────────────────────

    TopStatusStrip {
        id: topStrip
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: Sizing.pctH(9)
        height: Sizing.pctH(7)
        title: qsTr("Settings")
        currentPage: 0
        totalPages: 0
        totalText: ""
    }

    // Form. Centered horizontally; width capped so the rows don't
    // stretch edge-to-edge on widescreen. Each row is a SettingsField.
    Column {
        id: form

        anchors.top: topStrip.bottom
        anchors.topMargin: Sizing.pctH(4)
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(parent.width - Sizing.pctW(10), Sizing.pctW(70))
        spacing: Sizing.pctH(1.5)
        visible: settings.fieldCount > 0

        Repeater {
            model: settings.fields

            SettingsField {
                id: fieldRow

                required property int index
                required property var modelData

                width: form.width
                isFocused: index === settings.currentIndex
                label: modelData.label
                value: modelData.id === "resolution"
                       ? settings._resolutionDisplay(Browse.Settings.current_resolution)
                       : modelData.id === "language"
                       ? settings._languageDisplay(Browse.Settings.current_language)
                       : modelData.id === "buttonLayout"
                       ? settings._buttonLayoutDisplay(Browse.Settings.current_button_layout)
                       : ""
                control: modelData.id === "mouseEnabled" ? "toggle" : "value"
                checked: Browse.Settings.current_mouse_enabled
                // Pickers wrap modulo, so both arrows apply when the
                // focused field has a populated option list.
                canCyclePrev: (modelData.id === "resolution"
                               && settings._resolutionList().length > 0)
                              || (modelData.id === "language"
                                  && settings._languageList().length > 1)
                              || (modelData.id === "buttonLayout"
                                  && settings._buttonLayoutList().length > 1)
                              || (modelData.id === "mouseEnabled"
                                  && Browse.Settings.current_mouse_enabled)
                canCycleNext: (modelData.id === "resolution"
                               && settings._resolutionList().length > 0)
                              || (modelData.id === "language"
                                  && settings._languageList().length > 1)
                              || (modelData.id === "buttonLayout"
                                  && settings._buttonLayoutList().length > 1)
                              || (modelData.id === "mouseEnabled"
                                  && !Browse.Settings.current_mouse_enabled)
                onHovered: settings.currentIndex = index
                onClicked: {
                    settings.currentIndex = index
                    if (modelData.id === "mouseEnabled")
                        settings._toggleMouseEnabled()
                }
            }
        }
    }

    // Empty-state placeholder shown on runtimes with no settings to
    // expose. Centered in the body so it doesn't compete with the
    // top strip or help bar.
    Text {
        anchors.centerIn: parent
        visible: settings.fieldCount === 0
        text: qsTr("No settings available on this platform")
        color: Theme.textLabel
        font.family: Theme.fontUi
        font.pixelSize: Sizing.fontSize(2.6)
        renderType: Text.NativeRendering
    }
}
