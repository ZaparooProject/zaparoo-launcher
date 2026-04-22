// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
// SPDX-FileCopyrightText: 2026 Callan Barrett

#include "GamesModel.h"
#include "MockServer.h"
#include "ZaparooClient.h"

#include <QJsonArray>
#include <QJsonObject>
#include <QSignalSpy>
#include <QTest>

using namespace zaparoo;

static QJsonObject makeSearchReply(const QJsonArray& results, bool hasNextPage = false)
{
    return QJsonObject{
        {"jsonrpc", "2.0"},
        {"result",
         QJsonObject{{"results", results},
                     {"total", -1},
                     {"pagination", QJsonObject{{"hasNextPage", hasNextPage},
                                                {"pageSize", static_cast<int>(results.size())}}}}}};
}

static QJsonObject makeGame(const QString& name, const QString& systemId = "SNES")
{
    return QJsonObject{
        {"name", name},
        {"path", systemId + "/" + name + ".sfc"},
        {"zapScript", "@" + systemId + "/" + name},
        {"system",
         QJsonObject{{"id", systemId}, {"name", "Super Nintendo"}, {"category", "Console"}}},
        {"tags", QJsonArray{}}};
}

class TestGamesModel : public QObject
{
    Q_OBJECT

  private slots:
    void init() // NOLINT(readability-function-cognitive-complexity)
    {
        m_server = new MockServer(this);          // NOLINT(cppcoreguidelines-owning-memory)
        m_client = new ZaparooClient(this);       // NOLINT(cppcoreguidelines-owning-memory)
        m_model = new GamesModel(m_client, this); // NOLINT(cppcoreguidelines-owning-memory)
        m_client->connectToCore(
            QUrl(QStringLiteral("ws://127.0.0.1:%1/api/v0.1").arg(m_server->port())));
        QTRY_VERIFY(m_client->isConnected() && m_server->hasClient());
    }

    void cleanup()
    {
        m_client->disconnectFromCore();
        delete m_model;
        m_model = nullptr;
        delete m_client;
        m_client = nullptr;
        delete m_server;
        m_server = nullptr;
    }

    void testInitiallyEmpty() // NOLINT(readability-function-cognitive-complexity)
    {
        QCOMPARE(m_model->rowCount(), 0);
        QVERIFY(m_model->currentSystemId().isEmpty());
        QVERIFY(!m_model->loading());
        QVERIFY(!m_model->hasNextPage());
    }

    void testSetSystemRequestFormat() // NOLINT(readability-function-cognitive-complexity)
    {
        m_server->setReply(makeSearchReply({}));
        QSignalSpy spy(m_server, &MockServer::frameReceived);
        m_model->setSystem("SNES");
        QTRY_COMPARE(spy.count(), 1);

        const QJsonObject frame = m_server->lastFrame();
        QCOMPARE(frame["method"].toString(), "media.search");
        const QJsonObject p = frame["params"].toObject();
        QVERIFY(!p.contains("query")); // blank query must be omitted
        const QJsonArray systems = p["systems"].toArray();
        QCOMPARE(systems.size(), 1);
        QCOMPARE(systems[0].toString(), "SNES");
        QCOMPARE(p["maxResults"].toInt(), 100);
    }

    void testSetSystemPopulatesRows() // NOLINT(readability-function-cognitive-complexity)
    {
        m_server->setReply(makeSearchReply(QJsonArray{
            makeGame("Super Mario World"),
            makeGame("Donkey Kong Country"),
        }));
        m_model->setSystem("SNES");
        QSignalSpy resetSpy(m_model, &GamesModel::modelReset);
        QTRY_COMPARE(resetSpy.count(), 1);

        QCOMPARE(m_model->rowCount(), 2);
        QCOMPARE(m_model->nameAt(0), "Super Mario World");
        QCOMPARE(m_model->nameAt(1), "Donkey Kong Country");
        QVERIFY(!m_model->loading());
    }

