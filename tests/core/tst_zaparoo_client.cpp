// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
// SPDX-FileCopyrightText: 2026 Callan Barrett

#include "MediaTypes.h"
#include "ZaparooClient.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSignalSpy>
#include <QTest>
#include <QWebSocket>
#include <QWebSocketServer>

using namespace zaparoo;

// Local WebSocket server that records incoming frames and can reply on demand.
class MockServer : public QObject
{
    Q_OBJECT

  public:
    explicit MockServer(QObject* parent = nullptr)
        : QObject(parent), m_server("mock", QWebSocketServer::NonSecureMode, this)
    {
        if (!m_server.listen(QHostAddress::LocalHost, 0))
        {
            qFatal("MockServer: listen failed");
        }
        connect(&m_server, &QWebSocketServer::newConnection, this, &MockServer::onNewConnection);
    }

    [[nodiscard]] quint16 port() const
    {
        return m_server.serverPort();
    }
    [[nodiscard]] bool hasClient() const
    {
        return m_peer != nullptr;
    }
    [[nodiscard]] QJsonObject lastFrame() const
    {
        return m_lastFrame;
    }

    void setReply(const QJsonObject& reply)
    {
        m_reply = reply;
    }

    void sendToClient(const QJsonObject& frame)
    {
        if (m_peer != nullptr)
        {
            m_peer->sendTextMessage(
                QString::fromUtf8(QJsonDocument(frame).toJson(QJsonDocument::Compact)));
        }
    }

    void sendRawToClient(const QString& text)
    {
        if (m_peer != nullptr)
        {
            m_peer->sendTextMessage(text);
        }
    }

  signals:
    void frameReceived();
    void clientConnected();

  private slots:
    void onNewConnection()
    {
        m_peer = m_server.nextPendingConnection();
        connect(m_peer, &QWebSocket::textMessageReceived, this, &MockServer::onMessage);
        emit clientConnected();
    }

    void onMessage(const QString& msg)
    {
        m_lastFrame = QJsonDocument::fromJson(msg.toUtf8()).object();
        if (!m_reply.isEmpty())
        {
            QJsonObject reply = m_reply;
            reply["id"] = m_lastFrame["id"];
            m_reply = {};
            sendToClient(reply);
        }
        emit frameReceived();
    }

    QWebSocketServer m_server;
    QJsonObject m_reply;
    QJsonObject m_lastFrame;
    QWebSocket* m_peer{nullptr};
};

class TestZaparooClient : public QObject
{
    Q_OBJECT

  private slots:
    void init() // NOLINT(readability-function-cognitive-complexity)
    {
        m_server = new MockServer(this);    // NOLINT(cppcoreguidelines-owning-memory)
        m_client = new ZaparooClient(this); // NOLINT(cppcoreguidelines-owning-memory)
        m_client->connectToCore(
            QUrl(QStringLiteral("ws://127.0.0.1:%1/api/v0.1").arg(m_server->port())));
        QTRY_VERIFY(m_client->isConnected() && m_server->hasClient());
    }

    void cleanup()
    {
        m_client->disconnectFromCore();
        delete m_client;
        m_client = nullptr;
        delete m_server;
        m_server = nullptr;
    }

    void testMediaSearchRequestFormat() // NOLINT(readability-function-cognitive-complexity)
    {
        MediaSearchParams params;
        params.query = "mario";
        params.systems = {"SNES"};
        params.maxResults = 10;

        QSignalSpy spy(m_server, &MockServer::frameReceived);
        m_client->mediaSearch(params, [](const MediaSearchResult&, const JsonRpcError&) {});
        QTRY_COMPARE(spy.count(), 1);

        const QJsonObject frame = m_server->lastFrame();
        QCOMPARE(frame["jsonrpc"].toString(), "2.0");
        QCOMPARE(frame["method"].toString(), "media.search");
        QVERIFY(!frame["id"].toString().isEmpty());

        const QJsonObject p = frame["params"].toObject();
        QCOMPARE(p["query"].toString(), "mario");
        QCOMPARE(p["maxResults"].toInt(), 10);

        const QJsonArray systems = p["systems"].toArray();
        QCOMPARE(systems.size(), 1);
        QCOMPARE(systems[0].toString(), "SNES");
    }

    void testMediaSearchResponseParsing() // NOLINT(readability-function-cognitive-complexity)
    {
        QJsonObject reply;
        reply["jsonrpc"] = "2.0";
        reply["result"] = QJsonObject{
            {"results",
             QJsonArray{QJsonObject{
                 {"name", "Super Mario World"},
                 {"path", "SNES/Super Mario World.sfc"},
                 {"zapScript", "@SNES/Super Mario World"},
                 {"system",
                  QJsonObject{{"id", "SNES"}, {"name", "Super Nintendo"}, {"category", "Console"}}},
                 {"tags", QJsonArray{QJsonObject{{"tag", "platformer"}, {"type", "genre"}}}}}}},
            {"pagination",
             QJsonObject{{"hasNextPage", false}, {"pageSize", 10}, {"nextCursor", ""}}}};
        m_server->setReply(reply);

        MediaSearchResult result;
        JsonRpcError error;
        bool done = false;
        m_client->mediaSearch({},
                              [&](const MediaSearchResult& r, const JsonRpcError& e)
                              {
                                  result = r;
                                  error = e;
                                  done = true;
                              });

        QTRY_VERIFY(done);
        QVERIFY(!error.isError);
        QCOMPARE(result.results.size(), 1);
        QCOMPARE(result.results[0].name, "Super Mario World");
        QCOMPARE(result.results[0].system.id, "SNES");
        QCOMPARE(result.results[0].system.category, "Console");
        QCOMPARE(result.results[0].tags.size(), 1);
        QCOMPARE(result.results[0].tags[0].tag, "platformer");
        QCOMPARE(result.hasNextPage, false);
        QCOMPARE(result.pageSize, 10);
    }

