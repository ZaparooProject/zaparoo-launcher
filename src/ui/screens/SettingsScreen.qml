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
// because the underlying `vmode` command lives on MiSTer's Linux framebuffer
// (currently hidden — the picker doesn't switch reliably yet). Button style
// is cross-platform and selects the resource directory for help-bar button
// glyphs (Style A/B/C → resources/images/buttons/{a,b,c}/). Mouse support
// is cross-platform and controls cursor visibility plus mouse hit targets.
//
// Pure input dispatcher: emits `requestHubScreen()` on Escape; left/
// right cycle the focused field's value via the model singleton.
Item {
    id: settings

    // Bound by MainLayout to `root.pendingTransition !== ""`. Settings
    // is a destination, never a source, so this is currently always
    // false when the screen is visible — kept for parity with the
    // other screens so the convention holds when a future routing
    // change adds a Settings-as-source path.
    property bool transitioning: false

    signal requestHubScreen()
    // Forward signal carrying the focused action row's id. The router
    // decides what the payload means — currently only "uploadLog" is
    // wired, which opens the log-upload modal.
    signal requestAccept(actionId: string)

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
        // Resolution row hidden — `vmode` switching isn't reliable yet.
        // Restore by re-enabling this block once the MiSTer-side path is
        // trusted again; the picker plumbing in `_cycleResolution` and
        // the Settings model's `current_resolution` property are still
        // wired so the row works as soon as it's added back.
        // if (Browse.Settings.is_mister) {
        //     out.push({
        //         id: "resolution",
        //         label: qsTr("Resolution")
        //     })
        // }
        out.push({
            id: "language",
            label: qsTr("Language")
        })
        out.push({
            id: "buttonLayout",
            label: qsTr("Button style")
        })
        out.push({
            id: "mouseEnabled",
            label: qsTr("Mouse support")
        })
        out.push({
            id: "updateMediaDb",
            label: qsTr("Update media database")
        })
        out.push({
            id: "runScraper",
            label: qsTr("Scrape metadata")
        })
        out.push({
            id: "debugLogging",
            label: qsTr("Debug logging")
        })
        out.push({
            id: "uploadLog",
            label: qsTr("Upload log file")
        })
        return out
    }

    // Live-state caption helpers for the action rows. Empty string when
    // the row's operation is idle, so the field renders as quietly as
    // the cycler rows above. Pause/cancel paths use the same vocabulary
    // as the Core TUI so the launcher looks like a third surface for
    // the same flow.
    function _indexActionStatus(): string {
        if (Browse.MediaStatus.optimizing)
            return qsTr("Optimizing")
        if (Browse.MediaStatus.indexing)
            return Browse.MediaStatus.paused ? qsTr("Paused") : qsTr("In progress")
        return ""
    }

    function _scrapeActionStatus(): string {
        if (Browse.MediaStatus.scraping)
            return Browse.MediaStatus.scrape_paused ? qsTr("Paused") : qsTr("In progress")
        return ""
    }

    // Index and scrape can't run concurrently — Core serialises them.
    // While one is in flight the *other* row is non-actionable so we
    // don't queue a request that Core will reject.
    readonly property bool _indexBusy:
        Browse.MediaStatus.indexing || Browse.MediaStatus.optimizing
    readonly property bool _scrapeBusy: Browse.MediaStatus.scraping

    function _triggerIndex(): void {
        if (settings._scrapeBusy)
            return
        if (settings._indexBusy)
            Browse.MediaStatus.cancel_index()
        else
            Browse.MediaStatus.start_index()
    }

    function _triggerScrape(): void {
        if (settings._indexBusy)
            return
        if (settings._scrapeBusy)
            Browse.MediaStatus.cancel_scrape()
        else
            Browse.MediaStatus.start_scrape()
    }

    readonly property int fieldCount: settings.fields.length
    readonly property bool focusedFieldIsToggle: {
        if (settings.fieldCount === 0)
            return false
        const id = settings.fields[settings.currentIndex].id
        return id === "mouseEnabled" || id === "debugLogging"
    }
    // True when the focused field is an action button (updateMediaDb,
    // runScraper, uploadLog). Drives the help-bar Accept hint.
    readonly property bool focusedFieldIsAction: {
        if (settings.fieldCount === 0)
            return false
        const id = settings.fields[settings.currentIndex].id
        return id === "updateMediaDb"
               || id === "runScraper"
               || id === "uploadLog"
    }
    // True when the focused action's matching operation is currently
    // running, so the help bar can label Accept as "Cancel" rather
    // than "Start".
    readonly property bool focusedActionBusy: {
        if (settings.fieldCount === 0)
            return false
        const id = settings.fields[settings.currentIndex].id
        if (id === "updateMediaDb")
            return settings._indexBusy
        if (id === "runScraper")
            return settings._scrapeBusy
        return false
    }
    // True when the focused action can't run right now because the
    // *other* media operation has the bus. Drives the dimmed-row
    // visual and lets the help bar drop the Accept hint instead of
    // promising a press that will silently no-op.
    readonly property bool focusedActionDisabled: {
        if (settings.fieldCount === 0)
            return false
        const id = settings.fields[settings.currentIndex].id
        if (id === "updateMediaDb")
            return settings._scrapeBusy
        if (id === "runScraper")
            return settings._indexBusy
        return false
    }

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
        if (value === "b")
            return qsTr("Style B")
        if (value === "c")
            return qsTr("Style C")
        return qsTr("Style A")
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

    function _setDebugLogging(direction: int): void {
        Browse.Settings.set_debug_logging(direction > 0)
    }

    function _toggleDebugLogging(): void {
        Browse.Settings.set_debug_logging(!Browse.Settings.current_debug_logging)
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
        else if (id === "debugLogging")
            settings._setDebugLogging(direction)
        // Action fields ignore left/right — they only respond to accept.
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
            if (settings.fieldCount === 0)
                return
            const id = settings.fields[settings.currentIndex].id
            if (id === "mouseEnabled")
                settings._toggleMouseEnabled()
            else if (id === "debugLogging")
                settings._toggleDebugLogging()
            else if (id === "updateMediaDb")
                settings._triggerIndex()
            else if (id === "runScraper")
                settings._triggerScrape()
            else if (id === "uploadLog")
                settings.requestAccept("uploadLog")
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
                // Index and scrape can't run together; while one
                // operation is in flight the other row dims and its
                // MouseArea stops responding. Keyboard Accept is
                // separately gated in `_triggerIndex`/`_triggerScrape`.
                enabled: modelData.id === "updateMediaDb"
                         ? !settings._scrapeBusy
                         : modelData.id === "runScraper"
                         ? !settings._indexBusy
                         : true
                label: modelData.label
                value: modelData.id === "resolution"
                       ? settings._resolutionDisplay(Browse.Settings.current_resolution)
                       : modelData.id === "language"
                       ? settings._languageDisplay(Browse.Settings.current_language)
                       : modelData.id === "buttonLayout"
                       ? settings._buttonLayoutDisplay(Browse.Settings.current_button_layout)
                       : ""
                control: modelData.id === "mouseEnabled" || modelData.id === "debugLogging"
                         ? "toggle"
                         : (modelData.id === "updateMediaDb"
                            || modelData.id === "runScraper"
                            || modelData.id === "uploadLog") ? "action"
                         : "value"
                checked: modelData.id === "debugLogging"
                         ? Browse.Settings.current_debug_logging
                         : Browse.Settings.current_mouse_enabled
                actionStatus: modelData.id === "updateMediaDb"
                              ? settings._indexActionStatus()
                              : modelData.id === "runScraper"
                              ? settings._scrapeActionStatus()
                              : ""
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
                              || (modelData.id === "debugLogging"
                                  && Browse.Settings.current_debug_logging)
                canCycleNext: (modelData.id === "resolution"
                               && settings._resolutionList().length > 0)
                              || (modelData.id === "language"
                                  && settings._languageList().length > 1)
                              || (modelData.id === "buttonLayout"
                                  && settings._buttonLayoutList().length > 1)
                              || (modelData.id === "mouseEnabled"
                                  && !Browse.Settings.current_mouse_enabled)
                              || (modelData.id === "debugLogging"
                                  && !Browse.Settings.current_debug_logging)
                onHovered: settings.currentIndex = index
                onClicked: {
                    settings.currentIndex = index
                    if (modelData.id === "mouseEnabled")
                        settings._toggleMouseEnabled()
                    else if (modelData.id === "debugLogging")
                        settings._toggleDebugLogging()
                }
                // Action rows route through `onAccepted` only (see
                // `SettingsField.qml`'s MouseArea), so the focus
                // commit lives here too — clicking an action row
                // moves focus before firing the action.
                onAccepted: {
                    settings.currentIndex = index
                    if (modelData.id === "updateMediaDb")
                        settings._triggerIndex()
                    else if (modelData.id === "runScraper")
                        settings._triggerScrape()
                    else if (modelData.id === "uploadLog")
                        settings.requestAccept("uploadLog")
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
