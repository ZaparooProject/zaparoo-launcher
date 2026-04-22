// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
// SPDX-FileCopyrightText: 2026 Callan Barrett

#include "ZaparooClient.h"

#include "Logger.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QUuid>

namespace zaparoo
{

namespace
{

MediaTag parseMediaTag(const QJsonObject& obj)
{
    MediaTag tag;
    tag.tag = obj["tag"].toString();
    tag.type = obj["type"].toString();
    return tag;
}

SystemInfo parseSystemInfo(const QJsonObject& obj)
{
    SystemInfo info;
    info.id = obj["id"].toString();
    info.name = obj["name"].toString();
    info.category = obj["category"].toString();
    return info;
}

MediaItem parseMediaItem(const QJsonObject& obj)
{
    MediaItem item;
    item.system = parseSystemInfo(obj["system"].toObject());
    item.name = obj["name"].toString();
    item.path = obj["path"].toString();
    item.zapScript = obj["zapScript"].toString();
    for (const auto& val : obj["tags"].toArray())
    {
        item.tags.append(parseMediaTag(val.toObject()));
    }
    return item;
}

MediaSearchResult parseSearchResult(const QJsonObject& result)
{
    MediaSearchResult out;
    for (const auto& val : result["results"].toArray())
    {
        out.results.append(parseMediaItem(val.toObject()));
    }
    const QJsonObject pagination = result["pagination"].toObject();
    out.nextCursor = pagination["nextCursor"].toString();
    out.hasNextPage = pagination["hasNextPage"].toBool();
    out.pageSize = pagination["pageSize"].toInt();
    return out;
}

SystemsResult parseSystemsResult(const QJsonObject& result)
{
    SystemsResult out;
    for (const auto& val : result["systems"].toArray())
    {
        out.systems.append(parseSystemInfo(val.toObject()));
    }
    return out;
}

BrowseEntry parseBrowseEntry(const QJsonObject& obj)
{
    BrowseEntry entry;
    entry.name = obj["name"].toString();
    entry.path = obj["path"].toString();
    entry.type = obj["type"].toString();
    entry.systemId = obj["systemId"].toString();
    entry.zapScript = obj["zapScript"].toString();
    entry.fileCount = obj["fileCount"].toInt();
    for (const auto& val : obj["tags"].toArray())
    {
        entry.tags.append(parseMediaTag(val.toObject()));
    }
    return entry;
}

MediaBrowseResult parseBrowseResult(const QJsonObject& result)
{
    MediaBrowseResult out;
    out.path = result["path"].toString();
    out.totalFiles = result["totalFiles"].toInt();
    for (const auto& val : result["entries"].toArray())
    {
        out.entries.append(parseBrowseEntry(val.toObject()));
    }
    const QJsonObject pagination = result["pagination"].toObject();
    out.nextCursor = pagination["nextCursor"].toString();
    out.hasNextPage = pagination["hasNextPage"].toBool();
    return out;
}

} // namespace

ZaparooClient::ZaparooClient(QObject* parent) : QObject(parent)
{
    connect(&m_socket, &QWebSocket::connected, this, &ZaparooClient::onConnected);
    connect(&m_socket, &QWebSocket::disconnected, this, &ZaparooClient::onDisconnected);
    connect(&m_socket, &QWebSocket::textMessageReceived, this,
            &ZaparooClient::onTextMessageReceived);
    connect(&m_socket, &QWebSocket::errorOccurred, this, &ZaparooClient::onError);

    m_reconnectTimer.setSingleShot(true);
    connect(&m_reconnectTimer, &QTimer::timeout, this,
            [this]()
            {
                if (!m_endpoint.isEmpty())
                {
                    qCDebug(zapNet) << "reconnecting to Core...";
                    m_socket.open(m_endpoint);
                }
            });
}

ZaparooClient::~ZaparooClient() = default;

void ZaparooClient::connectToCore(const QUrl& endpoint)
{
    qCDebug(zapNet) << "connectToCore:" << endpoint;
    m_endpoint = endpoint;
    m_reconnectTimer.stop();
    m_socket.open(endpoint);
}

void ZaparooClient::disconnectFromCore()
{
    qCDebug(zapNet) << "disconnectFromCore";
    m_endpoint.clear();
    m_reconnectTimer.stop();
    m_socket.close();
}

bool ZaparooClient::isConnected() const
{
    return m_socket.state() == QAbstractSocket::ConnectedState;
}

void ZaparooClient::onConnected()
{
    qCDebug(zapNet) << "connected to Core";
    m_reconnectTimer.stop();
    emit connected();
}

void ZaparooClient::onDisconnected()
{
    qCDebug(zapNet) << "disconnected from Core";
    QHash<QString, PendingRequest> pending;
    pending.swap(m_pending);
    JsonRpcError err;
    err.isError = true;
    err.code = -1;
    err.message = QStringLiteral("disconnected");
    for (auto& req : pending)
    {
        req.callback(QJsonValue{}, err);
    }
    emit disconnected();
    if (!m_endpoint.isEmpty())
    {
        qCDebug(zapNet) << "scheduling reconnect in 1s";
        m_reconnectTimer.start(1000);
    }
}

void ZaparooClient::onError(QAbstractSocket::SocketError error)
{
    const QString msg = m_socket.errorString();
    qCWarning(zapNet) << "socket error" << error << msg;
    emit errorOccurred(msg);
}

void ZaparooClient::onTextMessageReceived(const QString& message)
{
    QJsonParseError parseError;
    const QJsonDocument doc = QJsonDocument::fromJson(message.toUtf8(), &parseError);
    if (parseError.error != QJsonParseError::NoError)
    {
        qCWarning(zapNet) << "JSON parse error:" << parseError.errorString();
        return;
    }
    if (!doc.isObject())
    {
        qCWarning(zapNet) << "expected JSON object, got non-object frame";
        return;
    }
    const QJsonObject frame = doc.object();

    if (frame.contains("id"))
    {
        const QJsonValue idVal = frame["id"];
        if (!idVal.isString())
        {
            qCWarning(zapNet) << "response has non-string id, ignoring:" << idVal;
            return;
        }
        const QString id = idVal.toString();
        auto it = m_pending.find(id);
        if (it == m_pending.end())
        {
            qCDebug(zapNet) << "no pending request for id:" << id;
            return;
        }
        PendingRequest req = std::move(it.value());
        m_pending.erase(it);

        if (frame.contains("error"))
        {
            const QJsonObject errObj = frame["error"].toObject();
            JsonRpcError err;
            err.isError = true;
            err.code = errObj["code"].toInt();
            err.message = errObj["message"].toString();
            req.callback(QJsonValue{}, err);
        }
        else
        {
            req.callback(frame["result"], JsonRpcError{});
        }
    }
    else
    {
        dispatchNotification(frame["method"].toString(), frame["params"].toObject());
    }
}

void ZaparooClient::dispatchNotification(const QString& method, const QJsonObject& params)
{
    if (method == QLatin1String("tokens.added"))
    {
        const QString uid = params["uid"].toString();
        const QString text = params["text"].toString();
        qCDebug(zapNet) << "scan received uid:" << uid << "text:" << text;
        emit scanReceived(uid, text);
    }
    else
    {
        qCDebug(zapNet) << "unhandled notification:" << method;
    }
}

QString
ZaparooClient::sendRequest(const QString& method, const QJsonObject& params,
                           std::function<void(const QJsonValue&, const JsonRpcError&)> callback)
{
    if (!isConnected())
    {
        qCWarning(zapNet) << "sendRequest called while not connected, method:" << method;
        JsonRpcError err;
        err.isError = true;
        err.code = -1;
        err.message = QStringLiteral("not connected");
        callback(QJsonValue{}, err);
        return {};
    }
    const QString id = QUuid::createUuid().toString(QUuid::WithoutBraces);
    const QJsonObject frame{
        {"jsonrpc", "2.0"},
        {"id", id},
        {"method", method},
        {"params", params},
    };
    qCDebug(zapNet) << "sending request" << method << "id:" << id;
    m_pending.insert(id, PendingRequest{std::move(callback)});
    m_socket.sendTextMessage(
        QString::fromUtf8(QJsonDocument(frame).toJson(QJsonDocument::Compact)));
    return id;
}

QString ZaparooClient::mediaSearch(const MediaSearchParams& params, MediaSearchCallback callback)
{
    QJsonObject jsonParams;
    if (!params.query.isEmpty())
    {
        jsonParams["query"] = params.query;
    }
    if (!params.systems.isEmpty())
    {
        QJsonArray systems;
        for (const auto& s : params.systems)
        {
            systems.append(s);
        }
        jsonParams["systems"] = systems;
    }
    jsonParams["maxResults"] = params.maxResults;
    if (!params.cursor.isEmpty())
    {
        jsonParams["cursor"] = params.cursor;
    }

    return sendRequest(
        "media.search", jsonParams,
        [cb = std::move(callback)](const QJsonValue& result, const JsonRpcError& error)
        {
            if (error.isError)
            {
                cb(MediaSearchResult{}, error);
                return;
            }
            cb(parseSearchResult(result.toObject()), JsonRpcError{});
        });
}

QString ZaparooClient::mediaBrowse(const MediaBrowseParams& params, MediaBrowseCallback callback)
{
    QJsonObject jsonParams;
    if (!params.path.isEmpty())
    {
        jsonParams["path"] = params.path;
    }
    jsonParams["maxResults"] = params.maxResults;
    if (!params.cursor.isEmpty())
    {
        jsonParams["cursor"] = params.cursor;
    }
    if (!params.sort.isEmpty())
    {
        jsonParams["sort"] = params.sort;
    }

    return sendRequest(
        "media.browse", jsonParams,
        [cb = std::move(callback)](const QJsonValue& result, const JsonRpcError& error)
        {
            if (error.isError)
            {
                cb(MediaBrowseResult{}, error);
                return;
            }
            cb(parseBrowseResult(result.toObject()), JsonRpcError{});
        });
}

QString ZaparooClient::run(const RunParams& params, RunCallback callback)
{
    QJsonObject jsonParams;
    jsonParams["text"] = params.text;
    return sendRequest("run", jsonParams,
                       [cb = std::move(callback)](const QJsonValue&, const JsonRpcError& error)
                       { cb(RunResult{}, error); });
}

QString ZaparooClient::systems(const SystemsParams& /*params*/, SystemsCallback callback)
{
    return sendRequest(
        "systems", QJsonObject{},
        [cb = std::move(callback)](const QJsonValue& result, const JsonRpcError& error)
        {
            if (error.isError)
            {
                cb(SystemsResult{}, error);
                return;
            }
            cb(parseSystemsResult(result.toObject()), JsonRpcError{});
        });
}

} // namespace zaparoo
