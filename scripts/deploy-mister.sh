#!/bin/bash
# Zaparoo Launcher
# Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
#
# Builds the ARM32 binary and deploys it to a MiSTer FPGA over SSH/SCP.
# Pass --skip-build to deploy an existing output/launcher without rebuilding.
# Reads MISTER_IP from a .env file in the project root.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="${PROJECT_ROOT}/.env"
REMOTE_PATH="/media/fat/zaparoo/launcher"
BINARY="${PROJECT_ROOT}/output/launcher"
SKIP_BUILD=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --skip-build)
            SKIP_BUILD=1
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--skip-build]"
            echo ""
            echo "Builds output/launcher and deploys it to MiSTer."
            echo "  --skip-build  Deploy existing output/launcher without rebuilding"
            exit 0
            ;;
        *)
            echo "Error: unknown argument: $1" >&2
            echo "Usage: $0 [--skip-build]" >&2
            exit 1
            ;;
    esac
done

if [ ! -f "${ENV_FILE}" ]; then
    echo "Error: .env file not found at ${ENV_FILE}"
    echo "Create it with: echo 'MISTER_IP=<your-mister-ip>' > .env"
    exit 1
fi

set -a
# shellcheck source=/dev/null
source "${ENV_FILE}"
set +a

if [ -z "${MISTER_IP}" ]; then
    echo "Error: MISTER_IP is not set in ${ENV_FILE}"
    exit 1
fi

if [ "${SKIP_BUILD}" -eq 1 ]; then
    echo "=== Skipping ARM32 build ==="
    if [ ! -f "${BINARY}" ]; then
        echo "Error: ${BINARY} does not exist; run ${SCRIPT_DIR}/build-arm32.sh first" >&2
        exit 1
    fi
else
    echo "=== Building ARM32 binary ==="
    "${SCRIPT_DIR}/build-arm32.sh"
fi

echo ""
echo "=== Deploying to MiSTer at ${MISTER_IP} ==="

ssh "root@${MISTER_IP}" "
    if [ -f '${REMOTE_PATH}' ]; then
        mv '${REMOTE_PATH}' '${REMOTE_PATH}.bak'
        echo 'Moved existing binary to ${REMOTE_PATH}.bak'
    fi
"

scp "${BINARY}" "root@${MISTER_IP}:${REMOTE_PATH}"
echo "Deployed ${BINARY} → root@${MISTER_IP}:${REMOTE_PATH}"

ssh "root@${MISTER_IP}" "
    killall launcher 2>/dev/null && echo 'Killed running launcher' || true
    killall MiSTer_Zaparoo 2>/dev/null && echo 'Killed running MiSTer_Zaparoo' || true
    rm -f /tmp/zaparoo/launcher.log
    nohup /media/fat/MiSTer_Zaparoo >/dev/null 2>&1 &
"
