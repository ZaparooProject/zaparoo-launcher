// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
// SPDX-FileCopyrightText: 2026 Callan Barrett
#pragma once

#include "MediaTypes.h"

#include <QAbstractSocket>
#include <QHash>
#include <QJsonValue>
#include <QObject>
#include <QString>
#include <QTimer>
#include <QUrl>
#include <QWebSocket>
#include <functional>

namespace zaparoo
{

struct JsonRpcError
{
    bool isError{false};
    int code{0};
    QString message;
};

using MediaSearchCallback = std::function<void(const MediaSearchResult&, const JsonRpcError&)>;
using MediaBrowseCallback = std::function<void(const MediaBrowseResult&, const JsonRpcError&)>;
using RunCallback = std::function<void(const RunResult&, const JsonRpcError&)>;
using SystemsCallback = std::function<void(const SystemsResult&, const JsonRpcError&)>;

// Asynchronous client for the Zaparoo Core JSON-RPC 2.0 WebSocket API.
// Call connectToCore() to open the connection; use mediaSearch()/mediaBrowse()
// to issue requests. Results arrive via callbacks on the Qt event loop thread.
// The scanReceived() signal fires for every tokens.added notification pushed
// by the server (NFC/barcode scans).
class ZaparooClient : public QObject
{
    Q_OBJECT

  public:
    explicit ZaparooClient(QObject* parent = nullptr);
    ~ZaparooClient() override;

    void connectToCore(const QUrl& endpoint);
    void disconnectFromCore();

    [[nodiscard]] bool isConnected() const;

    QString mediaSearch(const MediaSearchParams& params, MediaSearchCallback callback);
    QString mediaBrowse(const MediaBrowseParams& params, MediaBrowseCallback callback);
    QString run(const RunParams& params, RunCallback callback);
    QString systems(const SystemsParams& params, SystemsCallback callback);

  signals:
    void connected();
    void disconnected();
    void errorOccurred(const QString& message);
    void scanReceived(const QString& uid, const QString& text);

  private:
    struct PendingRequest
    {
        std::function<void(const QJsonValue&, const JsonRpcError&)> callback;
    };

    void onConnected();
    void onDisconnected();
    void onError(QAbstractSocket::SocketError error);
    void onTextMessageReceived(const QString& message);

    QString sendRequest(const QString& method, const QJsonObject& params,
                        std::function<void(const QJsonValue&, const JsonRpcError&)> callback);

    void dispatchNotification(const QString& method, const QJsonObject& params);

    QWebSocket m_socket;
    QHash<QString, PendingRequest> m_pending;
    QUrl m_endpoint;
    QTimer m_reconnectTimer;
};

} // namespace zaparoo
