// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
// SPDX-FileCopyrightText: 2026 Callan Barrett

#include "Config.h"

#include <QDir>
#include <QTemporaryDir>
#include <QTest>

using namespace zaparoo;

// NOLINTBEGIN(readability-convert-member-functions-to-static)
class TstConfig : public QObject
{
    Q_OBJECT

  private slots:
    void defaults_on_missing_file()
    {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        const Config cfg = loadConfigFrom(dir.filePath("nonexistent.conf"));
        const Config dflt;
        QCOMPARE(cfg.coreEndpoint, dflt.coreEndpoint);
        QCOMPARE(cfg.videoWidth, dflt.videoWidth);
        QCOMPARE(cfg.videoHeight, dflt.videoHeight);
    }

    void roundtrip()
    {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        const QString path = dir.filePath("launcher.conf");

        Config original;
        original.coreEndpoint = QUrl("ws://192.168.1.42:7497/api/v0.1");
        original.videoWidth = 1280;
        original.videoHeight = 720;

        saveConfigTo(path, original);
        QVERIFY(QFile::exists(path));

        const Config loaded = loadConfigFrom(path);
        QCOMPARE(loaded.coreEndpoint, original.coreEndpoint);
        QCOMPARE(loaded.videoWidth, original.videoWidth);
        QCOMPARE(loaded.videoHeight, original.videoHeight);
    }

    void defaults_on_malformed_toml()
    {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        const QString path = dir.filePath("launcher.conf");

        QFile f(path);
        QVERIFY(f.open(QIODevice::WriteOnly | QIODevice::Text));
        f.write("this is not [ valid toml !!!\n");
        f.close();

        const Config cfg = loadConfigFrom(path);
        const Config dflt;
        QCOMPARE(cfg.videoWidth, dflt.videoWidth);
        QCOMPARE(cfg.videoHeight, dflt.videoHeight);
    }

    void partial_overrides_keep_defaults()
    {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        const QString path = dir.filePath("launcher.conf");

        QFile f(path);
        QVERIFY(f.open(QIODevice::WriteOnly | QIODevice::Text));
        f.write("[video]\nwidth = 640\n");
        f.close();

        const Config cfg = loadConfigFrom(path);
        QCOMPARE(cfg.videoWidth, 640);
        QCOMPARE(cfg.videoHeight, Config{}.videoHeight); // default preserved
    }

    void core_url_parsed_from_handwritten_toml()
    {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        const QString path = dir.filePath("launcher.conf");

        QFile f(path);
        QVERIFY(f.open(QIODevice::WriteOnly | QIODevice::Text));
        f.write("[core]\nurl = \"ws://1.2.3.4:7497/api/v0.1\"\n");
        f.close();

        const Config cfg = loadConfigFrom(path);
        QCOMPARE(cfg.coreEndpoint, QUrl("ws://1.2.3.4:7497/api/v0.1"));
        QCOMPARE(cfg.videoWidth, Config{}.videoWidth);
        QCOMPARE(cfg.videoHeight, Config{}.videoHeight);
    }

    void save_creates_parent_directory()
    {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        const QString path = dir.filePath("subdir/nested/launcher.conf");

        saveConfigTo(path, Config{});
        QVERIFY(QFile::exists(path));
    }

    void save_fails_silently_on_readonly_path()
    {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        QFile::setPermissions(dir.path(), QFileDevice::ReadOwner | QFileDevice::ExeOwner);

        const QString path = dir.filePath("launcher.conf");
        saveConfigTo(path, Config{}); // must not crash
        QVERIFY(!QFile::exists(path));

        // Restore permissions so QTemporaryDir can clean up.
        QFile::setPermissions(dir.path(), QFileDevice::ReadOwner | QFileDevice::WriteOwner |
                                              QFileDevice::ExeOwner);
    }
};
// NOLINTEND(readability-convert-member-functions-to-static)

QTEST_GUILESS_MAIN(TstConfig)
#include "tst_config.moc"
