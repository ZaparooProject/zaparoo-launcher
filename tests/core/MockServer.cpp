// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
// SPDX-FileCopyrightText: 2026 Callan Barrett

#include "MockServer.h"

MockServer::MockServer(QObject* parent)
    : QObject(parent), m_server("mock", QWebSocketServer::NonSecureMode, this)
{
    if (!m_server.listen(QHostAddress::LocalHost, 0))
    {
        qFatal("MockServer: listen failed");
    }
    connect(&m_server, &QWebSocketServer::newConnection, this, &MockServer::onNewConnection);
}

quint16 MockServer::port() const
{
    return m_server.serverPort();
}

bool MockServer::hasClient() const
{
    return m_peer != nullptr;
}

QJsonObject MockServer::lastFrame() const
{
    return m_lastFrame;
}

void MockServer::setReply(const QJsonObject& reply)
{
    m_reply = reply;
}

void MockServer::sendToClient(const QJsonObject& frame)
{
    if (m_peer != nullptr)
    {
        m_peer->sendTextMessage(
            QString::fromUtf8(QJsonDocument(frame).toJson(QJsonDocument::Compact)));
    }
}

void MockServer::sendRawToClient(const QString& text)
{
    if (m_peer != nullptr)
    {
        m_peer->sendTextMessage(text);
    }
}

void MockServer::onNewConnection()
{
    m_peer = m_server.nextPendingConnection();
    connect(m_peer, &QWebSocket::textMessageReceived, this, &MockServer::onMessage);
    emit clientConnected();
}

void MockServer::onMessage(const QString& msg)
{
    m_lastFrame = QJsonDocument::fromJson(msg.toUtf8()).object();
    if (!m_reply.isEmpty())
    {
        QJsonObject reply = m_reply;
        reply["id"] = m_lastFrame["id"];
        m_reply = {};
        sendToClient(reply);
    }
    emit frameReceived(m_lastFrame);
}
