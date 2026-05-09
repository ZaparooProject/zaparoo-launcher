// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//
// Thin C++ entry point for the Rust launcher. Domain logic lives in the
// zaparoo_launcher_rs staticlib; Qt plugin wiring is handled here so that
// Qt's CMake (qt_import_qml_plugins) can emit the correct link flags.

#include "media_image_provider.h"
#include "native_video_writer.h"

#include <QByteArray>
#include <QFontDatabase>
#include <QGuiApplication>
#include <QImageReader>
#include <QList>
#include <QLocale>
#include <QPixmapCache>
#include <QQmlApplicationEngine>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QString>
#include <QStringList>
#include <QTranslator>
#include <QUrl>
#include <QVariantMap>
#include <QtQml/qqmlextensionplugin.h>
#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <vector>

// Default QPixmapCache cap is 10 MiB. With ~100 system PNGs decoded at
// 256 px sourceSize the working set straddles that limit, so navigating
// through every category evicts earlier system covers and re-decodes
// them on the next visit. Bumping to 50 MiB keeps the entire system-
// cover set resident across category swaps for the cost of a one-time
// allocation — a worthwhile trade on MiSTer's 1 GiB DDR3 since
// pixmap decode on the UI thread is the visible "pop in" the user
// flagged.
constexpr int kPixmapCacheLimitKiB = 50 * 1024;

extern "C" int zaparoo_rust_init(bool crtNativePathForced);
extern "C" void zaparoo_rust_post_qt_start();
extern "C" void zaparoo_log_qt(uint8_t level, const char* msg, size_t len);
extern "C" const char* zaparoo_rust_language_code();
extern "C" bool zaparoo_rust_crt_native_path_enabled();
extern "C" uint32_t zaparoo_rust_video_width();
extern "C" uint32_t zaparoo_rust_video_height();

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
Q_IMPORT_PLUGIN(QSvgPlugin)
#endif

// Forward all Qt log messages to the Rust tracing registry (same sinks as
// Rust-side log output: stderr + launcher.log). Installed after
// zaparoo_rust_init() so the tracing subscriber is already alive.
static void qtMessageHandler(QtMsgType type, const QMessageLogContext& /*ctx*/, const QString& msg)
{
    const QByteArray utf8 = msg.toUtf8();
    zaparoo_log_qt(static_cast<uint8_t>(type), utf8.constData(), static_cast<size_t>(utf8.size()));
}

struct ParsedArguments
{
    bool crtNativePathForced = false;
    std::vector<char*> argv;
};

static ParsedArguments extractCrtArgument(int argc, char* argv[])
{
    ParsedArguments parsed;
    parsed.argv.reserve(static_cast<size_t>(argc));
    std::copy_n(argv, argc, std::back_inserter(parsed.argv));

    std::vector<char*> filtered;
    filtered.reserve(parsed.argv.size());
    if (!parsed.argv.empty())
    {
        filtered.push_back(parsed.argv.front());
    }

    for (size_t i = 1; i < parsed.argv.size(); ++i)
    {
        if (std::strcmp(parsed.argv[i], "--crt") == 0)
        {
            parsed.crtNativePathForced = true;
            continue;
        }
        filtered.push_back(parsed.argv[i]);
    }

    parsed.argv = std::move(filtered);
    parsed.argv.push_back(nullptr);
    return parsed;
}

