# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
# SPDX-FileCopyrightText: 2026 Callan Barrett

qt_add_executable(launcher main.cpp MiSterRuntime.cpp MiSterRuntime.h)

target_compile_definitions(
    launcher
    PRIVATE ZAPAROO_VERSION="${CMAKE_PROJECT_VERSION}"
)

# Detect static Qt by inspecting Qt6::Core's actual link type rather than
# BUILD_SHARED_LIBS, which may be unset when invoking via qt-cmake.
get_target_property(_qt6_core_type Qt6::Core TYPE)

# For static builds (MiSTer ARM32), load the QML plugin CMake targets from
# Qt6Qml/QmlPlugins/ — they are not loaded by find_package(Qt6 ...) by default.
# qt_import_qml_plugins (called below) uses qmlimportscanner to find which QML
# modules the app needs, then links the corresponding targets; but those targets
# must already exist in scope when the linker step runs.
# Also load the linuxfb platform plugin, whose config lives inside Qt6Gui/ rather
# than a standalone Qt6QLinuxFbIntegrationPlugin/ directory.
if(_qt6_core_type STREQUAL "STATIC_LIBRARY")
    target_compile_definitions(launcher PRIVATE ZAPAROO_MISTER)
    get_filename_component(_qt_prefix "${Qt6_DIR}/../../.." ABSOLUTE)
    file(GLOB _qml_plugin_configs
        "${_qt_prefix}/lib/cmake/Qt6Qml/QmlPlugins/Qt6*Config.cmake"
    )
    foreach(_config IN LISTS _qml_plugin_configs)
        include("${_config}" OPTIONAL)
    endforeach()
    include("${_qt_prefix}/lib/cmake/Qt6Gui/Qt6QLinuxFbIntegrationPluginConfig.cmake" OPTIONAL)
    # Also load the QtQuick.Controls chain — their _init object files are not
    # propagated automatically from a cross-compiled static Qt toolchain.
    foreach(_qml_plugin IN ITEMS
            qtquickcontrols2plugin
            qtquickcontrols2basicstyleplugin
            qtquickcontrols2implplugin
            qtquicktemplates2plugin
            quickwindow)
        include("${_qt_prefix}/lib/cmake/Qt6Qml/QmlPlugins/Qt6${_qml_plugin}Config.cmake" OPTIONAL)
    endforeach()
endif()

target_link_libraries(
    launcher
    PRIVATE
        Zaparoo::CompileOptions
        zaparoo_core
        zaparoo_coreplugin
        zaparoo_ui_appplugin
        Qt6::Quick
        Qt6::QuickControls2
)

# qt_import_qml_plugins must be called AFTER target_link_libraries so that
# qmlimportscanner can traverse the full dependency graph and find all
# import statements in the linked QML modules.
qt_import_qml_plugins(launcher)

# For static builds: link the linuxfb platform plugin and the QtQuick.Controls
# chain. The _init object files contain Q_IMPORT_PLUGIN which registers each
# plugin as a static factory; they are not pulled in transitively from a
# cross-compiled static Qt toolchain that lacks qmlimportscanner.
if(_qt6_core_type STREQUAL "STATIC_LIBRARY")
    if(TARGET Qt6::QLinuxFbIntegrationPlugin)
        target_link_libraries(launcher PRIVATE
            Qt6::QLinuxFbIntegrationPlugin
            Qt6::QLinuxFbIntegrationPlugin_init
        )
    endif()
    foreach(_qml_plugin IN ITEMS
            qtquickcontrols2plugin
            qtquickcontrols2basicstyleplugin
            qtquickcontrols2implplugin
            qtquicktemplates2plugin
            quickwindow)
        if(TARGET Qt6::${_qml_plugin})
            target_link_libraries(launcher PRIVATE
                Qt6::${_qml_plugin}
                Qt6::${_qml_plugin}_init
            )
        endif()
    endforeach()
endif()

set_target_properties(
    launcher PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
)

install(TARGETS launcher RUNTIME DESTINATION bin)
