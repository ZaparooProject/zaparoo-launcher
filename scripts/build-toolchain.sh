#!/bin/bash
# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
# SPDX-FileCopyrightText: 2026 Callan Barrett
#
# Build the Qt 6.7.2 + MiSTer ARM32 toolchain base image.
# Run this ONCE (or when Qt version needs bumping). Takes ~45 minutes.
# After this, build-arm32.sh will be fast (< 1 min).

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
IMAGE_TAG="zaparoo/qt6-arm32-mister:6.7.2"

echo "=== Building Qt 6.7.2 ARM32 toolchain image ==="
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
