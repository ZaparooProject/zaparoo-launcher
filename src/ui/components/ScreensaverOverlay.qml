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
// the live scene, bakes an 80%-black scrim into that capture once via
// `Item.grabToImage`, and then displays the resulting opaque image as
// the screensaver background. A copy of the Zaparoo logo bounces 45°
// across the window. Software-renderer safe: the baked background is
// fully opaque so Qt's scene graph keeps it cached and only the small
// logo dirty rect repaints per frame; no translucent overlay is
// animated over busy content. State is purely in-memory (no persist).
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
    property url _bakedSource: ""
    // Holds the QQuickItemGrabResult object alive. Its `url` is only
    // resolvable while the grab-result QObject is referenced — drop
    // the reference and the Image stops painting. Letting the
    // callback's local go out of scope was the original bug: the
    // baked image showed nothing because the url backing it had
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
        overlay._bakedSource = "";
        overlay._grabResult = null;
        overlay._armed = true;
        // Wait two frames so the scrim Rectangle is actually rasterised
        // before we grab — `_armed = true` only marks the binding
        // dirty; the bake scrim does not show up in the next render
        // until the scene graph syncs and paints. A single 16 ms tick
        // is racy on the software adaptation (cold-start frames can
        // run long), so use a slightly longer hold to guarantee the
        // 80% darken is in the captured frame.
        bakeTimer.restart();
    }

    function deactivate(): void {
        if (!overlay._armed)
            return;
        bounceSegment.stop();
        bakeTimer.stop();
        holdBeforeBounce.stop();
        overlay._armed = false;
        overlay._bakedSource = "";
        overlay._grabResult = null;
        overlay._grabRoot = null;
    }

    // ── Bake-time scrim ──────────────────────────────────────────────
    // Translucent black, painted ONCE while the grab is pending. After
    // the callback assigns `_bakedSource`, the scrim hides and the
    // opaque baked image takes over — no translucent layer is ever
    // animated over.
    Rectangle {
        id: bakeScrim

        anchors.fill: parent
        color: "black"
        opacity: 0.8
        visible: overlay._armed && overlay._bakedSource === ""
    }

    // ── Baked scene ──────────────────────────────────────────────────
    // Opaque snapshot of (live scene + bake scrim) produced by
    // `Item.grabToImage`. Once visible it covers everything underneath
    // so Qt's scene graph stops painting the live screens — the only
    // dirty rect per frame is the bouncing logo above.
    Image {
        id: bakedBg

        anchors.fill: parent
        cache: false
        smooth: false
        asynchronous: false
        fillMode: Image.Stretch
        source: overlay._bakedSource
        visible: overlay._bakedSource !== ""
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
        visible: overlay._bakedSource !== ""
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
        id: bakeTimer
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
                overlay._bakedSource = result.url;
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
        if (!overlay._armed || overlay._bakedSource === "")
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
