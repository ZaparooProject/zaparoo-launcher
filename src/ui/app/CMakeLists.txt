# Zaparoo Launcher
# Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0

qt_add_library(zaparoo_ui_app STATIC)

# Fonts and images live in resources/ at the repo root. Qt requires that
# absolute-path resource files have a QT_RESOURCE_ALIAS set so the generated
# resource system can give them a stable, relative-looking path.
set(_RESOURCE_ROOT "${CMAKE_SOURCE_DIR}/resources")
set(_APP_RESOURCES
    "${_RESOURCE_ROOT}/fonts/AtkinsonHyperlegible-Regular.ttf"
    "${_RESOURCE_ROOT}/fonts/AtkinsonHyperlegible-Bold.ttf"
    "${_RESOURCE_ROOT}/images/logo.png"
    # Tiled circuit-trace background. The .png is pre-rendered from the
    # .svg at the pattern's native 304×304 (rsvg-convert / Inkscape /
    # ImageMagick); shipping both keeps the source available for
    # re-rendering without forcing a runtime QtSvg dependency.
    "${_RESOURCE_ROOT}/images/bg-circuit.png"
    "${_RESOURCE_ROOT}/images/bg-circuit.svg"
)

# System and category logos: PNGs dropped into
# resources/images/systems/<SystemId>.png and
# resources/images/categories/<CategoryName>.png (curated from
# PRO100BYTE/console-logos — see src/LICENSES/console-logos-ATTRIBUTION.txt).
# Globbed so adding/removing a logo doesn't require touching this file; we
# CONFIGURE_DEPENDS so CMake re-globs on directory changes.
file(GLOB _SYSTEM_LOGOS CONFIGURE_DEPENDS
    "${_RESOURCE_ROOT}/images/systems/*.png")
file(GLOB _CATEGORY_LOGOS CONFIGURE_DEPENDS
    "${_RESOURCE_ROOT}/images/categories/*.png")
file(GLOB _STATUS_ICONS CONFIGURE_DEPENDS
    "${_RESOURCE_ROOT}/images/status/*.xpm")
list(APPEND _APP_RESOURCES ${_SYSTEM_LOGOS} ${_CATEGORY_LOGOS} ${_STATUS_ICONS})

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
        Zaparoo.Screens
        Zaparoo.Browse
)

target_link_libraries(
    zaparoo_ui_app
    PUBLIC
        Qt6::Quick
        zaparoo_ui_componentsplugin
        zaparoo_ui_screensplugin
        zaparoo_ui_themeplugin
    PRIVATE
        Zaparoo::CompileOptions
)
