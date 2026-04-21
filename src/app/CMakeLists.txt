# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
# SPDX-FileCopyrightText: 2026 Callan Barrett

qt_add_executable(zaparoo-launcher main.cpp)

target_compile_definitions(
    zaparoo-launcher
    PRIVATE ZAPAROO_VERSION="${CMAKE_PROJECT_VERSION}"
)

# Static QML plugin imports must be explicitly listed so the linker
# does not eliminate them as unreferenced symbols.
qt_import_qml_plugins(zaparoo-launcher)

target_link_libraries(
    zaparoo-launcher
    PRIVATE
        Zaparoo::CompileOptions
        zaparoo_core
        zaparoo_ui_appplugin
        Qt6::Quick
        Qt6::QuickControls2
)

set_target_properties(
    zaparoo-launcher PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
)

install(TARGETS zaparoo-launcher RUNTIME DESTINATION bin)
