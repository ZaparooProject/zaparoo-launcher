// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
// `Item.grabToImage` is invoked through a property whose static type
// is `QQuickItem`, so qmllint's compiler check flags the call as
// shadowable until the qmltypes schema grows method-level finality.
// Same pattern as HeaderBar.qml — suppress file-wide.
// qmllint disable compiler

import QtQuick
import Zaparoo.Theme

// Screen-burn protection. After an idle timeout the launcher captures
// the live scene with `Item.grabToImage` and stacks three static
// layers — solid-black backstop, opaque snapshot, 80% black scrim —
// behind a single bouncing copy of the Zaparoo logo.
//
// Why three static layers instead of baking everything into one
// image: the original implementation tried to bake (snapshot + 80%
// scrim) into a single opaque QImage by painting the scrim above
// the live scene and grabbing that composite. On Qt's Software
// adaptation the grab raced the scrim's first paint — `_armed` only
// dirties the binding; the Rectangle is not actually rasterised
// until the next sync — so the captured pixmap held just the live
// scene with no darken. Even with a longer pre-grab delay the
// behaviour was unreliable across cold-start frames. Stacking the
// scrim as its own QML node avoids that race entirely: the user
// sees the darken from the moment the overlay is armed, regardless
// of whether the grab has completed yet.
//
// CLAUDE.md's "no translucent overlay over a screen body" rule
// targets translucent nodes above *animated* content (screens,
// transitions): every animated frame underneath propagates up
// through the translucent layer and forces a repaint of the
// blended pixels. Here the only thing under the scrim is the
// snapshot Image (or the solid-black backstop while the snapshot
// is still arriving). Both are static, so the only dirty rect
// per frame is the bouncing logo's own bounding box — three
// blits at that small rect (snapshot patch, scrim patch, logo)
// and nothing else. State is purely in-memory; the timeout
// itself is persisted on `Browse.Settings.current_screensaver_timeout`.
Item {
    id: overlay

    // Public API ─────────────────────────────────────────────────────
    // True between activate() and deactivate(). Visible-bound below.
    readonly property bool armed: overlay._armed
    // Source for the bouncing logo copy on top of the baked scrim.
    property url logoSource: ""

    // Emitted when the user clicks/taps anywhere on the overlay while
    // armed. Main.qml uses this to run the same dismiss path as a
    // keyboard/gamepad press (deactivate + reset idle + clear repeat).
    signal userDismissed

    // Internal ───────────────────────────────────────────────────────
    // The Item to capture into the baked background. Provided by the
    // caller at activate() time so the overlay does not assume any
    // particular root.
    property Item _grabRoot: null
    property bool _armed: false
    property url _snapshotSource: ""
    // Holds the QQuickItemGrabResult object alive. Its `url` is only
    // resolvable while the grab-result QObject is referenced — drop
    // the reference and the Image stops painting. Letting the
    // callback's local go out of scope was the original bug: the
    // snapshot image showed nothing because the url backing it had
    // already been freed.
    property var _grabResult: null
    // Logo geometry copied from the live header logo, in the overlay's
    // own coordinate space.
    property real _logoStartX: 0
    property real _logoStartY: 0
    property real _logoStartW: 0
    property real _logoStartH: 0
    // Bounce direction. (+1, +1) starts down-right per spec; flipped on
    // each wall hit by `_scheduleNextBounce`.
    property int _dx: 1
    property int _dy: 1

    visible: overlay._armed

    // Activate: capture the scene with a darkened scrim baked into a
    // single opaque image, hold the still copy of the logo at its
    // original position for 1 s, then begin the 45° bounce.
    function activate(grabRootItem: Item, logoSrc: url, startRect: rect): void {
        if (overlay._armed)
            return;
        overlay._grabRoot = grabRootItem;
        overlay.logoSource = logoSrc;
        overlay._logoStartX = Sizing.px(startRect.x);
        overlay._logoStartY = Sizing.px(startRect.y);
        overlay._logoStartW = Sizing.px(startRect.width);
        overlay._logoStartH = Sizing.px(startRect.height);
        ssLogo.x = overlay._logoStartX;
        ssLogo.y = overlay._logoStartY;
        ssLogo.width = overlay._logoStartW;
        ssLogo.height = overlay._logoStartH;
        overlay._dx = 1;
        overlay._dy = 1;
        overlay._snapshotSource = "";
        overlay._grabResult = null;
        overlay._armed = true;
        // Capture the live scene one tick later so the scrim Rectangle
        // (which becomes visible the instant `_armed` flips) is in the
        // grab too. The scrim is also stacked on top of the snapshot
        // as a separate node, so even if the snapshot were captured
        // before the scrim the user would still see the darken — the
        // double-source-of-truth is intentional.
        snapshotTimer.restart();
    }

    function deactivate(): void {
        if (!overlay._armed)
            return;
        bounceSegment.stop();
        snapshotTimer.stop();
        holdBeforeBounce.stop();
        overlay._armed = false;
        overlay._snapshotSource = "";
        overlay._grabResult = null;
        overlay._grabRoot = null;
    }

    // ── Solid-black backstop ─────────────────────────────────────────
    // Opaque, painted the instant the screensaver arms. Guarantees a
    // dark canvas under the scrim before the snapshot grab arrives,
    // and acts as a fallback if the grab fails for any reason.
    Rectangle {
        id: hardBackstop

        anchors.fill: parent
        color: "black"
        visible: overlay._armed
    }

    // ── Live-scene snapshot ──────────────────────────────────────────
    // Opaque copy of the scene captured by `Item.grabToImage` at
    // activation time. Sits above the backstop so the snapshot fades
    // through the scrim above it. Source binds to the grab result's
    // url; `_grabResult` is held on the overlay so the underlying
    // QImage stays alive (the url alone goes stale when the result
    // QObject is GC'd).
    Image {
        id: snapshotImage

        anchors.fill: parent
        cache: false
        smooth: false
        asynchronous: false
        fillMode: Image.Stretch
        source: overlay._snapshotSource
        visible: overlay._snapshotSource !== ""
    }

    // ── Static darken scrim ──────────────────────────────────────────
    // Translucent black on top of the snapshot. Static while the
    // overlay is armed — only the logo above moves — so on the
    // software adaptation the only per-frame dirty rect is the
    // logo's bounding box. The scrim's blend cost stays bounded to
    // that small patch instead of the full screen.
    Rectangle {
        id: darkenScrim

        anchors.fill: parent
        color: "black"
        opacity: 0.8
        visible: overlay._armed
    }

    // ── Bouncing logo ────────────────────────────────────────────────
    // Single Image element whose `x`/`y` are driven by a chained
    // ParallelAnimation. PreserveAspectFit + smooth: false keeps the
    // raster crisp at any window size; the start geometry mirrors the
    // header logo so the activation looks like the logo dimming in
    // place before walking off.
    Image {
        id: ssLogo

        source: overlay.logoSource
        fillMode: Image.PreserveAspectFit
        smooth: false
        cache: true
        visible: overlay._armed
    }

    // Click/tap dismissal. Enabled only while armed so the overlay
    // does not eat input on the live screens. The top-level idle
    // MouseArea (Qt.NoButton) above this lets press events fall
    // through to here.
    MouseArea {
        id: dismissArea

        anchors.fill: parent
        enabled: overlay._armed
        visible: enabled
        hoverEnabled: false
        acceptedButtons: Qt.AllButtons
        onPressed: mouse => {
            overlay.userDismissed();
            mouse.accepted = true;
        }
    }

    Timer {
        id: snapshotTimer
        interval: 50
        repeat: false
        onTriggered: {
            if (!overlay._armed || !overlay._grabRoot)
                return;
            overlay._grabRoot.grabToImage(function (result) {
                if (!overlay._armed)
                    return;
                // Pin the QQuickItemGrabResult on a property *before*
                // assigning its url — otherwise the callback returns,
                // `result` becomes unreferenced, the engine releases
                // the underlying QImage, and the Image element below
                // ends up with a dangling url it cannot resolve.
                overlay._grabResult = result;
                overlay._snapshotSource = result.url;
                holdBeforeBounce.restart();
            });
        }
    }

    Timer {
        id: holdBeforeBounce
        interval: 1000
        repeat: false
        onTriggered: overlay._scheduleNextBounce()
    }

    ParallelAnimation {
        id: bounceSegment

        NumberAnimation {
            id: animX
            target: ssLogo
            property: "x"
            easing.type: Easing.Linear
        }
        NumberAnimation {
            id: animY
            target: ssLogo
            property: "y"
            easing.type: Easing.Linear
        }
        onFinished: overlay._scheduleNextBounce()
    }

    function _scheduleNextBounce(): void {
        if (!overlay._armed || overlay._snapshotSource === "")
            return;
        const minX = 0;
        const minY = 0;
        const maxX = overlay.width - ssLogo.width;
        const maxY = overlay.height - ssLogo.height;
        if (maxX <= minX || maxY <= minY)
            return;
        // Snap-to-edge correction. Floating-point drift can leave the
        // logo a sub-pixel shy of the wall when the previous segment
        // ended; treat anything within 0.5 px as flush so the new
        // direction flips deterministically.
        if (ssLogo.x <= minX + 0.5)
            overlay._dx = 1;
        else if (ssLogo.x >= maxX - 0.5)
            overlay._dx = -1;
        if (ssLogo.y <= minY + 0.5)
            overlay._dy = 1;
        else if (ssLogo.y >= maxY - 0.5)
            overlay._dy = -1;
        const distX = overlay._dx > 0 ? maxX - ssLogo.x : ssLogo.x - minX;
        const distY = overlay._dy > 0 ? maxY - ssLogo.y : ssLogo.y - minY;
        const dist = Math.min(distX, distY);
        if (dist < 1)
            return;
        const endX = Sizing.px(ssLogo.x + overlay._dx * dist);
        const endY = Sizing.px(ssLogo.y + overlay._dy * dist);
        // Speed = full window width per 3 s, scaled so a 45° vector
        // covers the same screen-width-per-second regardless of the
        // current resolution. `dist` is along the diagonal; using the
        // window-width baseline gives a pleasant pace from 240p to
        // 1080p.
        const speedPxPerS = overlay.width > 0 ? overlay.width / 3.0 : 1;
        const dur = Math.max(16, Math.round((dist / speedPxPerS) * 1000));
        bounceSegment.stop();
        animX.from = ssLogo.x;
        animX.to = endX;
        animX.duration = dur;
        animY.from = ssLogo.y;
        animY.to = endY;
        animY.duration = dur;
        bounceSegment.start();
    }
}
