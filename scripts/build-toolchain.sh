#!/bin/bash
# Zaparoo Launcher
# Copyright (c) 2026 The Zaparoo Project Contributors.
# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
#
# Build the Qt + MiSTer ARM32 toolchain base image. Qt upstream version is
# pinned in Dockerfile.toolchain (QT_VERSION arg); the image tag is read from
# toolchain/VERSION so CI and local dev share the same source of truth.
# Run this ONCE (or when the toolchain version needs bumping). Takes ~45
# minutes. After this, build-arm32.sh will be fast (< 1 min).

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
VERSION_FILE="${PROJECT_ROOT}/toolchain/VERSION"
if [ ! -f "${VERSION_FILE}" ]; then
    echo "Error: toolchain version file not found at ${VERSION_FILE}" >&2
    echo "       (PROJECT_ROOT=${PROJECT_ROOT})" >&2
    exit 1
fi
TOOLCHAIN_VERSION="$(tr -d '[:space:]' < "${VERSION_FILE}")"
if ! printf '%s' "${TOOLCHAIN_VERSION}" | grep -Eq '^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$'; then
    echo "Error: invalid toolchain version in ${VERSION_FILE}" >&2
    echo "       raw value: '${TOOLCHAIN_VERSION}'" >&2
    echo "       expected:  Docker tag [A-Za-z0-9_][A-Za-z0-9_.-]{0,127}" >&2
    exit 1
fi
IMAGE_TAG="zaparoo/qt6-arm32-mister:${TOOLCHAIN_VERSION}"

echo "=== Building Qt 6.7.2 ARM32 toolchain image (${TOOLCHAIN_VERSION}) ==="
echo "Tag: ${IMAGE_TAG}"
echo "This will take ~45 minutes on first run."
echo ""

docker build \
    -f "${PROJECT_ROOT}/Dockerfile.toolchain" \
    -t "${IMAGE_TAG}" \
    "${PROJECT_ROOT}"

echo ""
echo "=== Toolchain image built successfully ==="
echo "Tag: ${IMAGE_TAG}"
echo ""
echo "You can now run ./scripts/build-arm32.sh to build the application."