int main(int argc, char* argv[])
{
    ParsedArguments parsedArgs = extractCrtArgument(argc, argv);
    const bool crtNativePathForced = parsedArgs.crtNativePathForced;
    int qtArgc = static_cast<int>(parsedArgs.argv.size()) - 1;
    char** qtArgv = parsedArgs.argv.data();
    qInfo("CRT startup decision: --crt argument %s", crtNativePathForced ? "present" : "absent");

    QGuiApplication::setApplicationName("Zaparoo Launcher");
    QGuiApplication::setApplicationVersion("0.1.0");
    QGuiApplication::setOrganizationName("Zaparoo");
    QGuiApplication::setOrganizationDomain("zaparoo.org");

    if (zaparoo_rust_init(crtNativePathForced) != 0)
    {
        return EXIT_FAILURE;
    }

    // Install after zaparoo_rust_init() so tracing is live before any Qt
    // messages are emitted.
    qInstallMessageHandler(qtMessageHandler);

    QGuiApplication app(qtArgc, qtArgv);
    QPixmapCache::setCacheLimit(kPixmapCacheLimitKiB);
    // addApplicationFont returns -1 on failure (broken qrc path,
    // unreadable file). Logging the failure mode keeps a refactor that
    // breaks the resource alias from silently degrading to the default
    // font with no clue in the logs.
    const auto registerFont = [](const QString& path)
    {
        const int fontId = QFontDatabase::addApplicationFont(path);
        if (fontId == -1)
        {
            qWarning("Failed to register font: %s", qUtf8Printable(path));
            return;
        }
        qInfo("Registered font %s: %s", qUtf8Printable(path),
              qUtf8Printable(QFontDatabase::applicationFontFamilies(fontId).join(", ")));
    };
    registerFont(
        QStringLiteral(":/qt/qml/Zaparoo/App/resources/fonts/AtkinsonHyperlegible-Regular.ttf"));
    registerFont(
        QStringLiteral(":/qt/qml/Zaparoo/App/resources/fonts/AtkinsonHyperlegible-Bold.ttf"));
    registerFont(QStringLiteral(":/qt/qml/Zaparoo/App/resources/fonts/Bongo-8 Mono.ttf"));
    const bool crtNativePathEnabled = zaparoo_rust_crt_native_path_enabled();
    qInfo("CRT startup decision: Rust CRT native path %s",
          crtNativePathEnabled ? "enabled" : "disabled");
    if (crtNativePathEnabled)
    {
        QQuickWindow::setTextRenderType(QQuickWindow::NativeTextRendering);
        qInfo("CRT native path: using native text rendering");
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
    // Engine takes ownership of the provider — it deletes it when the
    // engine is destroyed at process shutdown. The provider is the
    // bridge from `image://media-image/<encoded>` URLs to the
    // Rust-side in-memory media image cache, so it must be installed
    // before any QML type binds to a `coverKey` (every Tile inside
    // MainLayout does).
    // NOLINTNEXTLINE(cppcoreguidelines-owning-memory)
    engine.addImageProvider(QStringLiteral("media-image"), new MediaImageProvider());

    // One-shot diagnostic: a static MiSTer Qt build configured without
    // `-feature-png` / libpng silently lacks the PNG QImageIOHandler, so
    // `QImage::loadFromData(<png bytes>)` returns null and every cover
    // looks "missing" with no other signal. Logging the registered
    // formats at startup turns that failure mode into one decisive line.
    QStringList formatNames;
    const QList<QByteArray> supportedFormats = QImageReader::supportedImageFormats();
    formatNames.reserve(supportedFormats.size());
    for (const QByteArray& fmt : supportedFormats)
    {
        formatNames << QString::fromLatin1(fmt);
    }
    qInfo("QImageReader supportedImageFormats: %s",
          qUtf8Printable(formatNames.join(QStringLiteral(", "))));

    QVariantMap initialProperties = {
        {"crtNativePath", crtNativePathEnabled},
    };
#ifdef ZAPAROO_EMBEDDED_BUILD
    initialProperties.insert(QStringLiteral("fullScreen"), true);
#else
    // Desktop CRT preview: when --crt is passed off-MiSTer, render the
    // QML scene at the configured logical video size and integer-
    // upscale via a layered wrapper Item in MainLayout. Scale defaults
    // to 0 (sentinel for "auto-pick the largest integer that fits the
    // primary screen with a 5% margin"); ZAPAROO_CRT_PREVIEW_SCALE
    // overrides for ad-hoc testing without rebuilding (e.g. =2 for
    // half-size, =8 to inspect a single tile).
    if (zaparoo_rust_crt_native_path_enabled())
    {
        int previewScale = 0;
        const QByteArray envScale = qgetenv("ZAPAROO_CRT_PREVIEW_SCALE");
        if (!envScale.isEmpty())
        {
            bool ok = false;
            const int parsed = envScale.toInt(&ok);
            if (ok && parsed > 0)
            {
                previewScale = parsed;
            }
        }
        initialProperties.insert(QStringLiteral("crtPreview"), true);
        initialProperties.insert(QStringLiteral("crtPreviewScale"), previewScale);
        initialProperties.insert(QStringLiteral("videoWidth"),
                                 static_cast<int>(zaparoo_rust_video_width()));
        initialProperties.insert(QStringLiteral("videoHeight"),
                                 static_cast<int>(zaparoo_rust_video_height()));
    }
#endif
    engine.setInitialProperties(initialProperties);

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

    if (crtNativePathEnabled)
    {
        qInfo("CRT startup decision: starting native video writer");
        startNativeVideoWriter();
        std::atexit(stopNativeVideoWriter);
    }
    else
    {
        qInfo("CRT startup decision: skipping native video writer");
    }

    zaparoo_rust_post_qt_start();
    return QGuiApplication::exec();
}
