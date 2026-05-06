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
// glyphs (Style A/B/C/D → resources/images/buttons/{a,b,c,d}/). Mouse support
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

    // Field registry. Each entry's `kind` is `"header"` (non-focusable
    // group label) or `"field"` (a navigable row). Field entries also
    // carry an `id` that handleAction routes to the right model setter.
    // Keeping this as data (rather than a Repeater of typed children)
    // makes adding rows a one-line edit and keeps navigation uniform.
    //
    // Section grouping mirrors the Settings menus on Switch/Xbox/
    // Playnite/Pegasus: a single page with non-focusable headers
    // splitting commonly-used controls (General, Library) from rarer
    // diagnostics-flavoured ones (Advanced).
    readonly property var fields: {
        const out = []
        out.push({ kind: "header", label: qsTr("General") })
        // Resolution row hidden — `vmode` switching isn't reliable yet.
        // Restore by re-enabling this block once the MiSTer-side path is
        // trusted again; the picker plumbing in `_cycleResolution` and
        // the Settings model's `current_resolution` property are still
        // wired so the row works as soon as it's added back.
        // if (Browse.Settings.is_mister) {
        //     out.push({
        //         kind: "field",
        //         id: "resolution",
        //         label: qsTr("Resolution")
        //     })
        // }
        out.push({
            kind: "field",
            id: "language",
            label: qsTr("Language")
        })
        out.push({
            kind: "field",
            id: "browseLayout",
            label: qsTr("Browsing layout")
        })
        out.push({
            kind: "field",
            id: "buttonLayout",
            label: qsTr("Button style")
        })
        out.push({ kind: "header", label: qsTr("Library") })
        out.push({
            kind: "field",
            id: "updateMediaDb",
            label: qsTr("Update media database")
        })
        out.push({
            kind: "field",
            id: "runScraper",
            label: qsTr("Scrape metadata")
        })
        out.push({ kind: "header", label: qsTr("Advanced") })
        out.push({
            kind: "field",
            id: "mouseEnabled",
            label: qsTr("Mouse support")
        })
        out.push({
            kind: "field",
            id: "debugLogging",
            label: qsTr("Debug logging")
        })
        out.push({
            kind: "field",
            id: "uploadLog",
            label: qsTr("Upload log file")
        })
        out.push({
            kind: "field",
            id: "aboutLicense",
            label: qsTr("About / License")
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

    // True iff `idx` points at a focusable field row (not a header,
    // not out of bounds). All `focused*` derivations early-return on
    // header indices so a defensive out-of-band write to currentIndex
    // can't mis-light the help bar.
    function _isField(idx: int): bool {
        if (idx < 0 || idx >= settings.fieldCount)
            return false
        return settings.fields[idx].kind === "field"
    }

    // First focusable row in the registry. Used to seed `currentIndex`
    // at construction; returns -1 only if every entry is a header
    // (registry mistake — shouldn't happen).
    function _firstNavigableIndex(): int {
        for (let i = 0; i < settings.fieldCount; i++)
            if (settings.fields[i].kind === "field")
                return i
        return -1
    }

    // Walk from `from` in `direction` (±1) until we hit a focusable
    // row or run off the registry. Headers are transparent — Up/Down
    // skip across them so the user feels a single flat list.
    function _seekNavigable(from: int, direction: int): int {
        let i = from + direction
        while (i >= 0 && i < settings.fieldCount) {
            if (settings.fields[i].kind === "field")
                return i
            i += direction
        }
        return from
    }

    readonly property bool focusedFieldIsToggle: {
        if (!settings._isField(settings.currentIndex))
            return false
        const id = settings.fields[settings.currentIndex].id
        return id === "mouseEnabled" || id === "debugLogging"
    }
    // True when the focused field is an action button (updateMediaDb,
    // runScraper, uploadLog, aboutLicense). Drives the help-bar Accept
    // hint and the SettingsField chevron.
    readonly property bool focusedFieldIsAction: {
        if (!settings._isField(settings.currentIndex))
            return false
        const id = settings.fields[settings.currentIndex].id
        return id === "updateMediaDb"
               || id === "runScraper"
               || id === "uploadLog"
               || id === "aboutLicense"
    }
    // Verb shown on the help-bar Accept hint for the focused action
    // row. Index/scrape flip between Start and Cancel because the press
    // toggles the in-flight operation; uploadLog and aboutLicense are
    // single-press triggers, with aboutLicense reading "Open" because
    // the press navigates rather than starts a job.
    readonly property string focusedActionLabel: {
        if (!settings._isField(settings.currentIndex))
            return ""
        const id = settings.fields[settings.currentIndex].id
        if (id === "updateMediaDb" || id === "runScraper")
            return settings.focusedActionBusy ? qsTr("Cancel") : qsTr("Start")
        if (id === "uploadLog")
            return qsTr("Start")
        if (id === "aboutLicense")
            return qsTr("Open")
        return ""
    }
    // True when the focused action's matching operation is currently
    // running, so the help bar can label Accept as "Cancel" rather
    // than "Start".
    readonly property bool focusedActionBusy: {
        if (!settings._isField(settings.currentIndex))
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
        if (!settings._isField(settings.currentIndex))
            return false
        const id = settings.fields[settings.currentIndex].id
        if (id === "updateMediaDb")
            return settings._scrapeBusy
        if (id === "runScraper")
            return settings._indexBusy
        return false
    }

    // Initial focus: first navigable row. The binding evaluates once
    // (no reactive dependencies inside `_firstNavigableIndex`) and is
    // broken the first time the user moves focus — handleAction's
    // up/down branches assign to `currentIndex` directly. Falling back
    // to 0 covers the all-headers degenerate case; helpers below
    // early-return on `_isField(0) === false` if it ever lands there.
    property int currentIndex: {
        const idx = settings._firstNavigableIndex()
        return idx >= 0 ? idx : 0
    }

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

    function _browseLayoutList(): list<string> {
        const raw = Browse.Settings.available_browse_layouts
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

    function _browseLayoutDisplay(value: string): string {
        if (value === "list")
            return qsTr("Detailed list view")
        return qsTr("Grid view")
    }

    function _currentBrowseLayoutIndex(): int {
        const list = settings._browseLayoutList()
        const cur = Browse.Settings.current_browse_layout
        for (let i = 0; i < list.length; i++)
            if (list[i] === cur)
                return i
        return -1
    }

    function _cycleBrowseLayout(direction: int): void {
        const list = settings._browseLayoutList()
        if (list.length === 0)
            return
        let idx = settings._currentBrowseLayoutIndex()
        if (idx < 0)
            idx = direction > 0 ? -1 : 0
        const next = ((idx + direction) % list.length + list.length) % list.length
        Browse.Settings.set_browse_layout(list[next])
    }

    function _buttonLayoutDisplay(value: string): string {
        if (value === "b")
            return qsTr("Style B")
        if (value === "c")
            return qsTr("Style C")
        if (value === "d")
            return qsTr("Style D")
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
        if (!settings._isField(settings.currentIndex))
            return
        const id = settings.fields[settings.currentIndex].id
        if (id === "resolution")
            settings._cycleResolution(direction)
        else if (id === "language")
            settings._cycleLanguage(direction)
        else if (id === "browseLayout")
            settings._cycleBrowseLayout(direction)
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
            settings.currentIndex =
                settings._seekNavigable(settings.currentIndex, -1)
        } else if (action === "down") {
            settings.currentIndex =
                settings._seekNavigable(settings.currentIndex, 1)
        } else if (action === "left") {
            settings._cycleFocused(-1)
        } else if (action === "right") {
            settings._cycleFocused(1)
        } else if (action === "accept") {
            if (!settings._isField(settings.currentIndex))
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
            else if (id === "aboutLicense")
                settings.requestAccept("aboutLicense")
        } else if (action === "cancel") {
            settings.requestHubScreen()
        }
    }

    // ── Visual tree ───────────────────────────────────────────────────────────

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        onClicked: settings.requestHubScreen()
    }

    TopStatusStrip {
        id: topStrip
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: Sizing.headerBottom
        height: Sizing.pctH(7)
        title: qsTr("Settings")
        currentPage: 0
        totalPages: 0
        totalText: ""
    }

    // Scroll focused row into view if it sits outside the Flickable's
    // current viewport. No-op for header indices (they aren't focusable
    // and currentIndex never lands on one in normal flow). Bind via
    // onCurrentIndexChanged below; no animation — software-renderer
    // budget can't pay for a moving column behind a focus border.
    function _scrollFocusedIntoView(): void {
        if (!settings._isField(settings.currentIndex))
            return
        const row = rowRepeater.itemAt(settings.currentIndex)
        if (row === null)
            return
        const top = row.y
        const bottom = top + row.height
        if (top < flickable.contentY)
            flickable.contentY = top
        else if (bottom > flickable.contentY + flickable.height)
            flickable.contentY = bottom - flickable.height
    }

    onCurrentIndexChanged: settings._scrollFocusedIntoView()

    // Form lives in a Flickable so the section bands can grow past
    // a single screen without dropping off-frame. Width capped so
    // the rows don't stretch edge-to-edge on widescreen; bottom
    // margin clears the help bar (pctH(6)) plus a small gap.
    Flickable {
        id: flickable

        anchors.top: topStrip.bottom
        anchors.topMargin: Sizing.pctH(2)
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Sizing.pctH(8)
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(parent.width - Sizing.pctW(10), Sizing.pctW(70))
        contentWidth: width
        contentHeight: form.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: form

            width: parent.width
            spacing: Sizing.pctH(1.5)
            visible: settings.fieldCount > 0

            Repeater {
                id: rowRepeater
                model: settings.fields

                // Wrapper row — both potential children exist but only
                // the kind-matching one paints. A Loader would also
                // work, but binding-through-`parent.modelData` adds
                // static-analysis friction under
                // ComponentBehavior:Bound; the wrapper Item is cheap
                // (≤ 3 headers + ≤ 7 fields) and keeps every
                // field-row binding readable in place.
                Item {
                    id: row

                    required property int index
                    required property var modelData

                    readonly property bool isHeader:
                        modelData.kind === "header"

                    width: form.width
                    implicitHeight: row.isHeader
                                    ? header.implicitHeight
                                    : field.implicitHeight

                    SettingsSectionHeader {
                        id: header
                        visible: row.isHeader
                        anchors.left: parent.left
                        anchors.right: parent.right
                        label: row.modelData.label
                    }

                    SettingsField {
                        id: field
                        visible: !row.isHeader
                        anchors.left: parent.left
                        anchors.right: parent.right
                        isFocused: row.index === settings.currentIndex
                        // Index and scrape can't run together; while
                        // one operation is in flight the other row
                        // dims and its MouseArea stops responding.
                        // Keyboard Accept is separately gated in
                        // `_triggerIndex`/`_triggerScrape`.
                        enabled: row.modelData.id === "updateMediaDb"
                                 ? !settings._scrapeBusy
                                 : row.modelData.id === "runScraper"
                                 ? !settings._indexBusy
                                 : true
                        label: row.modelData.label
                        value: row.modelData.id === "resolution"
                               ? settings._resolutionDisplay(Browse.Settings.current_resolution)
                               : row.modelData.id === "language"
                               ? settings._languageDisplay(Browse.Settings.current_language)
                               : row.modelData.id === "browseLayout"
                               ? settings._browseLayoutDisplay(Browse.Settings.current_browse_layout)
                               : row.modelData.id === "buttonLayout"
                               ? settings._buttonLayoutDisplay(Browse.Settings.current_button_layout)
                               : ""
                        control: row.modelData.id === "mouseEnabled"
                                 || row.modelData.id === "debugLogging"
                                 ? "toggle"
                                 : (row.modelData.id === "updateMediaDb"
                                    || row.modelData.id === "runScraper"
                                    || row.modelData.id === "uploadLog"
                                    || row.modelData.id === "aboutLicense") ? "action"
                                 : "value"
                        checked: row.modelData.id === "debugLogging"
                                 ? Browse.Settings.current_debug_logging
                                 : Browse.Settings.current_mouse_enabled
                        actionStatus: row.modelData.id === "updateMediaDb"
                                      ? settings._indexActionStatus()
                                      : row.modelData.id === "runScraper"
                                      ? settings._scrapeActionStatus()
                                      : ""
                        // Pickers wrap modulo, so both arrows apply
                        // when the focused field has a populated
                        // option list.
                        canCyclePrev: (row.modelData.id === "resolution"
                                       && settings._resolutionList().length > 0)
                                      || (row.modelData.id === "language"
                                          && settings._languageList().length > 1)
                                      || (row.modelData.id === "browseLayout"
                                          && settings._browseLayoutList().length > 1)
                                      || (row.modelData.id === "buttonLayout"
                                          && settings._buttonLayoutList().length > 1)
                                      || (row.modelData.id === "mouseEnabled"
                                          && Browse.Settings.current_mouse_enabled)
                                      || (row.modelData.id === "debugLogging"
                                          && Browse.Settings.current_debug_logging)
                        canCycleNext: (row.modelData.id === "resolution"
                                       && settings._resolutionList().length > 0)
                                      || (row.modelData.id === "language"
                                          && settings._languageList().length > 1)
                                      || (row.modelData.id === "browseLayout"
                                          && settings._browseLayoutList().length > 1)
                                      || (row.modelData.id === "buttonLayout"
                                          && settings._buttonLayoutList().length > 1)
                                      || (row.modelData.id === "mouseEnabled"
                                          && !Browse.Settings.current_mouse_enabled)
                                      || (row.modelData.id === "debugLogging"
                                          && !Browse.Settings.current_debug_logging)
                        onHovered: settings.currentIndex = row.index
                        onClicked: {
                            settings.currentIndex = row.index
                            if (row.modelData.id === "mouseEnabled")
                                settings._toggleMouseEnabled()
                            else if (row.modelData.id === "debugLogging")
                                settings._toggleDebugLogging()
                        }
                        onRightClicked: settings.requestHubScreen()
                        // Action rows route through `onAccepted` only
                        // (see `SettingsField.qml`'s MouseArea), so
                        // the focus commit lives here too — clicking
                        // an action row moves focus before firing the
                        // action.
                        onAccepted: {
                            settings.currentIndex = row.index
                            if (row.modelData.id === "updateMediaDb")
                                settings._triggerIndex()
                            else if (row.modelData.id === "runScraper")
                                settings._triggerScrape()
                            else if (row.modelData.id === "uploadLog")
                                settings.requestAccept("uploadLog")
                            else if (row.modelData.id === "aboutLicense")
                                settings.requestAccept("aboutLicense")
                        }
                    }
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
