// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
// SPDX-FileCopyrightText: 2026 Callan Barrett

#include "BrowseModel.h"
#include "MockServer.h"
#include "ZaparooClient.h"

#include <QJsonArray>
#include <QJsonObject>
#include <QSignalSpy>
#include <QTest>

using namespace zaparoo;

// Build a minimal successful browse response.
static QJsonObject makeBrowseReply(const QJsonArray& entries)
{
    return QJsonObject{{"jsonrpc", "2.0"},
                       {"result", QJsonObject{{"path", ""},
                                              {"totalFiles", entries.size()},
                                              {"entries", entries},
                                              {"pagination", QJsonObject{{"hasNextPage", false},
                                                                         {"nextCursor", ""}}}}}};
}

static QJsonObject makeBrowseReplyForPath(const QString& path, const QJsonArray& entries)
{
    QJsonObject reply = makeBrowseReply(entries);
    reply["result"] = [&]()
    {
        QJsonObject r = reply["result"].toObject();
        r["path"] = path;
        return r;
    }();
    return reply;
}

static QJsonObject makeFolderEntry(const QString& name, const QString& path)
{
    return QJsonObject{{"name", name},    {"path", path},   {"type", "folder"},    {"systemId", ""},
                       {"zapScript", ""}, {"fileCount", 3}, {"tags", QJsonArray{}}};
}

static QJsonObject makeGameEntry(const QString& name, const QString& path)
{
    return QJsonObject{{"name", name},
                       {"path", path},
                       {"type", "file"},
                       {"systemId", "SNES"},
                       {"zapScript", "@SNES/" + path},
                       {"fileCount", 0},
                       {"tags", QJsonArray{}}};
}

class TestBrowseModel : public QObject
{
    Q_OBJECT

