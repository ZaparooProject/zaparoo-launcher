# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
# SPDX-FileCopyrightText: 2026 Callan Barrett

qt_add_executable(tst_ui_smoke tst_main.cpp)

qt_add_qml_module(
    tst_ui_smoke
    URI ZaparooTest.UiSmoke
    VERSION 1.0
    QML_FILES tst_smoke.qml
    IMPORTS
        Zaparoo.App
        Zaparoo.Ui
        Zaparoo.Theme
)

qt_import_qml_plugins(tst_ui_smoke)

target_compile_definitions(
    tst_ui_smoke
    PRIVATE QUICK_TEST_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}"
)

target_link_libraries(
    tst_ui_smoke
    PRIVATE
        Zaparoo::CompileOptions
        zaparoo_ui_appplugin
        zaparoo_ui_componentsplugin
        zaparoo_ui_themeplugin
        Qt6::QuickTest
        Qt6::Quick
)

add_test(NAME ui_smoke COMMAND tst_ui_smoke -input "${CMAKE_CURRENT_SOURCE_DIR}")
set_tests_properties(ui_smoke PROPERTIES TIMEOUT 30)
