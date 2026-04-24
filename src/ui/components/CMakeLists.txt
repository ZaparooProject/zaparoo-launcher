# Zaparoo Launcher
# Copyright (c) 2026 The Zaparoo Project Contributors.
# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0

qt_add_library(zaparoo_ui_components STATIC)

qt_add_qml_module(
    zaparoo_ui_components
    URI Zaparoo.Ui
    VERSION 1.0
    QML_FILES
        Carousel.qml
        CoverDelegate.qml
        FpsCounter.qml
        TextTileDelegate.qml
)

target_link_libraries(
    zaparoo_ui_components
    PUBLIC Qt6::Quick
    PRIVATE Zaparoo::CompileOptions
)