  private slots:
    void init() // NOLINT(readability-function-cognitive-complexity)
    {
        m_server = new MockServer(this);           // NOLINT(cppcoreguidelines-owning-memory)
        m_client = new ZaparooClient(this);        // NOLINT(cppcoreguidelines-owning-memory)
        m_model = new BrowseModel(m_client, this); // NOLINT(cppcoreguidelines-owning-memory)

        // Pre-set an empty reply so the auto-refresh from connected() completes cleanly.
        m_server->setReply(makeBrowseReply({}));
        m_client->connectToCore(
            QUrl(QStringLiteral("ws://127.0.0.1:%1/api/v0.1").arg(m_server->port())));
        QTRY_VERIFY(m_client->isConnected() && m_server->hasClient());
        QTRY_COMPARE(m_model->rowCount(), 0); // auto-refresh resolved
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

    void testBrowsePopulatesEntries() // NOLINT(readability-function-cognitive-complexity)
    {
        m_server->setReply(makeBrowseReply(
            {makeFolderEntry("Games", "Games"), makeGameEntry("Super Mario World", "Mario.sfc")}));
        m_model->refresh();
        QTRY_COMPARE(m_model->rowCount(), 2);
        QCOMPARE(m_model->nameAt(0), "Games");
        QCOMPARE(m_model->nameAt(1), "Super Mario World");
    }

    void testIsFolderDetection() // NOLINT(readability-function-cognitive-complexity)
    {
        m_server->setReply(makeBrowseReply(
            {makeFolderEntry("Systems", "Systems"), makeGameEntry("Zelda", "Zelda.sfc")}));
        m_model->refresh();
        QTRY_COMPARE(m_model->rowCount(), 2);
        QVERIFY(m_model->isFolderAt(0));
        QVERIFY(!m_model->isFolderAt(1));
    }

    void testRoleDataMatchesEntry() // NOLINT(readability-function-cognitive-complexity)
    {
        m_server->setReply(makeBrowseReply({makeFolderEntry("SNES", "SNES")}));
        m_model->refresh();
        QTRY_COMPARE(m_model->rowCount(), 1);

        const QModelIndex idx = m_model->index(0);
        QCOMPARE(m_model->data(idx, BrowseModel::NameRole).toString(), "SNES");
        QCOMPARE(m_model->data(idx, BrowseModel::PathRole).toString(), "SNES");
        QCOMPARE(m_model->data(idx, BrowseModel::IsFolderRole).toBool(), true);
        QCOMPARE(m_model->data(idx, BrowseModel::FileCountRole).toInt(), 3);
    }

    void testEnterFolderUpdatesState() // NOLINT(readability-function-cognitive-complexity)
    {
        m_server->setReply(makeBrowseReply({makeFolderEntry("SNES", "SNES")}));
        m_model->refresh();
        QTRY_COMPARE(m_model->rowCount(), 1);
        QVERIFY(!m_model->canGoBack());

        m_server->setReply(
            makeBrowseReplyForPath("SNES", {makeGameEntry("Super Mario World", "Mario.sfc")}));
        QSignalSpy resetSpy(m_model, &QAbstractItemModel::modelReset);
        m_model->enter(0);
        QTRY_COMPARE(resetSpy.count(), 1);

        QCOMPARE(m_model->rowCount(), 1);
        QCOMPARE(m_model->currentPath(), "SNES");
        QVERIFY(m_model->canGoBack());
    }

    void testGoBackRestoresIndex() // NOLINT(readability-function-cognitive-complexity)
    {
        // Navigate into a folder at index 1.
        m_server->setReply(
            makeBrowseReply({makeFolderEntry("SNES", "SNES"), makeFolderEntry("NES", "NES")}));
        m_model->refresh();
        QTRY_COMPARE(m_model->rowCount(), 2);

        m_server->setReply(makeBrowseReplyForPath("NES", {makeGameEntry("Zelda", "Zelda.nes")}));
        m_model->enter(1);
        QTRY_COMPARE(m_model->currentPath(), "NES");

        // Go back — modelReset must fire before indexRestored (Main.qml depends on this order).
        m_server->setReply(
            makeBrowseReply({makeFolderEntry("SNES", "SNES"), makeFolderEntry("NES", "NES")}));
        QList<QByteArray> signalOrder;
        connect(m_model, &QAbstractItemModel::modelReset, this,
                [&]() { signalOrder.append("modelReset"); });
        connect(m_model, &BrowseModel::indexRestored, this,
                [&](int) { signalOrder.append("indexRestored"); });
        QSignalSpy indexSpy(m_model, &BrowseModel::indexRestored);
        m_model->goBack();
        QTRY_COMPARE(indexSpy.count(), 1);

        QCOMPARE(indexSpy.first().first().toInt(), 1);
        QCOMPARE(m_model->currentPath(), "");
        QVERIFY(!m_model->canGoBack());
        QVERIFY(signalOrder.size() >= 2);
        QCOMPARE(signalOrder[0], QByteArray("modelReset"));
        QCOMPARE(signalOrder[1], QByteArray("indexRestored"));
    }

    void testEnterOnErrorDoesNotCorruptStack() // NOLINT(readability-function-cognitive-complexity)
    {
        m_server->setReply(makeBrowseReply({makeFolderEntry("SNES", "SNES")}));
        m_model->refresh();
        QTRY_COMPARE(m_model->rowCount(), 1);
        QVERIFY(!m_model->canGoBack());

        const QJsonObject errorReply{
            {"jsonrpc", "2.0"}, {"error", QJsonObject{{"code", 404}, {"message", "not found"}}}};
        m_server->setReply(errorReply);

        QSignalSpy errorSpy(m_model, &BrowseModel::errorMessageChanged);
        m_model->enter(0);
        QTRY_COMPARE(errorSpy.count(), 1);

        QVERIFY(!m_model->canGoBack());
        QCOMPARE(m_model->currentPath(), "");
        QCOMPARE(m_model->errorMessage(), "not found");
    }

    void testStaleResponseDropped() // NOLINT(readability-function-cognitive-complexity)
    {
        // Fire two refreshes; hold both responses, then reply only to the second.
        // After that, reply to the first — its response should be ignored.

        // Capture both pending request ids.
        QList<QJsonObject> frames;
        connect(m_server, &MockServer::frameReceived, this,
                [&](const QJsonObject& f) { frames.append(f); });

        // Don't auto-reply — capture frames manually.
        m_model->refresh(); // seq=1 (gets current m_seq after increment)
        m_model->refresh(); // seq=2

        QTRY_COMPARE(frames.size(), 2);

        // Reply to the second request (frames[1]).
        const QString secondId = frames[1]["id"].toString();
        QJsonObject reply2 = makeBrowseReply({makeGameEntry("NewGame", "foo.sfc")});
        reply2["id"] = secondId;
        m_server->sendToClient(reply2);
        QTRY_COMPARE(m_model->rowCount(), 1);

        // Now reply to the first — it should be silently dropped.
        const QString firstId = frames[0]["id"].toString();
        QJsonObject reply1 = makeBrowseReply(
            {makeGameEntry("OldGame1", "bar.sfc"), makeGameEntry("OldGame2", "baz.sfc")});
        reply1["id"] = firstId;
        m_server->sendToClient(reply1);

        // Give the event loop time to process and verify nothing changed.
        QTest::qWait(80);
        QCOMPARE(m_model->rowCount(), 1);
        QCOMPARE(m_model->nameAt(0), "NewGame");
    }

    void testErrorSetsMessageAndClearsLoading() // NOLINT(readability-function-cognitive-complexity)
    {
        const QJsonObject errorReply{
            {"jsonrpc", "2.0"},
            {"error", QJsonObject{{"code", 404}, {"message", "path not found"}}}};
        m_server->setReply(errorReply);

        QSignalSpy errorSpy(m_model, &BrowseModel::errorMessageChanged);
        m_model->refresh();
        QTRY_COMPARE(errorSpy.count(), 1);

        QCOMPARE(m_model->errorMessage(), "path not found");
        QVERIFY(!m_model->loading());
    }

    void testEmptyFolderNoRowCount() // NOLINT(readability-function-cognitive-complexity)
    {
        m_server->setReply(makeBrowseReply({}));
        m_model->refresh();
        QTRY_VERIFY(!m_model->loading());
        QCOMPARE(m_model->rowCount(), 0);
    }

    void testOutOfBoundsQueriesSafe() // NOLINT(readability-function-cognitive-complexity)
    {
        QCOMPARE(m_model->nameAt(-1), "");
        QCOMPARE(m_model->nameAt(0), "");
        QVERIFY(!m_model->isFolderAt(0));
        m_model->enter(-1); // no crash
        m_model->enter(99); // no crash
        m_model->goBack();  // no crash on empty stack
    }

    void testLaunchAtSendsRunRequest() // NOLINT(readability-function-cognitive-complexity)
    {
        m_server->setReply(makeBrowseReply({makeGameEntry("Super Mario World", "Mario.sfc")}));
        m_model->refresh();
        QTRY_COMPARE(m_model->rowCount(), 1);

        QList<QJsonObject> frames;
        connect(m_server, &MockServer::frameReceived, this,
                [&](const QJsonObject& f) { frames.append(f); });

        m_model->launchAt(0);
        QTRY_COMPARE(frames.size(), 1);

        QCOMPARE(frames[0]["method"].toString(), "run");
        QCOMPARE(frames[0]["params"].toObject()["text"].toString(), "@SNES/Mario.sfc");
    }

    void testLaunchAtIgnoresFolders() // NOLINT(readability-function-cognitive-complexity)
    {
        m_server->setReply(makeBrowseReply({makeFolderEntry("SNES", "SNES")}));
        m_model->refresh();
        QTRY_COMPARE(m_model->rowCount(), 1);

        QList<QJsonObject> frames;
        connect(m_server, &MockServer::frameReceived, this,
                [&](const QJsonObject& f) { frames.append(f); });

        m_model->launchAt(0);
        QTest::qWait(80);
        QCOMPARE(frames.size(), 0); // no run request sent for a folder
    }

    void testLaunchAtOutOfBoundsSafe() // NOLINT(readability-function-cognitive-complexity)
    {
        m_model->launchAt(-1); // no crash
        m_model->launchAt(99); // no crash
        QTest::qWait(50);      // nothing sent to server
    }

  private:                            // NOLINT(readability-redundant-access-specifiers)
    MockServer* m_server{nullptr};    // NOLINT(cppcoreguidelines-owning-memory)
    ZaparooClient* m_client{nullptr}; // NOLINT(cppcoreguidelines-owning-memory)
    BrowseModel* m_model{nullptr};    // NOLINT(cppcoreguidelines-owning-memory)
};

QTEST_GUILESS_MAIN(TestBrowseModel)

#include "tst_browse_model.moc"