    void testLaunchAtSendsRun() // NOLINT(readability-function-cognitive-complexity)
    {
        m_server->setReply(makeSearchReply(QJsonArray{makeGame("Super Mario World")}));
        m_model->setSystem("SNES");
        QSignalSpy resetSpy(m_model, &GamesModel::modelReset);
        QTRY_COMPARE(resetSpy.count(), 1);

        QSignalSpy frameSpy(m_server, &MockServer::frameReceived);
        m_server->setReply(QJsonObject{{"jsonrpc", "2.0"}, {"result", QJsonValue::Null}});
        m_model->launchAt(0);
        QTRY_COMPARE(frameSpy.count(), 1);

        const QJsonObject frame = m_server->lastFrame();
        QCOMPARE(frame["method"].toString(), "run");
        QCOMPARE(frame["params"].toObject()["text"].toString(), "@SNES/Super Mario World");
    }

    void testErrorResponseSetsErrorMessage() // NOLINT(readability-function-cognitive-complexity)
    {
        m_server->setReply(QJsonObject{
            {"jsonrpc", "2.0"}, {"error", QJsonObject{{"code", 1}, {"message", "not indexed"}}}});
        m_model->setSystem("SNES");
        QSignalSpy spy(m_model, &GamesModel::errorMessageChanged);
        QTRY_COMPARE(spy.count(), 1);

        QCOMPARE(m_model->errorMessage(), "not indexed");
        QCOMPARE(m_model->rowCount(), 0);
        QVERIFY(!m_model->loading());
    }

    void testStaleResponseDropped() // NOLINT(readability-function-cognitive-complexity)
    {
        // Capture frames without auto-reply; send replies in controlled order.
        QList<QJsonObject> frames;
        connect(m_server, &MockServer::frameReceived, this,
                [&](const QJsonObject& f) { frames.append(f); });

        m_model->setSystem("NES");  // seq=1
        m_model->setSystem("SNES"); // seq=2

        QTRY_COMPARE(frames.size(), 2);

        // Reply to the second (SNES) request first.
        QJsonObject reply2 = makeSearchReply(QJsonArray{makeGame("New Game", "SNES")});
        reply2["id"] = frames[1]["id"].toString();
        m_server->sendToClient(reply2);
        QTRY_COMPARE(m_model->rowCount(), 1);

        // Reply to the first (NES) — stale seq, should be silently dropped.
        QJsonObject reply1 =
            makeSearchReply(QJsonArray{makeGame("Old Game 1"), makeGame("Old Game 2")});
        reply1["id"] = frames[0]["id"].toString();
        m_server->sendToClient(reply1);

        QTest::qWait(80);
        QCOMPARE(m_model->rowCount(), 1);
        QCOMPARE(m_model->nameAt(0), "New Game");
    }

    void testOutOfBoundsSafe() // NOLINT(readability-function-cognitive-complexity)
    {
        QVERIFY(m_model->nameAt(-1).isEmpty());
        QVERIFY(m_model->nameAt(99).isEmpty());
        m_model->launchAt(-1); // no crash
        m_model->launchAt(99); // no crash
        QTest::qWait(50);
    }

    void testHasNextPageReported() // NOLINT(readability-function-cognitive-complexity)
    {
        m_server->setReply(makeSearchReply(QJsonArray{makeGame("Game")}, /*hasNextPage=*/true));
        m_model->setSystem("DOS");
        QSignalSpy spy(m_model, &GamesModel::modelReset);
        QTRY_COMPARE(spy.count(), 1);

        QVERIFY(m_model->hasNextPage());
    }

  private:                            // NOLINT(readability-redundant-access-specifiers)
    MockServer* m_server{nullptr};    // NOLINT(cppcoreguidelines-owning-memory)
    ZaparooClient* m_client{nullptr}; // NOLINT(cppcoreguidelines-owning-memory)
    GamesModel* m_model{nullptr};     // NOLINT(cppcoreguidelines-owning-memory)
};

QTEST_GUILESS_MAIN(TestGamesModel)

#include "tst_games_model.moc"
