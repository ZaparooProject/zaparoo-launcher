# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
# SPDX-FileCopyrightText: 2026 Callan Barrett

qt_add_executable(tst_zaparoo_client tst_zaparoo_client.cpp)

target_link_libraries(
    tst_zaparoo_client
    PRIVATE
        Zaparoo::CompileOptions
        zaparoo_core
        Qt6::Test
)

add_test(NAME zaparoo_client COMMAND tst_zaparoo_client)
set_tests_properties(zaparoo_client PROPERTIES TIMEOUT 30)

qt_add_executable(tst_browse_model tst_browse_model.cpp)

target_link_libraries(
    tst_browse_model
    PRIVATE
        Zaparoo::CompileOptions
        zaparoo_core
        Qt6::Test
)

add_test(NAME browse_model COMMAND tst_browse_model)
set_tests_properties(browse_model PROPERTIES TIMEOUT 30)

qt_add_executable(tst_config tst_config.cpp)

target_link_libraries(
    tst_config
    PRIVATE
        Zaparoo::CompileOptions
        zaparoo_core
        Qt6::Test
)

add_test(NAME config COMMAND tst_config)
set_tests_properties(config PROPERTIES TIMEOUT 10)
