# Zaparoo Launcher
# Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
#
# Sync cxx-qt-generated QML module directories (qmldir + plugin.qmltypes)
# from cargo's OUT_DIR into the central CMAKE_BINARY_DIR/qml tree, so Qt
# tooling (qmllint in particular) can resolve types declared by Rust-side
# QML plugins. cxx-qt writes these files under
# <cargo_out>/qt-build-utils/qml_modules/<Module/Path>/ but qmllint only
# searches the Qt qml output root; copying makes them siblings of the
# C++-generated App/Theme/Ui modules.
#
# cxx-qt 0.8 emits qmllint-clean qmltypes natively for singletons, plain
# `int`, and real C++ prototypes — the 0.7-era patches for those have been
# removed. The remaining patch injects `isFinal: true` on properties of
# QML_SINGLETON Components, suppressing qmllint's "Member can be shadowed"
# false positive (singletons can't be subclassed). Methods get no patch:
# the qmltypes schema has no isFinal slot for Method.
#
# Run via:
#   cmake -DCARGO_DIR=... -DDEST_QML_DIR=... -P SyncCxxqtQmlModules.cmake

cmake_minimum_required(VERSION 3.22)

if(NOT DEFINED CARGO_DIR)
    message(FATAL_ERROR "SyncCxxqtQmlModules: CARGO_DIR is required")
endif()
if(NOT DEFINED DEST_QML_DIR)
    message(FATAL_ERROR "SyncCxxqtQmlModules: DEST_QML_DIR is required")
endif()

file(GLOB_RECURSE _all_qmldirs "${CARGO_DIR}/*qmldir")

set(_qmldirs "")
foreach(_candidate IN LISTS _all_qmldirs)
    if(_candidate MATCHES "/qt-build-utils/qml_modules/.+/qmldir$")
        list(APPEND _qmldirs "${_candidate}")
    endif()
endforeach()

foreach(_qmldir IN LISTS _qmldirs)
    string(REGEX REPLACE
        ".*/qt-build-utils/qml_modules/(.+)/qmldir$"
        "\\1"
        _module_path
        "${_qmldir}"
    )
    get_filename_component(_src_dir "${_qmldir}" DIRECTORY)
    set(_dst_dir "${DEST_QML_DIR}/${_module_path}")
    file(MAKE_DIRECTORY "${_dst_dir}")
    file(GLOB _contents "${_src_dir}/*")
    foreach(_src_file IN LISTS _contents)
        get_filename_component(_name "${_src_file}" NAME)
        execute_process(
            COMMAND ${CMAKE_COMMAND} -E copy_if_different
                "${_src_file}" "${_dst_dir}/${_name}"
        )
    endforeach()
endforeach()

# ── Patch plugin.qmltypes: isFinal: true on singleton properties ─────────────
# Collect QML_SINGLETON element names from the cxx-qt-generated headers, then
# rewrite each synced plugin.qmltypes to mark every Property final when *all*
# Components in the file are known singletons. Only run the patch under that
# guard: non-singleton types can legitimately be subclassed and marking their
# members final would be incorrect. Methods are untouched — the qmltypes
# schema has no isFinal slot for Method.

set(_singleton_names "")
file(GLOB_RECURSE _all_cxxqt_headers "${CARGO_DIR}/*.cxxqt.h")
foreach(_hdr IN LISTS _all_cxxqt_headers)
    file(READ "${_hdr}" _hdr_content)
    if(NOT _hdr_content MATCHES "QML_SINGLETON")
        continue()
    endif()
    string(REGEX MATCHALL
        "Q_CLASSINFO\\(\"QML.Element\", \"[A-Za-z_][A-Za-z0-9_]*\"\\)[ \t\r\n]*QML_SINGLETON"
        _matches "${_hdr_content}")
    foreach(_m IN LISTS _matches)
        if(_m MATCHES "\"QML.Element\", \"([A-Za-z_][A-Za-z0-9_]*)\"")
            list(APPEND _singleton_names "${CMAKE_MATCH_1}")
        endif()
    endforeach()
endforeach()
list(REMOVE_DUPLICATES _singleton_names)

file(GLOB_RECURSE _synced_qmltypes "${DEST_QML_DIR}/*/plugin.qmltypes")
foreach(_qt_file IN LISTS _synced_qmltypes)
    file(READ "${_qt_file}" _qt_content)
    set(_original "${_qt_content}")

    string(REGEX MATCHALL
        "    Component \\{\n[ \t]+file: \"[^\"]+\"\n[ \t]+lineNumber: [0-9]+\n[ \t]+name: \"[^\"]+\""
        _component_headers "${_qt_content}")
    set(_non_singleton_components "")
    foreach(_hdr IN LISTS _component_headers)
        if(_hdr MATCHES "name: \"([^\"]+)\"")
            list(FIND _singleton_names "${CMAKE_MATCH_1}" _sidx)
            if(_sidx EQUAL -1)
                list(APPEND _non_singleton_components "${CMAKE_MATCH_1}")
            endif()
        endif()
    endforeach()
    if(NOT _non_singleton_components)
        string(REGEX REPLACE
            "(Property \\{\n)([ \t]+)(name:)"
            "\\1\\2isFinal: true\n\\2\\3"
            _qt_content "${_qt_content}")
    endif()

    if(NOT _qt_content STREQUAL _original)
        file(WRITE "${_qt_file}" "${_qt_content}")
    endif()
endforeach()
