#!/bin/bash
# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
# SPDX-FileCopyrightText: 2026 Callan Barrett
#
# Cross-compiles the launcher for ARM32 / MiSTer FPGA using Docker.
# Uses the prebuilt toolchain image; builds the application layer only (~1 min).
#
# If the toolchain image is not present locally it is built automatically
# (~45 min one-time). Subsequent runs are fast.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="${PROJECT_ROOT}/output"
TOOLCHAIN_IMAGE="zaparoo/qt6-arm32-mister:6.7.2"

# Build toolchain image if it doesn't exist locally.
if ! docker image inspect "${TOOLCHAIN_IMAGE}" > /dev/null 2>&1; then
    echo "Toolchain image '${TOOLCHAIN_IMAGE}' not found locally."
    echo "Building it now (~45 minutes)..."
    "${SCRIPT_DIR}/build-toolchain.sh"
fi

echo "=== Cross-compiling launcher for ARM32 ==="
mkdir -p "${OUTPUT_DIR}"

docker build \
    -f "${PROJECT_ROOT}/Dockerfile.arm32" \
    --output "type=local,dest=${OUTPUT_DIR}" \
    --target export \
    "${PROJECT_ROOT}"

if [ -f "${OUTPUT_DIR}/launcher" ]; then
    echo ""
    echo "=== Build successful! ==="
    echo "Binary: ${OUTPUT_DIR}/launcher"
    file "${OUTPUT_DIR}/launcher"
else
    echo "Build failed — binary not found in ${OUTPUT_DIR}"
    exit 1
fi
