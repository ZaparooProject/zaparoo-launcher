# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
# SPDX-FileCopyrightText: 2026 Callan Barrett

qt_add_executable(tst_zaparoo_client tst_zaparoo_client.cpp MockServer.cpp)

target_link_libraries(
    tst_zaparoo_client
    PRIVATE
        Zaparoo::CompileOptions
        zaparoo_core
        Qt6::Test
)

add_test(NAME zaparoo_client COMMAND tst_zaparoo_client)
set_tests_properties(zaparoo_client PROPERTIES TIMEOUT 30)

qt_add_executable(tst_browse_model tst_browse_model.cpp MockServer.cpp)

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

qt_add_executable(tst_logger tst_logger.cpp)

target_link_libraries(
    tst_logger
    PRIVATE
        Zaparoo::CompileOptions
        zaparoo_core
        Qt6::Test
)

add_test(NAME logger COMMAND tst_logger)
set_tests_properties(logger PROPERTIES TIMEOUT 15)

qt_add_executable(tst_systems_catalog tst_systems_catalog.cpp MockServer.cpp)

target_link_libraries(
    tst_systems_catalog
    PRIVATE
        Zaparoo::CompileOptions
        zaparoo_core
        Qt6::Test
)

add_test(NAME systems_catalog COMMAND tst_systems_catalog)
set_tests_properties(systems_catalog PROPERTIES TIMEOUT 30)

qt_add_executable(tst_systems_model tst_systems_model.cpp MockServer.cpp)

target_link_libraries(
    tst_systems_model
    PRIVATE
        Zaparoo::CompileOptions
        zaparoo_core
        Qt6::Test
)

add_test(NAME systems_model COMMAND tst_systems_model)
set_tests_properties(systems_model PROPERTIES TIMEOUT 30)

qt_add_executable(tst_games_model tst_games_model.cpp MockServer.cpp)

target_link_libraries(
    tst_games_model
    PRIVATE
        Zaparoo::CompileOptions
        zaparoo_core
        Qt6::Test
)

add_test(NAME games_model COMMAND tst_games_model)
set_tests_properties(games_model PROPERTIES TIMEOUT 30)
