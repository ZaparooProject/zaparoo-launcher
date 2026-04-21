// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
// SPDX-FileCopyrightText: 2026 Callan Barrett

#include "ZaparooClient.h"

#include "Logger.h"

namespace zaparoo
{

ZaparooClient::ZaparooClient(QObject* parent) : QObject(parent) {}

ZaparooClient::~ZaparooClient() = default;

void ZaparooClient::connectToCore(const QUrl& endpoint)
{
    // TODO: establish WebSocket connection to endpoint.
    qCDebug(zapNet) << "connectToCore: not yet implemented, endpoint:" << endpoint;
}

void ZaparooClient::disconnectFromCore()
{
    // TODO: close WebSocket connection.
    qCDebug(zapNet) << "disconnectFromCore: not yet implemented";
    m_connected = false;
}

bool ZaparooClient::isConnected() const
{
    return m_connected;
}

} // namespace zaparoo
