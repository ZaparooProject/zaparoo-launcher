# Zaparoo Launcher
# Copyright (c) 2026 The Zaparoo Project Contributors.
# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0

qt_add_library(zaparoo_ui_app STATIC)

# Fonts and images live in resources/ at the repo root. Qt requires that
# absolute-path resource files have a QT_RESOURCE_ALIAS set so the generated
# resource system can give them a stable, relative-looking path.
set(_RESOURCE_ROOT "${CMAKE_SOURCE_DIR}/resources")
set(_APP_RESOURCES
    "${_RESOURCE_ROOT}/fonts/PressStart2P.ttf"
    "${_RESOURCE_ROOT}/images/logo.png"
    "${_RESOURCE_ROOT}/images/placeholder/cover_generic.png"
)

foreach(_res IN LISTS _APP_RESOURCES)
    file(RELATIVE_PATH _alias "${_RESOURCE_ROOT}/.." "${_res}")
    set_source_files_properties("${_res}" PROPERTIES QT_RESOURCE_ALIAS "${_alias}")
endforeach()

qt_add_qml_module(
    zaparoo_ui_app
    URI Zaparoo.App
    VERSION 1.0
    QML_FILES
        Main.qml
        MainLayout.qml
    RESOURCES ${_APP_RESOURCES}
    IMPORTS
        Zaparoo.Ui
        Zaparoo.Theme
        Zaparoo.Browse
)

target_link_libraries(
    zaparoo_ui_app
    PUBLIC
        Qt6::Quick
        zaparoo_ui_componentsplugin
        zaparoo_ui_themeplugin
    PRIVATE
        Zaparoo::CompileOptions
)
