// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//
// Thin C++ entry point for the Rust launcher. Domain logic lives in the
// zaparoo_launcher_rs staticlib; Qt plugin wiring is handled here so that
// Qt's CMake (qt_import_qml_plugins) can emit the correct link flags.

#include <QFontDatabase>
#include <QGuiApplication>
#include <QLocale>
#include <QPixmapCache>
#include <QQmlApplicationEngine>
#include <QQuickStyle>
#include <QString>
#include <QTranslator>
#include <QUrl>
#include <QtQml/qqmlextensionplugin.h>
#include <cstddef>
#include <cstdint>

// Default QPixmapCache cap is 10 MiB. With ~100 system PNGs decoded at
// 256 px sourceSize the working set straddles that limit, so navigating
// through every category evicts earlier system covers and re-decodes
// them on the next visit. Bumping to 50 MiB keeps the entire system-
// cover set resident across category swaps for the cost of a one-time
// allocation — a worthwhile trade on MiSTer's 1 GiB DDR3 since
// pixmap decode on the UI thread is the visible "pop in" the user
// flagged.
constexpr int kPixmapCacheLimitKiB = 50 * 1024;

extern "C" int zaparoo_rust_init();
extern "C" void zaparoo_rust_post_qt_start();
extern "C" void zaparoo_log_qt(uint8_t level, const char* msg, size_t len);
extern "C" const char* zaparoo_rust_language_code();

// Pull Zaparoo QML plugin symbols into the final binary so the linker does
// not strip their static-initializer registration functions.
Q_IMPORT_QML_PLUGIN(Zaparoo_AppPlugin)
Q_IMPORT_QML_PLUGIN(Zaparoo_UiPlugin)
Q_IMPORT_QML_PLUGIN(Zaparoo_ThemePlugin)
Q_IMPORT_QML_PLUGIN(Zaparoo_ScreensPlugin)
Q_IMPORT_QML_PLUGIN(Zaparoo_Browse_plugin)

// For static Qt builds (MiSTer ARM32): the QtQuick.Controls plugin chain and
// platform plugin are embedded in the binary, not found on disk, so they
// must be explicitly imported. On dynamic (desktop) Qt these are loaded
// automatically and the symbols don't exist as static functions.
#ifdef QT_STATIC
#include <QtPlugin>
Q_IMPORT_QML_PLUGIN(QtQuickControls2Plugin)
Q_IMPORT_QML_PLUGIN(QtQuickControls2BasicStylePlugin)
Q_IMPORT_QML_PLUGIN(QtQuickControls2ImplPlugin)
Q_IMPORT_QML_PLUGIN(QtQuickTemplates2Plugin)
Q_IMPORT_QML_PLUGIN(QtQuick_WindowPlugin)
Q_IMPORT_PLUGIN(QLinuxFbIntegrationPlugin)
#endif

// Forward all Qt log messages to the Rust tracing registry (same sinks as
// Rust-side log output: stderr + launcher.log). Installed after
// zaparoo_rust_init() so the tracing subscriber is already alive.
static void qtMessageHandler(QtMsgType type, const QMessageLogContext& /*ctx*/, const QString& msg)
{
    const QByteArray utf8 = msg.toUtf8();
    zaparoo_log_qt(static_cast<uint8_t>(type), utf8.constData(), static_cast<size_t>(utf8.size()));
}

int main(int argc, char* argv[])
{
    QGuiApplication::setApplicationName("Zaparoo Launcher");
    QGuiApplication::setApplicationVersion("0.1.0");
    QGuiApplication::setOrganizationName("Zaparoo");
    QGuiApplication::setOrganizationDomain("zaparoo.org");

    if (zaparoo_rust_init() != 0)
    {
        return EXIT_FAILURE;
    }

    // Install after zaparoo_rust_init() so tracing is live before any Qt
    // messages are emitted.
    qInstallMessageHandler(qtMessageHandler);

    QGuiApplication app(argc, argv);
    QPixmapCache::setCacheLimit(kPixmapCacheLimitKiB);
    // addApplicationFont returns -1 on failure (broken qrc path,
    // unreadable file). Logging the failure mode keeps a refactor that
    // breaks the resource alias from silently degrading to the default
    // font with no clue in the logs.
    const QString regularPath =
        QStringLiteral(":/qt/qml/Zaparoo/App/resources/fonts/AtkinsonHyperlegible-Regular.ttf");
    const QString boldPath =
        QStringLiteral(":/qt/qml/Zaparoo/App/resources/fonts/AtkinsonHyperlegible-Bold.ttf");
    if (QFontDatabase::addApplicationFont(regularPath) == -1)
    {
        qWarning("Failed to register font: %s", qUtf8Printable(regularPath));
    }
    if (QFontDatabase::addApplicationFont(boldPath) == -1)
    {
        qWarning("Failed to register font: %s", qUtf8Printable(boldPath));
    }
    QQuickStyle::setStyle("Basic");

    // Install the locale .qm translator before constructing the QML engine
    // so qsTr() lookups in Main.qml's initial bindings see translated text.
    // The Rust side resolves `[general] language` from launcher.toml into a
    // BCP-47 tag ("ja", "de_DE") or an empty string (follow system locale).
    // Stack lifetime is fine — `translator` outlives app.exec() and all QML.
    const QString langCode = QString::fromUtf8(zaparoo_rust_language_code());
    const QLocale locale = langCode.isEmpty() ? QLocale::system() : QLocale(langCode);
    QTranslator translator;
    if (translator.load(locale, "launcher", "_", ":/i18n"))
    {
        QCoreApplication::installTranslator(&translator);
    }
    else
    {
        // Not an error on first run (English-only build ships a passthrough
        // launcher_en.qm). Log at info so the sink records the resolved
        // locale for bug reports without spamming at warn level.
        qInfo("No translation catalog for %s in :/i18n; using source strings",
              qUtf8Printable(locale.name()));
    }

    QQmlApplicationEngine engine;
#ifndef ZAPAROO_DEV_BUILD
    engine.setInitialProperties({{"fullScreen", true}});
#endif

    // objectCreationFailed fires before loadFromModule returns when a QML
    // type fails to resolve or compile. Individual QML errors are already
    // routed through qtMessageHandler → tracing; this handler adds the
    // tying narrative ("the root object for Zaparoo.App.Main failed") so
    // a reader of launcher.log doesn't have to infer the connection.
    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreationFailed, &engine, [](const QUrl& url)
        { qCritical("QML object creation failed for %s", qUtf8Printable(url.toString())); });

    engine.loadFromModule("Zaparoo.App", "Main");

    if (engine.rootObjects().isEmpty())
    {
        qCritical("QML engine produced no root objects; startup aborted (see earlier errors)");
        return EXIT_FAILURE;
    }

    zaparoo_rust_post_qt_start();
    return QGuiApplication::exec();
}
