#!/bin/bash
# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
# SPDX-FileCopyrightText: 2026 Callan Barrett
#
# Builds the ARM32 binary and deploys it to a MiSTer FPGA over SSH/SCP.
# Reads MISTER_IP from a .env file in the project root.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="${PROJECT_ROOT}/.env"
REMOTE_PATH="/media/fat/zaparoo/launcher"
BINARY="${PROJECT_ROOT}/output/launcher"

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

echo "=== Building ARM32 binary ==="
"${SCRIPT_DIR}/build-arm32.sh"

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
    nohup /media/fat/MiSTer_Zaparoo >/dev/null 2>&1 &
"
