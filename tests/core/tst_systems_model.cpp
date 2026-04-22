// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
// SPDX-FileCopyrightText: 2026 Callan Barrett

#include "MockServer.h"
#include "SystemsCatalog.h"
#include "SystemsModel.h"
#include "ZaparooClient.h"

#include <QJsonArray>
#include <QJsonObject>
#include <QSignalSpy>
#include <QTest>

using namespace zaparoo;

static QJsonObject makeSystem(const QString& id, const QString& name, const QString& category)
{
    return QJsonObject{{"id", id}, {"name", name}, {"category", category}};
}

static QJsonObject makeSystemsReply(const QJsonArray& systems)
{
    return QJsonObject{{"jsonrpc", "2.0"}, {"result", QJsonObject{{"systems", systems}}}};
}

class TestSystemsModel : public QObject
{
    Q_OBJECT

  private slots:
    void init() // NOLINT(readability-function-cognitive-complexity)
    {
        m_server = new MockServer(this);                // NOLINT(cppcoreguidelines-owning-memory)
        m_client = new ZaparooClient(this);             // NOLINT(cppcoreguidelines-owning-memory)
        m_catalog = new SystemsCatalog(m_client, this); // NOLINT(cppcoreguidelines-owning-memory)
        m_model = new SystemsModel(m_catalog, this);    // NOLINT(cppcoreguidelines-owning-memory)

        m_server->setReply(makeSystemsReply(QJsonArray{
            makeSystem("SNES", "Super Nintendo", "Console"),
            makeSystem("NES", "Nintendo", "Console"),
            makeSystem("GBC", "Gameboy Color", "Handheld"),
        }));
        m_client->connectToCore(
            QUrl(QStringLiteral("ws://127.0.0.1:%1/api/v0.1").arg(m_server->port())));
        QSignalSpy spy(m_catalog, &SystemsCatalog::catalogChanged);
        QTRY_COMPARE(spy.count(), 1);
    }

    void cleanup()
    {
        m_client->disconnectFromCore();
        delete m_model;
        m_model = nullptr;
        delete m_catalog;
        m_catalog = nullptr;
        delete m_client;
        m_client = nullptr;
        delete m_server;
        m_server = nullptr;
    }

    void testInitiallyEmpty() // NOLINT(readability-function-cognitive-complexity)
    {
        QCOMPARE(m_model->rowCount(), 0);
        QVERIFY(m_model->currentCategory().isEmpty());
    }

    void testSetCategoryFilters() // NOLINT(readability-function-cognitive-complexity)
    {
        QSignalSpy resetSpy(m_model, &SystemsModel::modelReset);
        m_model->setCategory("Console");
        QCOMPARE(resetSpy.count(), 1);
        QCOMPARE(m_model->rowCount(), 2);
        QCOMPARE(m_model->currentCategory(), "Console");
    }

    void testSetCategoryToHandheld() // NOLINT(readability-function-cognitive-complexity)
    {
        m_model->setCategory("Handheld");
        QCOMPARE(m_model->rowCount(), 1);
        QCOMPARE(m_model->systemIdAt(0), "GBC");
        QCOMPARE(m_model->systemNameAt(0), "Gameboy Color");
    }

    void testUnknownCategoryYieldsZeroRows() // NOLINT(readability-function-cognitive-complexity)
    {
        m_model->setCategory("Arcade");
        QCOMPARE(m_model->rowCount(), 0);
    }

    void testSystemsSortedByName() // NOLINT(readability-function-cognitive-complexity)
    {
        m_model->setCategory("Console");
        // Catalog sorts all systems by name; byCategory preserves that order.
        QCOMPARE(m_model->systemNameAt(0), "Nintendo");
        QCOMPARE(m_model->systemNameAt(1), "Super Nintendo");
    }

    void testOutOfBoundsInvokablesSafe() // NOLINT(readability-function-cognitive-complexity)
    {
        QVERIFY(m_model->systemIdAt(-1).isEmpty());
        QVERIFY(m_model->systemIdAt(99).isEmpty());
        QVERIFY(m_model->systemNameAt(-1).isEmpty());
    }

    void testModelResetsOnCatalogChange() // NOLINT(readability-function-cognitive-complexity)
    {
        m_model->setCategory("Console");
        QCOMPARE(m_model->rowCount(), 2);

        // Simulate a reconnect that delivers a fresh systems list.
        QSignalSpy resetSpy(m_model, &SystemsModel::modelReset);
        m_server->setReply(makeSystemsReply(QJsonArray{
            makeSystem("SNES", "Super Nintendo", "Console"),
        }));
        emit m_client->connected(); // trigger catalog refresh
        QTRY_COMPARE(resetSpy.count(), 1);
        QCOMPARE(m_model->rowCount(), 1);
    }

  private:                              // NOLINT(readability-redundant-access-specifiers)
    MockServer* m_server{nullptr};      // NOLINT(cppcoreguidelines-owning-memory)
    ZaparooClient* m_client{nullptr};   // NOLINT(cppcoreguidelines-owning-memory)
    SystemsCatalog* m_catalog{nullptr}; // NOLINT(cppcoreguidelines-owning-memory)
    SystemsModel* m_model{nullptr};     // NOLINT(cppcoreguidelines-owning-memory)
};

QTEST_GUILESS_MAIN(TestSystemsModel)

#include "tst_systems_model.moc"
