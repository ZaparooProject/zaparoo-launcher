// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
// SPDX-FileCopyrightText: 2026 Callan Barrett
#pragma once

#include <QJsonDocument>
#include <QJsonObject>
#include <QObject>
#include <QWebSocket>
#include <QWebSocketServer>

// Shared in-process WebSocket server for unit tests.
// Records the last received frame; can reply to incoming requests on demand.
class MockServer : public QObject
{
    Q_OBJECT

  public:
    explicit MockServer(QObject* parent = nullptr);

    [[nodiscard]] quint16 port() const;
    [[nodiscard]] bool hasClient() const;
    [[nodiscard]] QJsonObject lastFrame() const;

    void setReply(const QJsonObject& reply);
    void sendToClient(const QJsonObject& frame);
    void sendRawToClient(const QString& text);

  signals:
    void frameReceived(QJsonObject);
    void clientConnected();

  private slots:
    void onNewConnection();
    void onMessage(const QString& msg);

  private: // NOLINT(readability-redundant-access-specifiers)
    QWebSocketServer m_server;
    QJsonObject m_reply;
    QJsonObject m_lastFrame;
    QWebSocket* m_peer{nullptr};
};