    void testTokensAddedNotification() // NOLINT(readability-function-cognitive-complexity)
    {
        QSignalSpy spy(m_client, &ZaparooClient::scanReceived);

        m_server->sendToClient(QJsonObject{{"jsonrpc", "2.0"},
                                           {"method", "tokens.added"},
                                           {"params", QJsonObject{{"uid", "04E1234567890"},
                                                                  {"text", "**launch.system:snes"},
                                                                  {"type", "nfc"}}}});

        QTRY_COMPARE(spy.count(), 1);
        const QList<QVariant> args = spy.takeFirst();
        QCOMPARE(args[0].toString(), "04E1234567890");
        QCOMPARE(args[1].toString(), "**launch.system:snes");
    }

    void testErrorResponseRouting() // NOLINT(readability-function-cognitive-complexity)
    {
        QJsonObject reply;
        reply["jsonrpc"] = "2.0";
        reply["error"] = QJsonObject{{"code", 1}, {"message", "invalid cursor"}};
        m_server->setReply(reply);

        JsonRpcError error;
        bool done = false;
        m_client->mediaSearch({},
                              [&](const MediaSearchResult&, const JsonRpcError& e)
                              {
                                  error = e;
                                  done = true;
                              });

        QTRY_VERIFY(done);
        QVERIFY(error.isError);
        QCOMPARE(error.code, 1);
        QCOMPARE(error.message, "invalid cursor");
    }

    void testMediaBrowseRequestFormat() // NOLINT(readability-function-cognitive-complexity)
    {
        MediaBrowseParams params;
        params.path = "SNES";
        params.maxResults = 20;
        params.sort = "name";

        QSignalSpy spy(m_server, &MockServer::frameReceived);
        m_client->mediaBrowse(params, [](const MediaBrowseResult&, const JsonRpcError&) {});
        QTRY_COMPARE(spy.count(), 1);

        const QJsonObject frame = m_server->lastFrame();
        QCOMPARE(frame["jsonrpc"].toString(), "2.0");
        QCOMPARE(frame["method"].toString(), "media.browse");
        QVERIFY(!frame["id"].toString().isEmpty());

        const QJsonObject p = frame["params"].toObject();
        QCOMPARE(p["path"].toString(), "SNES");
        QCOMPARE(p["maxResults"].toInt(), 20);
        QCOMPARE(p["sort"].toString(), "name");
    }

    void testSendWhileDisconnected() // NOLINT(readability-function-cognitive-complexity)
    {
        m_client->disconnectFromCore();
        QTRY_VERIFY(!m_client->isConnected());

        JsonRpcError error;
        bool done = false;
        m_client->mediaSearch({},
                              [&](const MediaSearchResult&, const JsonRpcError& e)
                              {
                                  error = e;
                                  done = true;
                              });

        QVERIFY(done);
        QVERIFY(error.isError);
        QCOMPARE(error.code, -1);
    }

    void testRunRequestFormat() // NOLINT(readability-function-cognitive-complexity)
    {
        RunParams params;
        params.text = "@SNES/Mario.sfc";

        QSignalSpy spy(m_server, &MockServer::frameReceived);
        m_client->run(params, [](const RunResult&, const JsonRpcError&) {});
        QTRY_COMPARE(spy.count(), 1);

        const QJsonObject frame = m_server->lastFrame();
        QCOMPARE(frame["jsonrpc"].toString(), "2.0");
        QCOMPARE(frame["method"].toString(), "run");
        QVERIFY(!frame["id"].toString().isEmpty());

        const QJsonObject p = frame["params"].toObject();
        QCOMPARE(p["text"].toString(), "@SNES/Mario.sfc");
    }

    void testMalformedFramesIgnoredGracefully() // NOLINT(readability-function-cognitive-complexity)
    {
        // Send a JSON array instead of an object — should be ignored, no crash.
        m_server->sendRawToClient("[1,2,3]");

        // Send a valid response with a numeric id — should be ignored.
        m_server->sendRawToClient(R"({"jsonrpc":"2.0","id":42,"result":{}})");

        // Send a response with an id that has no pending request — should be ignored.
        m_server->sendRawToClient(R"({"jsonrpc":"2.0","id":"no-such-id","result":{}})");

        // Give the event loop a moment to process all three frames.
        QTest::qWait(100);

        // Verify the client is still functional after receiving bad frames.
        QSignalSpy spy(m_server, &MockServer::frameReceived);
        m_client->mediaSearch({}, [](const MediaSearchResult&, const JsonRpcError&) {});
        QTRY_COMPARE(spy.count(), 1);
    }

    MockServer* m_server{nullptr};    // NOLINT(cppcoreguidelines-owning-memory)
    ZaparooClient* m_client{nullptr}; // NOLINT(cppcoreguidelines-owning-memory)
};

QTEST_GUILESS_MAIN(TestZaparooClient)

#include "tst_zaparoo_client.moc"
