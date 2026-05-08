// Design-time entry point. Opens MainLayout at a fixed 1280×720 canvas
// so Qt Design Studio has something deterministic to render.
import QtQuick
import Zaparoo.App
import Zaparoo.Theme

MainLayout {
    width: 1280
    height: 720
    Component.onCompleted: {
        Sizing.screenWidth = width;
        Sizing.screenHeight = height;
    }
}
