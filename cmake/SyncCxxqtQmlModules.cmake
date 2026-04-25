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
# Also patches plugin.qmltypes to work around three cxx-qt 0.7 gaps that
# make qmllint noisy against Rust-backed singletons. Remove the patch
# block when we upgrade to cxx-qt 0.8, which adds first-class
# qmllint/qmlls support:
#
#   1. `isSingleton: true` / `isCreatable: false` for types declared
#      `QML_SINGLETON`. The macro lands in the C++ header but
#      qmltyperegistrar does not forward it to .qmltypes, so without the
#      patch qmllint treats every `Browse.QAppState.property` access as
#      a static meta-object lookup and reports [missing-property].
#
#   2. `::std::int32_t` → `int`. cxx-qt-gen emits the C++ typedef
#      verbatim (upstream issue cxx-qt#60). Qt's qmllint has no mapping
#      from `::std::int32_t` to its built-in `int` type, so every
#      int-valued property or method return trips [unresolved-type].
#
#   3. `prototype: "::rust::cxxqt1::CxxQtType<T>"` /
#      `"::rust::cxxqt1::CxxQtThreading<T>"` → `"QObject"`. The cxx-qt
#      bridge templates inherit from QObject at the C++ level, but
#      qmllint sees them as unresolved types and therefore refuses to
#      use a singleton as a `Connections.target:` (expects QObject).
#
#   4. `isFinal: true` on every Property of a singleton Component. QML
#      singletons can't be subclassed, so the QQmlCompiler "Member X
#      can be shadowed" warning is a false positive — qmllint only
#      suppresses it when the member is marked final. Methods are left
#      untouched: the qmltypes schema has no isFinal slot for Method
#      (qmllint itself rejects it with "Expected only name, lineNumber,
#      ..."), so method-shadowing warnings linger until we upgrade to
#      cxx-qt 0.8.
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

# ── Patch plugin.qmltypes for cxx-qt singletons ──────────────────────────────
# Collect the set of QML element names declared as singletons by scanning
# every cxx-qt-generated header for a QML_SINGLETON macro paired with a
# Q_CLASSINFO("QML.Element", "<Name>") line. Then rewrite each synced
# plugin.qmltypes so qmllint sees those Components as singletons.

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

    # (1) Inject isSingleton / isCreatable for each QML_SINGLETON class.
    # Idempotent — rerunning the sync target leaves the file unchanged
    # once all three patches have already been applied.
    foreach(_name IN LISTS _singleton_names)
        string(REGEX MATCH
            "name: \"${_name}\"\n[ \t]+accessSemantics: \"reference\"\n[ \t]+isSingleton: true"
            _already "${_qt_content}")
        if(_already)
            continue()
        endif()
        string(REGEX REPLACE
            "(name: \"${_name}\"\n)([ \t]+)(accessSemantics: \"reference\")"
            "\\1\\2\\3\n\\2isSingleton: true\n\\2isCreatable: false"
            _qt_content "${_qt_content}")
    endforeach()

    # (2) ::std::int32_t → int. qmltyperegistrar emits the C++ typedef
    # spelled exactly like this; Qt's qmllint only knows the short form.
    string(REPLACE "::std::int32_t" "int" _qt_content "${_qt_content}")

    # (3) cxx-qt bridge template → QObject. The templated C++ ancestor
    # is a QObject mixin, but qmllint can't see through unresolved
    # template instantiations; collapsing to the concrete base unlocks
    # Connections.target:, signal bindings, etc.
    string(REGEX REPLACE
        "prototype: \"::rust::cxxqt1::CxxQt(Type|Threading)<[^\"]+>\""
        "prototype: \"QObject\""
        _qt_content "${_qt_content}")

    # (4) isFinal: true on every Property / multi-line Method.
    # Only run when *every* Component in the file is a known singleton —
    # non-singleton types can legitimately be subclassed, and marking
    # their members final would be incorrect. Today all cxx-qt-backed
    # types we register are singletons; the guard keeps this honest if
    # that ever changes.
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
