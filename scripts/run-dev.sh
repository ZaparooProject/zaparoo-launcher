#!/bin/bash
# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
# SPDX-FileCopyrightText: 2026 Callan Barrett
#
# Build and run a desktop dev build (ZAPAROO_DEV=ON).
# Uses build-dev/ to avoid clobbering the regular build/.
# Reconfigures only when CMakeLists.txt changes; always rebuilds before running.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${PROJECT_ROOT}/build-dev"

cmake -S "${PROJECT_ROOT}" -B "${BUILD_DIR}" \
    -DCMAKE_BUILD_TYPE=Debug \
    -DZAPAROO_DEV=ON \
    -DZAPAROO_BUILD_TESTS=OFF

cmake --build "${BUILD_DIR}"

exec "${BUILD_DIR}/bin/launcher"
