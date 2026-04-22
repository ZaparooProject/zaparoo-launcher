# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
# SPDX-FileCopyrightText: 2026 Callan Barrett

qt_add_library(zaparoo_core STATIC)

target_sources(
    zaparoo_core
    PRIVATE
        BrowseModel.cpp
        BrowseModel.h
        CategoriesModel.cpp
        CategoriesModel.h
        Config.cpp
        Config.h
        GamesModel.cpp
        GamesModel.h
        Logger.cpp
        Logger.h
        MediaTypes.h
        PlatformPaths.cpp
        PlatformPaths.h
        SystemsCatalog.cpp
        SystemsCatalog.h
        SystemsModel.cpp
        SystemsModel.h
        ZaparooClient.cpp
        ZaparooClient.h
)

qt_add_qml_module(
    zaparoo_core
    URI Zaparoo.Browse
    VERSION 1.0
)

target_include_directories(
    zaparoo_core
    PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}"
    SYSTEM PRIVATE "${CMAKE_SOURCE_DIR}/third_party" # tomlplusplus v3.4.0
)

target_link_libraries(
    zaparoo_core
    PUBLIC
        Qt6::Core
        Qt6::Qml
        Qt6::WebSockets
    PRIVATE
        Zaparoo::CompileOptions
)
