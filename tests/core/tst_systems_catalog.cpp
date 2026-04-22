// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
// SPDX-FileCopyrightText: 2026 Callan Barrett

#include "MockServer.h"
#include "SystemsCatalog.h"
#include "ZaparooClient.h"

#include <QJsonArray>
#include <QJsonObject>
#include <QSignalSpy>
#include <QTest>

using namespace zaparoo;

static QJsonObject makeSystemsReply(const QJsonArray& systems)
{
    return QJsonObject{{"jsonrpc", "2.0"}, {"result", QJsonObject{{"systems", systems}}}};
}

static QJsonObject makeSystem(const QString& id, const QString& name, const QString& category)
{
    return QJsonObject{{"id", id}, {"name", name}, {"category", category}};
}

class TestSystemsCatalog : public QObject
{
    Q_OBJECT

  private slots:
    void init()
    {
        m_server = new MockServer(this);                // NOLINT(cppcoreguidelines-owning-memory)
        m_client = new ZaparooClient(this);             // NOLINT(cppcoreguidelines-owning-memory)
        m_catalog = new SystemsCatalog(m_client, this); // NOLINT(cppcoreguidelines-owning-memory)
    }

    void cleanup()
    {
        m_client->disconnectFromCore();
        delete m_catalog;
        m_catalog = nullptr;
        delete m_client;
        m_client = nullptr;
        delete m_server;
        m_server = nullptr;
    }

    void testCategoriesDeduped() // NOLINT(readability-function-cognitive-complexity)
    {
        m_server->setReply(makeSystemsReply(QJsonArray{
            makeSystem("SNES", "Super Nintendo", "Console"),
            makeSystem("NES", "Nintendo", "Console"), // same category
            makeSystem("GBC", "Gameboy Color", "Handheld"),
        }));
        QSignalSpy spy(m_catalog, &SystemsCatalog::catalogChanged);
        m_client->connectToCore(
            QUrl(QStringLiteral("ws://127.0.0.1:%1/api/v0.1").arg(m_server->port())));
        QTRY_COMPARE(spy.count(), 1);

        const QStringList cats = m_catalog->categories();
        QCOMPARE(cats.size(), 2);
        QVERIFY(cats.contains("Console"));
        QVERIFY(cats.contains("Handheld"));
    }

    void testCategoriesSortedCaseInsensitive() // NOLINT(readability-function-cognitive-complexity)
    {
        m_server->setReply(makeSystemsReply(QJsonArray{
            makeSystem("A", "Zebra System", "Zzz"),
            makeSystem("B", "Alpha System", "aaa"),
        }));
        QSignalSpy spy(m_catalog, &SystemsCatalog::catalogChanged);
        m_client->connectToCore(
            QUrl(QStringLiteral("ws://127.0.0.1:%1/api/v0.1").arg(m_server->port())));
        QTRY_COMPARE(spy.count(), 1);

        const QStringList cats = m_catalog->categories();
        QCOMPARE(cats.size(), 2);
        QVERIFY(cats[0].compare("aaa", Qt::CaseInsensitive) == 0);
        QVERIFY(cats[1].compare("Zzz", Qt::CaseInsensitive) == 0);
    }

    void testEmptyCategoryBucketedAsOther() // NOLINT(readability-function-cognitive-complexity)
    {
        m_server->setReply(makeSystemsReply(QJsonArray{
            makeSystem("MAME", "MAME", ""),
            makeSystem("SNES", "Super Nintendo", "Console"),
        }));
        QSignalSpy spy(m_catalog, &SystemsCatalog::catalogChanged);
        m_client->connectToCore(
            QUrl(QStringLiteral("ws://127.0.0.1:%1/api/v0.1").arg(m_server->port())));
        QTRY_COMPARE(spy.count(), 1);

        QVERIFY(m_catalog->categories().contains("Other"));
        const QVector<SystemInfo> other = m_catalog->byCategory("Other");
        QCOMPARE(other.size(), 1);
        QCOMPARE(other[0].id, "MAME");
    }

    void testByCategoryFilters() // NOLINT(readability-function-cognitive-complexity)
    {
        m_server->setReply(makeSystemsReply(QJsonArray{
            makeSystem("SNES", "Super Nintendo", "Console"),
            makeSystem("NES", "Nintendo", "Console"),
            makeSystem("GBC", "Gameboy Color", "Handheld"),
        }));
        QSignalSpy spy(m_catalog, &SystemsCatalog::catalogChanged);
        m_client->connectToCore(
            QUrl(QStringLiteral("ws://127.0.0.1:%1/api/v0.1").arg(m_server->port())));
        QTRY_COMPARE(spy.count(), 1);

        const QVector<SystemInfo> consoles = m_catalog->byCategory("Console");
        QCOMPARE(consoles.size(), 2);

        const QVector<SystemInfo> handheld = m_catalog->byCategory("Handheld");
        QCOMPARE(handheld.size(), 1);
        QCOMPARE(handheld[0].id, "GBC");

        QCOMPARE(m_catalog->byCategory("Unknown").size(), 0);
    }

    void testSystemsSortedByName() // NOLINT(readability-function-cognitive-complexity)
    {
        m_server->setReply(makeSystemsReply(QJsonArray{
            makeSystem("B", "Zebra", "Console"),
            makeSystem("A", "Apple", "Console"),
        }));
        QSignalSpy spy(m_catalog, &SystemsCatalog::catalogChanged);
        m_client->connectToCore(
            QUrl(QStringLiteral("ws://127.0.0.1:%1/api/v0.1").arg(m_server->port())));
        QTRY_COMPARE(spy.count(), 1);

        const QVector<SystemInfo> all = m_catalog->all();
        QCOMPARE(all.size(), 2);
        QCOMPARE(all[0].name, "Apple");
        QCOMPARE(all[1].name, "Zebra");
    }

  private:                              // NOLINT(readability-redundant-access-specifiers)
    MockServer* m_server{nullptr};      // NOLINT(cppcoreguidelines-owning-memory)
    ZaparooClient* m_client{nullptr};   // NOLINT(cppcoreguidelines-owning-memory)
    SystemsCatalog* m_catalog{nullptr}; // NOLINT(cppcoreguidelines-owning-memory)
};

QTEST_GUILESS_MAIN(TestSystemsCatalog)

#include "tst_systems_catalog.moc"
