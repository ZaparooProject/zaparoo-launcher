#!/bin/bash
# Zaparoo Launcher
# Copyright (c) 2026 The Zaparoo Project Contributors.
# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
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
VERSION_FILE="${PROJECT_ROOT}/toolchain/VERSION"
if [ ! -f "${VERSION_FILE}" ]; then
    echo "Error: toolchain version file not found at ${VERSION_FILE}" >&2
    echo "       (PROJECT_ROOT=${PROJECT_ROOT})" >&2
    exit 1
fi
# tr -d strips the trailing newline and guards against stray whitespace
# that would silently corrupt the Docker tag.
TOOLCHAIN_VERSION="$(tr -d '[:space:]' < "${VERSION_FILE}")"
if ! printf '%s' "${TOOLCHAIN_VERSION}" | grep -Eq '^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$'; then
    echo "Error: invalid toolchain version in ${VERSION_FILE}" >&2
    echo "       raw value: '${TOOLCHAIN_VERSION}'" >&2
    echo "       expected:  Docker tag [A-Za-z0-9_][A-Za-z0-9_.-]{0,127}" >&2
    exit 1
fi
# CI sets TOOLCHAIN_IMAGE to a GHCR tag; local dev defaults to the image
# produced by build-toolchain.sh, whose tag derives from toolchain/VERSION.
TOOLCHAIN_IMAGE="${TOOLCHAIN_IMAGE:-zaparoo/qt6-arm32-mister:${TOOLCHAIN_VERSION}}"

# Build toolchain image locally if it's missing and we're using the local tag.
# When TOOLCHAIN_IMAGE points at a registry, docker build will pull it.
if [[ "${TOOLCHAIN_IMAGE}" == zaparoo/qt6-arm32-mister:* ]] \
    && ! docker image inspect "${TOOLCHAIN_IMAGE}" > /dev/null 2>&1; then
    echo "Toolchain image '${TOOLCHAIN_IMAGE}' not found locally."
    echo "Building it now (~45 minutes)..."
    "${SCRIPT_DIR}/build-toolchain.sh"
fi

echo "=== Cross-compiling launcher for ARM32 ==="
echo "Using toolchain image: ${TOOLCHAIN_IMAGE}"
mkdir -p "${OUTPUT_DIR}"

docker build \
    -f "${PROJECT_ROOT}/Dockerfile.arm32" \
    --build-arg "TOOLCHAIN_IMAGE=${TOOLCHAIN_IMAGE}" \
    --output "type=local,dest=${OUTPUT_DIR}" \
    --target export \
    "${PROJECT_ROOT}"

if [ -f "${OUTPUT_DIR}/launcher" ]; then
    echo ""
    echo "=== Build successful! ==="
    file "${OUTPUT_DIR}/launcher"
else
    echo "Build failed — binary not found in ${OUTPUT_DIR}"
    exit 1
fi
